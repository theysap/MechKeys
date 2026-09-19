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

        if !controller.settingsStore.settings.hasCompletedOnboarding {
            showOnboarding()
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
            content: ConfigurationView(controller: controller) { [weak self] in
                self?.windows.close()
            }
        )
    }

    /// The menu bar popover, in an ordinary window, for capture and QA.
    public func showPopoverPreview() {
        windows.show(
            title: "MechKeys",
            takesFocus: true,
            content: MenuBarView(controller: controller).padding(.vertical, 4)
        )
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
