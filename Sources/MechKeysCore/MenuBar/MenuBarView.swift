import SwiftUI

/// The menu bar icon.
///
/// Deliberately plain: an SF Symbol with a filled and an outlined state, which
/// is the convention every other menu bar utility follows. Anything more
/// elaborate reads as noise at 16 points.
public struct MenuBarIcon: View {
    let isActive: Bool
    let showsState: Bool

    public init(isActive: Bool, showsState: Bool) {
        self.isActive = isActive
        self.showsState = showsState
    }

    public var body: some View {
        Image(systemName: (isActive && showsState) ? "keyboard.fill" : "keyboard")
            .accessibilityLabel(isActive ? "MechKeys, on" : "MechKeys, off")
    }
}

/// The popover behind the menu bar icon.
///
/// Holds only what is worth reaching for mid-task: the switch, the two
/// sliders, and a way to hear the result. Everything else lives in the
/// configuration window.
public struct MenuBarView: View {

    let controller: MechKeysController
    @Bindable var store: SettingsStore

    public var onConfigure: () -> Void
    public var onQuit: () -> Void

    private var permissions: PermissionManager { controller.permissions }

    public init(
        controller: MechKeysController,
        onConfigure: @escaping () -> Void = {},
        onQuit: @escaping () -> Void = {}
    ) {
        self.controller = controller
        self._store = Bindable(wrappedValue: controller.settingsStore)
        self.onConfigure = onConfigure
        self.onQuit = onQuit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if case .failed(let message) = controller.engineStatus {
                banner(message, symbol: "speaker.slash.fill", tint: .red, action: nil)
            } else if !permissions.isTrusted {
                banner(
                    "MechKeys can't hear keys without Accessibility permission.",
                    symbol: "exclamationmark.triangle.fill",
                    tint: .orange,
                    action: { controller.requestKeyboardAccess() }
                )
            }

            ProfilePicker(selection: $store.settings.profile)
                .labelsHidden()
                .pickerStyle(.menu)

            VStack(alignment: .leading, spacing: 14) {
                LabeledSlider(
                    title: "Dampening",
                    leadingLabel: "Sharp",
                    trailingLabel: "Muted",
                    value: $store.settings.dampening,
                    accessibilityHint: "Controls how acoustically dampened the keyboard sounds."
                )
                .disabled(store.settings.usesAdvancedDampening)
                .opacity(store.settings.usesAdvancedDampening ? 0.45 : 1)
                .overlay(alignment: .topTrailing) {
                    if store.settings.usesAdvancedDampening {
                        Text("Manual")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledSlider(
                    title: "Volume",
                    leadingLabel: "Quiet",
                    trailingLabel: "Loud",
                    value: $store.settings.volume,
                    accessibilityHint: "Master volume for keyboard sounds."
                )
            }
            .padding(12)
            .glassCard()

            Button {
                controller.playTestSound()
            } label: {
                Label("Test Sound", systemImage: "play.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .accessibilityHint("Plays one keypress using the current settings.")

            Divider()

            footer
        }
        .padding(14)
        .frame(width: 300)
    }

    // MARK: - Pieces

    private var header: some View {
        HStack {
            Text("MechKeys")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            Text(controller.isListening ? "ON" : "OFF")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Toggle("", isOn: enabledBinding)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .accessibilityLabel("Enable MechKeys")
                .accessibilityValue(store.settings.isEnabled ? "On" : "Off")
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { store.settings.isEnabled },
            set: { controller.setEnabled($0) }
        )
    }

    @ViewBuilder
    private func banner(
        _ message: String,
        symbol: String,
        tint: Color,
        action: (() -> Void)?
    ) -> some View {
        let content = HStack(alignment: .top, spacing: 7) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 8)

        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .accessibilityLabel("\(message) Opens Accessibility settings.")
        } else {
            content
        }
    }

    private var footer: some View {
        VStack(spacing: 9) {
            HStack {
                Text("Launch at Login").font(.system(size: 12))
                Spacer()
                Toggle("", isOn: $store.launchAtLogin)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .accessibilityLabel("Launch at login")
            }

            Button {
                controller.requestKeyboardAccess()
            } label: {
                HStack {
                    Text("Keyboard Access")
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                    Spacer()
                    StatusBadge(
                        level: permissions.isTrusted ? .good : .warning,
                        text: permissions.isTrusted ? "Granted" : "Required"
                    )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Keyboard access status")
            .accessibilityValue(permissions.isTrusted ? "Granted" : "Required")

            Divider()

            menuButton("Configure…", shortcut: ",", action: onConfigure)
            menuButton("Quit MechKeys", shortcut: "Q", action: onQuit)
        }
    }

    private func menuButton(
        _ title: String,
        shortcut: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 12))
                Spacer()
                if let shortcut {
                    Text("⌘\(shortcut)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
