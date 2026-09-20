import AppKit
import SwiftUI

/// The floating panel that answers "check for updates".
///
/// It is a window rather than part of the popover because the popover is gone
/// the moment anything else takes focus — including this. A check started from
/// the menu bar therefore has nowhere in the popover to put its answer, so the
/// answer comes back here, in the same Liquid Glass material the popover is
/// made of.
struct UpdatePanelView: View {

    /// What the panel is here to say. Either it is following a check, or it is
    /// confirming an update that has already installed itself and restarted
    /// the app — which is not a checker state, because the checker that ran it
    /// no longer exists.
    enum Mode: Equatable {
        case check
        case installed(AppVersion)
    }

    let checker: UpdateChecker
    let mode: Mode
    var onDismiss: () -> Void

    @StateObject private var hovering = ViewState(false)

    private var currentVersion: String { AppInfo.versionDescription }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            trafficLights

            HStack(alignment: .top, spacing: 11) {
                icon
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }

            if case .downloading(let fraction) = checker.state, mode == .check {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .accessibilityLabel("Download progress")
                    .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
            }

            buttons
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .glassCard(cornerRadius: 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Software update")
    }

    // MARK: - Traffic lights

    /// Drawn rather than taken from the window.
    ///
    /// The panel has no title bar to put AppKit's own buttons in — the glass
    /// card defines its shape, and a real title bar would draw a grey strip
    /// across the top of it. So the three are drawn as content.
    ///
    /// Only the red one does anything: there is nothing to minimise a
    /// 320-point notice into and nothing to zoom it to. The other two are
    /// drawn in the grey macOS itself uses for a disabled window button,
    /// rather than in full colour, because a button that looks live and does
    /// nothing is worse than one that plainly looks off.
    private var trafficLights: some View {
        HStack(spacing: 8) {
            Button(action: onDismiss) {
                ZStack {
                    Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34))
                    // macOS only shows the glyph while the pointer is over
                    // the cluster, and only on the buttons that work.
                    if hovering.value {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.black.opacity(0.55))
                    }
                }
                .frame(width: 12, height: 12)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityHint("Dismisses this notice.")

            ForEach([0, 1], id: \.self) { _ in
                Circle()
                    .fill(Color.secondary.opacity(0.28))
                    .frame(width: 12, height: 12)
            }
            .accessibilityHidden(true)

