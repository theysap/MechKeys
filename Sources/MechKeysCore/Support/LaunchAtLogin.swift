import Foundation
import OSLog
import ServiceManagement

/// Launch-at-login via `SMAppService`, the modern replacement for login-item
/// shell hacks and `SMLoginItemSetEnabled`.
///
/// Requires the app to be in a bundle with a stable identifier; running the
/// bare executable out of `.build` will report `.notFound`.
public enum LaunchAtLogin {

    private static let logger = Logger(subsystem: "com.mechkeys.app", category: "LaunchAtLogin")

    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when macOS says the user has disabled the item in System Settings,
    /// which we must not silently fight.
    public static var isBlockedByUser: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    public static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "Enabled"
        case .requiresApproval: return "Needs approval in System Settings"
        case .notFound: return "Unavailable (run the built app bundle)"
        case .notRegistered: return "Disabled"
        @unknown default: return "Unknown"
        }
    }

    /// Returns the state actually achieved, which may differ from what was
    /// asked for if the user has blocked the login item.
    @discardableResult
    public static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                guard SMAppService.mainApp.status != .enabled else { return true }
                try SMAppService.mainApp.register()
            } else {
                guard SMAppService.mainApp.status == .enabled else { return false }
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
        }
        return isEnabled
    }
}
