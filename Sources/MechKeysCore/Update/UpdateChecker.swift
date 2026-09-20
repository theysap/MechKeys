import AppKit
import Foundation
import Observation

/// Looks for a newer release, and installs one when asked.
///
/// Checking is cheap and quiet: one request to the GitHub releases API a few
/// seconds after launch and every six hours after, and only while the user
/// leaves that switched on. Nothing is downloaded until the user presses
/// Download & Restart, and nothing is installed that does not match the
/// checksum published with it.
///
/// This is the app's only network code path. It sends nothing — no
/// identifiers, no analytics — and reads one public JSON document.
@MainActor
@Observable
public final class UpdateChecker {

    /// Why an attempt stopped, and what pressing Retry should do about it.
    public struct Failure: Equatable, Sendable {
        public var message: String
        public var retry: Retry

        public enum Retry: Equatable, Sendable {
            /// The check itself failed; look again.
            case check
            /// The download or the install failed; try that same release again.
            case install(AppRelease)
        }
    }

    public enum State: Equatable, Sendable {
        case idle
        case checking
        case upToDate
        case available(AppRelease)
        case downloading(Double)
        case installing
        case failed(Failure)
    }

    public private(set) var state: State = .idle

    /// When the newest release was last looked for, so the UI can say.
    public private(set) var lastChecked: Date?

    /// Set on the first launch after an update replaced the running copy, so
    /// the app can confirm what happened. Cleared once it has been shown.
    public var installedVersion: AppVersion?

    @ObservationIgnored
    private let store: SettingsStore
    @ObservationIgnored
    private let defaults: UserDefaults
    @ObservationIgnored
    private let feed: URL
    @ObservationIgnored
    private var timer: Task<Void, Never>?
    @ObservationIgnored
    private var work: Task<Void, Never>?

    /// Where the running copy's version was recorded at its last launch.
    ///
    /// Deliberately not part of `AppSettings`: that value is snapshotted and
    /// restored by "Revert Changes", and reverting a piece of bookkeeping
    /// would make the app announce an update that had already been announced.
    static let lastRunVersionKey = "update.lastRunVersion"

    /// The releases API for the repository MechKeys is published from.
    public static let defaultFeed = URL(
        string: "https://api.github.com/repos/theysap/MechKeys/releases/latest")!

    public init(store: SettingsStore, defaults: UserDefaults = .standard, feed: URL? = nil) {
        self.store = store
        self.defaults = defaults

        // Lets the whole path — check, download, verify, install, relaunch —
        // be exercised against a local server instead of a real release.
        let override = ProcessInfo.processInfo.environment["MECHKEYS_UPDATE_FEED"]
            .flatMap(URL.init(string:))
        self.feed = feed ?? override ?? Self.defaultFeed
    }

    deinit {
        timer?.cancel()
        work?.cancel()
    }

    /// Whether this copy can update itself at all. A `swift build` binary
    /// cannot: there is no bundle to replace.
    public var canInstall: Bool { UpdateInstaller.installedBundle != nil }

    public var availableRelease: AppRelease? {
        if case .available(let release) = state { return release }
        return nil
    }

