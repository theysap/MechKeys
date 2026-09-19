import Combine
import Foundation
import OSLog

/// Owns the one `AppSettings` value and keeps it on disk.
///
/// The whole model is stored as a single JSON blob in `UserDefaults` rather
/// than as a scatter of individual keys, so that a snapshot can be taken and
/// restored atomically — which is what "Revert Changes" in the configuration
/// window needs.
@MainActor
public final class SettingsStore: ObservableObject {

    public static let defaultsKey = "settings.v1"

    @Published public var settings: AppSettings {
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

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.mechkeys.app", category: "Settings")
    private var isNormalizing = false
    private var snapshot: AppSettings?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = Self.load(from: defaults) ?? .default
    }

    // MARK: - Persistence

    private static func load(from defaults: UserDefaults) -> AppSettings? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        do {
            return try JSONDecoder().decode(AppSettings.self, from: data).normalized()
        } catch {
            // A settings file we cannot read is not worth crashing over, and
            // not worth keeping either.
            Logger(subsystem: "com.mechkeys.app", category: "Settings")
                .error("Stored settings were unreadable; starting from defaults.")
            return nil
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(settings)
            defaults.set(data, forKey: Self.defaultsKey)
        } catch {
            logger.error("Could not save settings: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Snapshot / revert

    /// Remembers the current state so the configuration window can offer to
    /// undo a session's worth of fiddling.
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
        // Resetting the sound settings should not throw away the two things
        // the user set up once and would be annoyed to redo.
        fresh.hasCompletedOnboarding = settings.hasCompletedOnboarding
        fresh.launchAtLogin = settings.launchAtLogin
        settings = fresh
    }
}
