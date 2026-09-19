import Combine
import Foundation
import OSLog

/// Wires the four subsystems together and owns the app's runtime state.
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
public final class MechKeysController: ObservableObject {

    public enum EngineStatus: Equatable {
        case idle
        case running
        case failed(String)

        public var isHealthy: Bool { self == .running }
    }

    public let settingsStore: SettingsStore
    public let permissions: PermissionManager

    @Published public private(set) var engineStatus: EngineStatus = .idle
    @Published public private(set) var isListening = false
    @Published public private(set) var launchAtLoginStatus: String = LaunchAtLogin.statusDescription

    private let engine: SoundEngine
    private let monitor: KeyboardMonitor
    private let logger = Logger(subsystem: "com.mechkeys.app", category: "Controller")
    private var cancellables: Set<AnyCancellable> = []

    /// Dependencies are optional rather than defaulted, because default
    /// argument expressions are evaluated outside the actor and these types are
    /// main-actor isolated.
    public init(settingsStore: SettingsStore? = nil,
                permissions: PermissionManager? = nil,
                engine: SoundEngine? = nil,
                monitor: KeyboardMonitor? = nil) {
        self.settingsStore = settingsStore ?? SettingsStore()
        self.permissions = permissions ?? PermissionManager()
        self.engine = engine ?? AVSoundEngine()
        self.monitor = monitor ?? KeyboardMonitor()
        let monitor = self.monitor

        monitor.onKeyEvent = { [weak self] event in
            // Arrives on the monitor's thread. `play` only enqueues, so this
            // returns straight back to the event tap.
            guard let self else { return }
            self.engine.play(keyCategory: event.category, profile: self.currentProfile)
        }

        observe()
    }

    /// Read from the monitor's thread on every keypress, so it is cached here
    /// rather than reached for through the main-actor-isolated store.
    private var currentProfile: SoundProfile = AppSettings.default.profile

    // MARK: - Start-up

    /// Brings the audio engine up and starts listening if the user has the app
    /// switched on. Safe to call more than once.
    public func startUp() {
        startEngineIfNeeded()
        apply(settingsStore.settings)
    }

    public func shutDown() {
        monitor.stop()
        engine.stop()
        isListening = false
        engineStatus = .idle
    }

    private func observe() {
        currentProfile = settingsStore.settings.profile

        settingsStore.$settings
            .removeDuplicates()
            .sink { [weak self] settings in
                self?.apply(settings)
            }
            .store(in: &cancellables)

        permissions.$isTrusted
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateListening(self.settingsStore.settings)
            }
            .store(in: &cancellables)
    }

    // MARK: - Applying settings

    private func apply(_ settings: AppSettings) {
        currentProfile = settings.profile
        engine.apply(settings)
        monitor.update(from: settings)
        updateListening(settings)
        syncLaunchAtLogin(settings)
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
            let message = (error as? SoundEngineError).map {
                [$0.errorDescription, $0.recoverySuggestion].compactMap { $0 }.joined(separator: " ")
            } ?? error.localizedDescription
            engineStatus = .failed(message)
            logger.error("Audio engine unavailable: \(message, privacy: .public)")
        }
    }

    /// The event tap runs only when it is genuinely needed: the app is on, the
    /// user has finished onboarding, and permission exists. Otherwise it is
    /// fully torn down — not merely ignored.
    private func updateListening(_ settings: AppSettings) {
        let shouldListen = settings.isEnabled
            && settings.hasCompletedOnboarding
            && permissions.isTrusted

        if shouldListen {
            startEngineIfNeeded()
            if !monitor.isRunning {
                isListening = monitor.start()
                if !isListening { permissions.refresh() }
            } else {
                isListening = true
            }
        } else if monitor.isRunning {
            monitor.stop()
            isListening = false
        } else {
            isListening = false
        }
    }

    private func syncLaunchAtLogin(_ settings: AppSettings) {
        let actual = LaunchAtLogin.isEnabled
        guard actual != settings.launchAtLogin else {
            launchAtLoginStatus = LaunchAtLogin.statusDescription
            return
        }
        let achieved = LaunchAtLogin.setEnabled(settings.launchAtLogin)
        launchAtLoginStatus = LaunchAtLogin.statusDescription
        if achieved != settings.launchAtLogin {
            // macOS refused — most likely the user has the login item switched
            // off in System Settings. Reflect reality instead of lying.
            settingsStore.settings.launchAtLogin = achieved
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