    public var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: true
        case .idle, .upToDate, .available, .failed: false
        }
    }

    // MARK: - Launch

    /// Notes the version this launch is running as, and reports the one it
    /// replaced if an update landed.
    ///
    /// The installer swaps the bundle and relaunches it, so nothing survives
    /// in memory to say what happened; the version the app last ran as is
    /// recorded instead, and a launch that finds a newer one is an update that
    /// arrived.
    public func recordLaunch() {
        let previous = defaults.string(forKey: Self.lastRunVersionKey).flatMap(AppVersion.init)
        let current = AppVersion.current

        installedVersion = UpdateAnnouncement.installedVersion(
            current: current, previous: previous)

        if let current {
            defaults.set(current.description, forKey: Self.lastRunVersionKey)
        }
    }

    /// Starts the background schedule. Safe to call more than once.
    public func start() {
        guard timer == nil else { return }

        timer = Task { [weak self] in
            // Not on the very first moment of launch: getting the audio engine
            // up and the tap running matters more.
            try? await Task.sleep(for: .seconds(10))
            while !Task.isCancelled {
                if self?.store.settings.checksForUpdatesAutomatically == true {
                    await self?.check(userInitiated: false)
                }
                try? await Task.sleep(for: .seconds(6 * 60 * 60))
            }
        }
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        work?.cancel()
        work = nil
    }

    // MARK: - Checking

    public func check(userInitiated: Bool) async {
        guard !isBusy else { return }
        // A background tick should not overwrite an answer the user is
        // currently looking at.
        if case .available = state, !userInitiated { return }

        state = .checking
        defer { lastChecked = .now }

        do {
            let release = try await newestRelease()
            guard let release, let current = AppVersion.current else {
                // No release yet, or a development build with no version to
                // compare against. Either way there is nothing to offer.
                state = .upToDate
                return
            }

            if release.version > current {
                AppLog.update.notice(
                    "Update available: \(release.version.description, privacy: .public)")
                state = .available(release)
            } else {
                state = .upToDate
            }
        } catch {
            AppLog.update.info(
                "Update check failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(Failure(message: error.localizedDescription, retry: .check))
        }
    }

    private func newestRelease() async throws -> AppRelease? {
        var request = URLRequest(url: feed)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            // A repository with no releases answers 404, which is not a
            // failure worth showing anyone.
            return nil
        }

        return try JSONDecoder().decode(GitHubRelease.self, from: data).release
    }

    // MARK: - Installing

    /// Downloads the available release, verifies it, puts it in place of this
    /// copy and restarts.
    public func installAvailableUpdate() {
        guard let release = availableRelease else { return }
        install(release)
    }

    /// Retries whatever failed. Does nothing unless the state is a failure.
    public func retry() {
        guard case .failed(let failure) = state else { return }
        switch failure.retry {
        case .check:
            state = .idle
            Task { await check(userInitiated: true) }
        case .install(let release):
            install(release)
        }
    }

    private func install(_ release: AppRelease) {
        guard work == nil else { return }

        work = Task { [weak self] in
            guard let self else { return }
            self.state = .downloading(0)

            do {
                try await UpdateInstaller.install(release) { [weak self] fraction in
                    Task { @MainActor in
                        // Only while the download is still the current state:
                        // a cancelled or failed attempt must not be dragged
                        // back onto the progress bar by a late callback.
                        guard let self, case .downloading = self.state else { return }
                        self.state = .downloading(fraction)
                    }
                }
                self.state = .installing
                // The replacement is done and the relaunch is scheduled; this
                // copy has to go so the new one can take over.
                NSApplication.shared.terminate(nil)
            } catch {
                AppLog.update.error(
                    "Update failed: \(error.localizedDescription, privacy: .public)")
                self.state = .failed(
                    Failure(message: error.localizedDescription, retry: .install(release)))
            }

            self.work = nil
        }
    }

    /// Forces a state, so `--update-panel` can put each answer on screen
    /// without waiting for a release that happens to be newer, or for a
    /// download that happens to fail. Nothing else calls this.
    func preview(_ state: State) {
        self.state = state
    }

    /// Puts the checker back to rest. Called when the panel is dismissed, so
    /// that the next check starts from a clean state rather than from an
    /// answer nobody is looking at any more.
    public func dismiss() {
        switch state {
        case .upToDate, .failed, .available, .idle:
            state = .idle
        case .checking, .downloading, .installing:
            // Work in flight is left alone; closing the panel is not cancelling.
            break
        }
    }
}

/// Whether this launch is the first one after an update installed itself.
enum UpdateAnnouncement {
    static func installedVersion(current: AppVersion?, previous: AppVersion?) -> AppVersion? {
        // No record means this is the first launch that kept one — a fresh
        // install, or the first run of the version that started recording.
        // Neither is an update worth announcing.
        guard let current, let previous, current > previous else { return nil }
        return current
    }
}
