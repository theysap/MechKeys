import AppKit
import ApplicationServices
import Foundation
import Observation

/// Tracks the Accessibility permission that a global event tap requires.
///
/// macOS posts no notification when the user grants Accessibility, so the
/// status has to be polled — but only while it is missing. The moment it is
/// granted the polling task ends and never runs again.
///
/// Polling and the activation watch are both structured concurrency tasks
/// rather than a `Timer` and a `NotificationCenter` token: a `Task` is
/// `Sendable` and cancellable, so this type can clean itself up from a
/// nonisolated `deinit`, which main-actor-bound objects cannot.
@MainActor
@Observable
public final class PermissionManager {

    public private(set) var isTrusted: Bool = false

    /// True once the system prompt has been shown, so the user is never asked
    /// twice — the second time we send them to System Settings instead.
    public private(set) var hasPrompted: Bool = false

    @ObservationIgnored
    private var pollTask: Task<Void, Never>?
    @ObservationIgnored
    private var activationTask: Task<Void, Never>?

    /// How often to re-check while permission is missing.
    private static let pollInterval = Duration.seconds(1)

    /// The literal value of `kAXTrustedCheckOptionPrompt`.
    ///
    /// The imported constant is a global `var` of a non-Sendable type, which
    /// Swift 6 will not allow from a nonisolated context. The key's spelling
    /// is API and cannot change, so it is written out.
    nonisolated private static let promptOptionKey = "AXTrustedCheckOptionPrompt"

    public init() {
        isTrusted = Self.currentStatus()
        observeActivation()
        if !isTrusted { startPolling() }
    }

    deinit {
        pollTask?.cancel()
        activationTask?.cancel()
    }

    /// Checks trust without showing a prompt.
    ///
    /// `nonisolated` because the keyboard monitor checks this from its own
    /// thread before creating the tap; the underlying API is thread-safe.
    nonisolated public static func currentStatus() -> Bool {
        AXIsProcessTrustedWithOptions([promptOptionKey: false] as CFDictionary)
    }

    /// The result of the last deep check, for the UI to report.
    public enum VerifyResult: Equatable, Sendable {
        case granted
        /// A tap can be created even though the trust call says otherwise, or
        /// the other way round. Either way it works, and the stale answer has
        /// been corrected.
        case grantedAfterDisagreement
        case denied
    }

    public private(set) var lastVerification: VerifyResult?

    /// Checks by actually creating an event tap, not by asking TCC.
    ///
    /// Wired to the "Check Again" button, because the cheap trust call is the
    /// one that goes stale: it can report no permission for a process that
    /// would in fact be allowed to listen, and the only other way out of that
    /// state is relaunching the app.
    @discardableResult
    public func verify() -> VerifyResult {
        let trusted = Self.currentStatus()
        let canListen = KeyboardMonitor.canCreateTap()

        let result: VerifyResult
        if canListen {
            result = trusted ? .granted : .grantedAfterDisagreement
        } else {
            result = .denied
        }

        lastVerification = result
        // The tap test wins: it is the capability the app actually needs.
        if canListen != isTrusted { isTrusted = canListen }
        if canListen {
            pollTask?.cancel()
            pollTask = nil
        } else if pollTask == nil {
            startPolling()
        }
        return result
    }

    @discardableResult
    public func refresh() -> Bool {
        let status = Self.currentStatus()
        if status != isTrusted {
            isTrusted = status
        }
        if status {
            pollTask?.cancel()
            pollTask = nil
        } else if pollTask == nil {
            startPolling()
        }
        return status
    }

    /// Shows the system's own "grant Accessibility" prompt. Only ever called
    /// from a deliberate user action.
    public func requestAccess() {
        hasPrompted = true
        _ = AXIsProcessTrustedWithOptions([Self.promptOptionKey: true] as CFDictionary)
        startPolling()
    }

    /// Deep-links to Privacy & Security → Accessibility.
    public func openSystemSettings() {
        let urlString =
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        startPolling()
    }

    // MARK: - Watching

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard let self, !Task.isCancelled else { return }
                // refresh() cancels this task once permission arrives.
                if self.refresh() { return }
            }
        }
    }

    /// Returning from System Settings is the likeliest moment for the status
    /// to have changed, so check then rather than waiting for the next tick.
    private func observeActivation() {
        activationTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: NSApplication.didBecomeActiveNotification
            )
            for await _ in notifications {
                guard let self, !Task.isCancelled else { return }
                self.refresh()
            }
        }
    }
}
