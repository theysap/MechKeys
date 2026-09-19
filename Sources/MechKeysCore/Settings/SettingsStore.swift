import Foundation
import Observation
import ServiceManagement

/// Owns the one `AppSettings` value, keeps it on disk, and mirrors the login
/// item that the system owns.
///
/// The whole model is stored as a single JSON blob in `UserDefaults` rather
/// than as a scatter of individual keys, so a snapshot can be taken and
/// restored atomically — which is what "Revert Changes" in the configuration
/// window needs.
@MainActor
@Observable
public final class SettingsStore {

    public static let defaultsKey = "settings.v1"

    public var settings: AppSettings {
        didSet {
            guard !isNormalizing else { return }
            let normalized = settings.normalized()
            if normalized != settings {
                isNormalizing = true
                settings = normalized
                isNormalizing = false
            }
            persist()
        }
    }

    /// Mirrors the login item's registration.
    ///
    /// Not part of `AppSettings`: the state belongs to `SMAppService`, and
    /// persisting our own copy would only create something to disagree with.
    /// The user can also switch the item off in System Settings, and the app
    /// must show that rather than a stale `true`.
    public var launchAtLogin: Bool {
        didSet {
            guard !isApplyingLaunchAtLogin else { return }
            applyLaunchAtLogin()
        }
    }

    @ObservationIgnored
    private let defaults: UserDefaults
    @ObservationIgnored
    private var isNormalizing = false
    @ObservationIgnored
    private var isApplyingLaunchAtLogin = false
    @ObservationIgnored
    private var snapshot: AppSettings?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = Self.load(from: defaults) ?? .default
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Persistence

    private static func load(from defaults: UserDefaults) -> AppSettings? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        do {
            return try JSONDecoder().decode(AppSettings.self, from: data).normalized()
        } catch {
            // Settings we cannot read are not worth crashing over, and not
            // worth keeping either.
            AppLog.settings.error("Stored settings were unreadable; starting from defaults.")
            return nil
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(settings)
            defaults.set(data, forKey: Self.defaultsKey)
        } catch {
            AppLog.settings.error(
                "Could not save settings: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Launch at login

    public var launchAtLoginStatus: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "Enabled"
        case .requiresApproval: return "Needs approval in System Settings"
        case .notFound: return "Unavailable — run the built app bundle"
        case .notRegistered: return "Disabled"
        @unknown default: return "Unknown"
        }
    }

    private func applyLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if launchAtLogin {
                try service.register()
            } else {
                try service.unregister()
            }
            AppLog.app.info("Launch at login set to \(self.launchAtLogin)")
        } catch {
            // Registration needs a real application bundle, so this fails when
            // running the binary straight out of .build. Put the toggle back
            // rather than leaving it showing a state that is not true.
            AppLog.app.error(
                "Could not change login item: \(error.localizedDescription, privacy: .public)")
            isApplyingLaunchAtLogin = true
            launchAtLogin = service.status == .enabled
            isApplyingLaunchAtLogin = false
        }
    }

    // MARK: - Snapshot / revert

    /// Remembers the current state so the configuration window can undo a
    /// session's worth of fiddling.
    public func beginEditing() {
        snapshot = settings
    }

    public var canRevert: Bool {
        guard let snapshot else { return false }
        return snapshot != settings
    }

    public func revert() {
        guard let snapshot else { return }
        settings = snapshot
    }

    public func commit() {
        snapshot = settings
        persist()
    }

    public func resetToDefaults() {
        var fresh = AppSettings.default
        // Resetting the sound settings should not send the user back through
        // onboarding.
        fresh.hasCompletedOnboarding = settings.hasCompletedOnboarding
        settings = fresh
    }
}
