import AppKit
import SwiftUI

/// The application scene.
///
/// A single `MenuBarExtra` in `.window` style, which is the modern way to get
/// a popover hanging off a menu bar icon without hand-rolling an
/// `NSStatusItem` and an `NSPopover`. Everything larger opens as a real window
/// through `AppDelegate`.
public struct MechKeysApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    public init() {}

    public var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                controller: appDelegate.controller,
                onConfigure: { appDelegate.showConfiguration() },
                onQuit: { NSApp.terminate(nil) }
            )
        } label: {
            MenuBarIcon(
                isActive: appDelegate.controller.settingsStore.settings.isEnabled
                    && appDelegate.controller.isListening,
                showsState: appDelegate.controller.settingsStore.settings.showsMenuBarStateInIcon
            )
        }
        .menuBarExtraStyle(.window)
    }
}
