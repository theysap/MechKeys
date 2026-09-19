import Foundation
import Observation

/// Wires the subsystems together and owns the app's runtime state.
///
/// ```
///   SettingsStore ──▶ MechKeysController ──▶ SoundEngine
///                            │           └─▶ KeyboardMonitor
///   PermissionManager ───────┘
/// ```
///
/// Nothing else in the app talks to the engine or the monitor directly: views
/// change settings, and settings changes flow down through here.
@MainActor
@Observable
public final class MechKeysController {

    public enum EngineStatus: Equatable, Sendable {
        case idle
        case running
        case failed(String)

        public var isHealthy: Bool { self == .running }
    }

    public let settingsStore: SettingsStore
    public let permissions: PermissionManager

    public private(set) var engineStatus: EngineStatus = .idle
    public private(set) var isListening = false

    @ObservationIgnored
    private let engine: any SoundEngine
    @ObservationIgnored
    private let monitor: KeyboardMonitor

    /// Read from the monitor's thread on every keypress, so it is cached in a
    /// plain stored property rather than reached for through the store.
    @ObservationIgnored
    private nonisolated(unsafe) var currentProfile: SoundProfile = AppSettings.default.profile

    /// Dependencies are optional rather than defaulted, because default
    /// argument expressions are evaluated outside the actor and these types
    /// are main-actor isolated.
    public init(
        settingsStore: SettingsStore? = nil,
        permissions: PermissionManager? = nil,
        engine: (any SoundEngine)? = nil,
        monitor: KeyboardMonitor? = nil
    ) {
        self.settingsStore = settingsStore ?? SettingsStore()
        self.permissions = permissions ?? PermissionManager()
        self.engine = engine ?? AVSoundEngine()
        self.monitor = monitor ?? KeyboardMonitor()

        let engineRef = self.engine
        self.monitor.onKeyEvent = { [weak self] event in
            // Arrives on the monitor's thread. `play` only enqueues, so this
            // returns straight back to the event tap.
            guard let self else { return }
            engineRef.play(keyCategory: event.category, profile: self.currentProfile)
        }
    }

    // MARK: - Start-up

    /// Brings the audio engine up and starts listening if the user has the app
    /// switched on. Safe to call more than once.
    public func startUp() {
        startEngineIfNeeded()
        apply(settingsStore.settings)
        startFollowing()
    }

    public func shutDown() {
        monitor.stop()
        engine.stop()
        isListening = false
        engineStatus = .idle
    }

    /// Re-applies settings whenever any of them, or the permission state,
    /// changes. `follow` re-arms itself, so this is set up once.
    private func startFollowing() {
        follow { [weak self] in
            guard let self else { return }
            // Both reads are what register this closure for change tracking.
            let settings = self.settingsStore.settings
            _ = self.permissions.isTrusted
            self.apply(settings)
        }
    }

    // MARK: - Applying settings

    private func apply(_ settings: AppSettings) {
        currentProfile = settings.profile
        engine.apply(settings)
        monitor.update(from: settings)
        updateListening(settings)
    }

    private func startEngineIfNeeded() {
        guard !engine.isRunning else {
            engineStatus = .running
            return
        }
        do {
            try engine.start()
            engine.apply(settingsStore.settings)
            engineStatus = .running
        } catch {
            let message =
                (error as? SoundEngineError).map {
                    [$0.errorDescription, $0.recoverySuggestion].compactMap { $0 }.joined(
                        separator: " ")
                } ?? error.localizedDescription
            engineStatus = .failed(message)
            AppLog.audio.error("Audio engine unavailable: \(message, privacy: .public)")
        }
    }

    /// The event tap runs only when it is genuinely needed: the app is on, the
    /// user has finished onboarding, and permission exists. Otherwise it is
    /// fully torn down — not merely ignored.
    private func updateListening(_ settings: AppSettings) {
        let shouldListen =
            settings.isEnabled
            && settings.hasCompletedOnboarding
            && permissions.isTrusted

        if shouldListen {
            startEngineIfNeeded()
            if monitor.isRunning {
                isListening = true
            } else {
                isListening = monitor.start()
                if !isListening { permissions.refresh() }
            }
        } else {
            if monitor.isRunning { monitor.stop() }
            isListening = false
        }
    }

    // MARK: - Actions

    public func setEnabled(_ enabled: Bool) {
        settingsStore.settings.isEnabled = enabled
    }

    public func toggleEnabled() {
        setEnabled(!settingsStore.settings.isEnabled)
    }

    /// Plays one keypress on demand. Works even when the app is switched off,
    /// which is the point — you audition a profile before turning it on.
    public func playTestSound(category: KeyCategory = .standard) {
        startEngineIfNeeded()
        engine.play(keyCategory: category, profile: settingsStore.settings.profile)
    }

    public func completeOnboarding() {
        settingsStore.settings.hasCompletedOnboarding = true
    }

    public func requestKeyboardAccess() {
        if permissions.hasPrompted {
            permissions.openSystemSettings()
        } else {
            permissions.requestAccess()
        }
    }

    // MARK: - Status for the UI

    public var isReady: Bool {
        permissions.isTrusted && engineStatus.isHealthy
    }

    public var statusSummary: String {
        if case .failed(let message) = engineStatus { return message }
        if !permissions.isTrusted { return "Keyboard access is required." }
        if !settingsStore.settings.isEnabled { return "MechKeys is off." }
        return isListening ? "Listening for keystrokes." : "Starting…"
    }
}
