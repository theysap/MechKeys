import AppKit
import ApplicationServices
import Combine
import Foundation

/// Tracks the Accessibility permission that a global event tap requires.
///
/// macOS has no notification for "the user just granted Accessibility", so the
/// status is polled — but only while it is missing, and only while the app is
/// actually waiting for it. Once granted, polling stops for good.
@MainActor
public final class PermissionManager: ObservableObject {

    @Published public private(set) var isTrusted: Bool = false

    /// True once we have shown the system prompt, so we never nag twice.
    @Published public private(set) var hasPrompted: Bool = false

    private var pollTimer: Timer?
    private var activationObserver: NSObjectProtocol?

    public init() {
        isTrusted = Self.currentStatus()
        observeActivation()
        if !isTrusted { startPolling() }
    }

    deinit {
        pollTimer?.invalidate()
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    /// Checks trust without showing a prompt.
    ///
    /// `nonisolated` because the keyboard monitor checks this from its own
    /// thread before creating the tap; the underlying API is thread-safe.
    nonisolated public static func currentStatus() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    public func refresh() -> Bool {
        let status = Self.currentStatus()
        if status != isTrusted {
            isTrusted = status
        }
        if status {
            stopPolling()
        } else if pollTimer == nil {
            startPolling()
        }
        return status
    }

    /// Shows the system's own "grant Accessibility" prompt. Called only from a
    /// deliberate user action.
    public func requestAccess() {
        hasPrompted = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        startPolling()
    }

    /// Deep-links to Privacy & Security → Accessibility.
    public func openSystemSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        startPolling()
    }

    // MARK: - Polling

    private func startPolling() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // Tolerance lets the timer coalesce with other wakeups, so the idle
        // cost of waiting for permission is negligible.
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Returning from System Settings is the most likely moment for the status
    /// to have changed, so check immediately rather than waiting for the tick.
    private func observeActivation() {
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
}