            Spacer(minLength: 0)
        }
        .onHover { hovering.value = $0 }
    }

    // MARK: - Content

    @ViewBuilder
    private var icon: some View {
        switch presentation {
        case .working:
            ProgressView()
                .controlSize(.small)
                .frame(width: 18, height: 18)
        case .symbol(let name, let tint):
            Image(systemName: name)
                .font(.system(size: 17))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
        }
    }

    private enum Presentation {
        case working
        case symbol(String, Color)
    }

    private var presentation: Presentation {
        if case .installed = mode { return .symbol("checkmark.seal.fill", .green) }

        switch checker.state {
        case .checking, .downloading, .installing:
            return .working
        case .upToDate:
            return .symbol("checkmark.circle.fill", .green)
        case .available:
            return .symbol("arrow.down.circle.fill", .accentColor)
        case .failed:
            return .symbol("exclamationmark.triangle.fill", .orange)
        case .idle:
            return .symbol("arrow.clockwise.circle.fill", .secondary)
        }
    }

    private var title: String {
        if case .installed(let version) = mode { return "Updated to \(version)" }

        switch checker.state {
        case .checking: return "Checking for updates…"
        case .upToDate: return "You're up to date"
        case .available: return "Update available"
        case .downloading: return "Downloading update"
        case .installing: return "Installing…"
        case .failed: return "Update failed"
        case .idle: return "Check for updates"
        }
    }

    private var detail: String {
        if case .installed = mode { return "MechKeys restarted with the new version." }

        switch checker.state {
        case .checking:
            return "Looking for a newer release of MechKeys."
        case .upToDate:
            return "MechKeys \(currentVersion) is the latest version."
        case .available(let release):
            return canInstall
                ? "Version \(release.version) is available. You have \(currentVersion)."
                : """
                Version \(release.version) is available. This copy is running \
                outside an application bundle, so it cannot replace itself — \
                download it from GitHub instead.
                """
        case .downloading(let fraction):
            return "\(Int((fraction * 100).rounded()))% of the disk image."
        case .installing:
            return "Replacing MechKeys and restarting."
        case .failed(let failure):
            return failure.message
        case .idle:
            return "MechKeys \(currentVersion)."
        }
    }

    private var canInstall: Bool { checker.canInstall }

    // MARK: - Buttons

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: 8) {
            Spacer()

            if case .installed = mode {
                dismissButton("OK", prominent: true)
            } else {
                switch checker.state {
                case .checking, .downloading, .installing:
                    // Nothing to press: pulling the bundle out from under a
                    // half-finished replacement is the one thing worth not
                    // offering.
                    EmptyView()

                case .upToDate, .idle:
                    dismissButton("OK", prominent: true)

                case .available:
                    dismissButton("Later", prominent: false)
                    Button("Download & Restart") {
                        checker.installAvailableUpdate()
                    }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canInstall)
                    .accessibilityHint(
                        "Downloads the update, verifies it, and restarts MechKeys.")

                case .failed:
                    dismissButton("Close", prominent: false)
                    Button("Retry") { checker.retry() }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityHint("Tries the update again.")
                }
            }
        }
    }

    /// The prominent form is the only button in the panel and carries Return;
    /// the quiet form sits beside a prominent one and carries Escape.
    @ViewBuilder
    private func dismissButton(_ title: String, prominent: Bool) -> some View {
        if prominent {
            Button(title, action: onDismiss)
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        } else {
            Button(title, action: onDismiss)
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)
        }
    }
}

// MARK: - The window

/// A panel that can take the keyboard, so Return and Escape work on the
/// buttons inside it. A borderless `NSPanel` refuses to become key by default.
private final class GlassPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// Escape closes the panel.
    ///
    /// AppKit routes Escape to `performClose:`, which looks for a real close
    /// button and beeps when it cannot find one. This panel's close button is
    /// drawn inside the glass, so the window has to answer for itself.
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

/// Owns the update panel's window.
///
/// Separate from `AppWindowController`, which keeps exactly one window and
/// would otherwise close the configuration window to show this.
@MainActor
final class UpdatePanelController: NSObject, NSWindowDelegate {

    private var panel: NSPanel?
    private var hosting: NSHostingController<UpdatePanelView>?
    /// Held so that closing by the window's own button resets the checker the
    /// same way the panel's Later / OK / Close buttons do. Weak because the
    /// controller owns it, not this.
    private weak var checker: UpdateChecker?

    func show(checker: UpdateChecker, mode: UpdatePanelView.Mode) {
        self.checker = checker
        let view = UpdatePanelView(checker: checker, mode: mode) { [weak self] in
            checker.dismiss()
            self?.close()
        }

        if let hosting {
            hosting.rootView = view
            panel?.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let controller = NSHostingController(rootView: view)
        // The panel is as tall as its content, and the content's height
        // depends on which answer arrived.
        controller.sizingOptions = [.preferredContentSize]

        let panel = GlassPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 140),
            styleMask: [.titled, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = controller
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        // None of AppKit's own buttons: the panel draws its own, inside the
        // glass, because there is no title bar for these to sit in.
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        // The glass draws the panel's surface; anything underneath it would
        // show as a grey rectangle behind the rounded corners.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.center()

        // An accessory application never comes forward on its own, and an
        // answer the user just asked for should not arrive behind their
        // editor.
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)

        self.panel = panel
        self.hosting = controller
    }

    func close() {
        panel?.close()
        panel = nil
        hosting = nil
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func windowWillClose(_ notification: Notification) {
        // Covers the close button and Escape, neither of which goes through
        // the SwiftUI buttons. `dismiss` leaves work in flight alone, so
        // closing a download does not cancel it.
        checker?.dismiss()
        panel = nil
        hosting = nil
    }
}
