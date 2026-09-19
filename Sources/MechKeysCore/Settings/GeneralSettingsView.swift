import AppKit
import SwiftUI

/// Permissions, startup, privacy and maintenance.
struct GeneralSettingsView: View {

    let controller: MechKeysController
    @Bindable var store: SettingsStore
    @Binding var showingResetConfirmation: Bool

    init(controller: MechKeysController, showingResetConfirmation: Binding<Bool>) {
        self.controller = controller
        self._store = Bindable(wrappedValue: controller.settingsStore)
        self._showingResetConfirmation = showingResetConfirmation
    }

    private var permissions: PermissionManager { controller.permissions }

    var body: some View {
        Form {
            Section("Status") {
                Toggle("Enable MechKeys", isOn: enabledBinding)
                    .accessibilityHint("Turns key sounds on and off system-wide.")

                LabeledContent("Keyboard Access") {
                    HStack(spacing: 8) {
                        StatusBadge(
                            level: permissions.isTrusted ? .good : .warning,
                            text: permissions.isTrusted ? "Granted" : "Required"
                        )
                        if !permissions.isTrusted {
                            Button("Open Settings…") { controller.requestKeyboardAccess() }
                                .controlSize(.small)
                        }
                    }
                }
                .accessibilityLabel("Keyboard access status")
                .accessibilityValue(permissions.isTrusted ? "Granted" : "Required")

                LabeledContent("Audio Output") {
                    if case .failed = controller.engineStatus {
                        StatusBadge(level: .bad, text: "Unavailable")
                    } else {
                        StatusBadge(level: .good, text: "Ready")
                    }
                }

                if case .failed(let message) = controller.engineStatus {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                Toggle("Launch at login", isOn: $store.launchAtLogin)
                    .accessibilityHint("Starts MechKeys automatically when you log in.")

                Toggle("Show state in the menu bar icon", isOn: $store.settings.showsMenuBarStateInIcon)
                    .accessibilityHint("Fills the menu bar icon while MechKeys is listening.")
            } header: {
                Text("Startup")
            } footer: {
                Text(store.launchAtLoginStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(Self.privacyPoints, id: \.self) { point in
                    Label {
                        Text(point)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "checkmark.shield")
                            .foregroundStyle(.green)
                    }
                }
            } header: {
                Text("Privacy")
            }

            Section {
                LabeledContent("Version", value: AppInfo.versionDescription)
                LabeledContent("Sounds", value: "Synthesised originals, bundled")

                HStack(spacing: 10) {
                    Button("Reset Settings…") { showingResetConfirmation = true }
                        .accessibilityHint(
                            "Restores the default profile, dampening, volume and key settings.")

                    Button("Quit MechKeys") { NSApp.terminate(nil) }
                        .accessibilityHint(
                            "Quits the app entirely. Key sounds stop until you launch it again.")
                }
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { store.settings.isEnabled },
            set: { controller.setEnabled($0) }
        )
    }

    /// What the app does and does not do with the keyboard. Stated plainly,
    /// because "needs Accessibility permission" reasonably makes people uneasy.
    static let privacyPoints = [
        "Key presses are classified into six categories and immediately discarded.",
        "No characters, key sequences or clipboard contents are read or stored.",
        "The event tap is listen-only and cannot alter or block your typing.",
        "Everything runs locally. No network access, no analytics, no telemetry.",
        "The event tap is torn down entirely whenever MechKeys is switched off.",
    ]
}

enum AppInfo {
    /// The released version, and only that.
    ///
    /// The bundle also carries a build number derived from the commit count,
    /// because macOS wants one that always increases. It is not shown: a build
    /// is not something anyone can download.
    static var versionDescription: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}
