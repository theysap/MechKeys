import AppKit
import SwiftUI

/// Owns the app's single auxiliary window.
///
/// The configuration window and the onboarding flow are ordinary AppKit
/// windows hosting SwiftUI, rather than SwiftUI `Window` scenes. In a
/// menu-bar-only app that is the simpler path: opening a scene from outside a
/// view hierarchy is awkward, and an `LSUIElement` process has to activate
/// itself deliberately or the window opens behind whatever the user is doing.
@MainActor
final class AppWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?

    /// Presents the window.
    ///
    /// `takesFocus` distinguishes the two ways a window gets opened here. The
    /// configuration window is opened from the menu bar, while the user is
    /// very likely mid-sentence in something else, so it activates politely
    /// and does not yank the keyboard away. Onboarding is shown because the
    /// user just launched the app and is waiting to see it, so it insists.
    func show(title: String, takesFocus: Bool = false, content: some View) {
        if let window {
            window.title = title
            activate(aggressively: takesFocus)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: AnyView(content))
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        // An accessory application never becomes active on its own, so without
        // this the window arrives visible but behind whatever the user was
        // looking at, and not even key.
        activate(aggressively: takesFocus)
        window.makeKeyAndOrderFront(nil)

        self.window = window
    }

    private func activate(aggressively: Bool) {
        if aggressively {
            // Deprecated, and deservedly so, but it is the only call that
            // reliably brings an accessory app's window in front of the
            // application the user is currently looking at. Reserved for the
            // first-launch welcome window, which the user is expecting.
            NSApp.activate(ignoringOtherApps: true)
        } else {
            NSApp.activate()
        }
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

/// Application lifecycle.
///
/// Holds the controller, so the SwiftUI scene and the windows share one.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {

    public let controller = MechKeysController()
    private let windows = AppWindowController()
    /// The update panel keeps its own window: it has to be able to appear over
    /// the configuration window rather than replacing it.
    private let updatePanel = UpdatePanelController()

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon, no app menu. Also set in Info.plist as
        // LSUIElement; doing it here as well means running the executable
        // straight out of .build behaves the same way.
        NSApp.setActivationPolicy(.accessory)

        controller.startUp()

        // Open a window straight away, so the interface can be looked at and
        // captured without clicking through the menu bar. Capturing a menu bar
        // popover otherwise needs screen-recording permission, which makes it
        // awkward to inspect any other way. Used by the QA pass and to render
        // the images in the README.
        if CommandLine.arguments.contains("--configure") {
            showConfiguration()
            return
        }
        if CommandLine.arguments.contains("--onboarding") {
            showOnboarding()
            return
        }
        if CommandLine.arguments.contains("--popover") {
            showPopoverPreview()
            return
        }
        if let state = Self.requestedUpdatePanel() {
            showUpdatePanelPreview(state)
            return
        }

        // Reports what the app can actually see about its own access, and
        // exits. Diagnosing "I granted it and it still says no" from the
        // outside is guesswork; this asks the process itself.
        if CommandLine.arguments.contains("--diagnose") {
            print(Diagnostics.report())
            NSApp.terminate(nil)
            return
        }

        if !controller.settingsStore.settings.hasCompletedOnboarding {
            showOnboarding()
        }

        announceInstalledUpdate()
        watchForBackgroundUpdates()
    }

    /// Confirms an update that has already replaced the app and restarted it.
    ///
    /// Also re-checks keyboard access, because the grant is keyed to the code
    /// signature: if a release were ever signed with a different identity, the
    /// tap would stop working silently, and the popover's banner should say so
    /// rather than the app just going quiet.
    private func announceInstalledUpdate() {
        guard let version = controller.updates.installedVersion else { return }
        controller.updates.installedVersion = nil
        controller.verifyKeyboardAccess()
        updatePanel.show(checker: controller.updates, mode: .installed(version))
    }

    /// Brings the panel up when a check nobody was watching finds something.
    ///
    /// A background check is silent until it has news; this is the one state
    /// worth interrupting for, and only when the panel is not already showing
    /// it.
    private func watchForBackgroundUpdates() {
        follow { [weak self] in
            guard let self else { return }
            guard case .available = self.controller.updates.state else { return }
            guard !self.updatePanel.isVisible else { return }
            self.updatePanel.show(checker: self.controller.updates, mode: .check)
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        controller.shutDown()
    }

    /// The app has no windows of its own most of the time; clicking the Dock
    /// icon (when one is shown) or re-opening should bring up configuration.
    public func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows: Bool
    ) -> Bool {
        showConfiguration()
        return true
    }

    // MARK: - Windows

    public func showConfiguration() {
        windows.show(
            title: "MechKeys",
            content: ConfigurationView(
                controller: controller,
                onClose: { [weak self] in self?.windows.close() },
                onCheckForUpdates: { [weak self] in self?.checkForUpdates() }
            )
        )
    }

    /// The menu bar popover, in an ordinary window, for capture and QA.
    public func showPopoverPreview() {
        windows.show(
            title: "MechKeys",
            takesFocus: true,
            content: MenuBarView(
                controller: controller,
                onConfigure: { [weak self] in self?.showConfiguration() },
                onCheckForUpdates: { [weak self] in self?.checkForUpdates() }
            )
            .padding(.vertical, 4)
        )
    }

    /// Opens the panel and looks for a newer release.
    ///
    /// The panel goes up first, in its "checking" state, so that the answer
    /// arrives in something the user is already looking at — the popover this
    /// was clicked in closes the moment the panel takes focus.
    public func checkForUpdates() {
        updatePanel.show(checker: controller.updates, mode: .check)
        Task { await controller.updates.check(userInitiated: true) }
    }

    /// `--update-panel <state>`: puts one update answer on screen without
    /// waiting for a real release. Used by the QA pass and to render the
    /// images in the README.
    private static func requestedUpdatePanel() -> UpdateChecker.State? {
        guard let flag = CommandLine.arguments.firstIndex(of: "--update-panel") else { return nil }
        let next = CommandLine.arguments.index(after: flag)
        let name = next < CommandLine.arguments.endIndex ? CommandLine.arguments[next] : "available"

        let release = AppRelease(
            version: AppVersion(major: 1, minor: 0, patch: 0),
            notes: "",
            diskImage: URL(string: "https://example.invalid/MechKeys-1.0.0.dmg")!,
            checksums: URL(string: "https://example.invalid/SHA256SUMS.txt")!
        )

        switch name {
        case "up-to-date": return .upToDate
        case "checking": return .checking
        case "downloading": return .downloading(0.42)
        case "failed":
            return .failed(
                UpdateChecker.Failure(
                    message: "The Internet connection appears to be offline.", retry: .check))
        default: return .available(release)
        }
    }

    private func showUpdatePanelPreview(_ state: UpdateChecker.State) {
        controller.updates.preview(state)
        updatePanel.show(checker: controller.updates, mode: .check)
    }

    public func showOnboarding() {
        windows.show(
            title: "Welcome to MechKeys",
            takesFocus: true,
            content: OnboardingView(controller: controller) { [weak self] in
                self?.windows.close()
            }
        )
    }
}
