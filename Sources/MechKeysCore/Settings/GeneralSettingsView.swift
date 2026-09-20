import AppKit
import SwiftUI

/// Permissions, startup, privacy and maintenance.
struct GeneralSettingsView: View {

    let controller: MechKeysController
    @Bindable var store: SettingsStore
    @Binding var showingResetConfirmation: Bool
    var onCheckForUpdates: () -> Void

    init(
        controller: MechKeysController,
        showingResetConfirmation: Binding<Bool>,
        onCheckForUpdates: @escaping () -> Void = {}
    ) {
        self.controller = controller
        self._store = Bindable(wrappedValue: controller.settingsStore)
        self._showingResetConfirmation = showingResetConfirmation
        self.onCheckForUpdates = onCheckForUpdates
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
                        Button("Check Again") { controller.verifyKeyboardAccess() }
                            .controlSize(.small)
                            .accessibilityHint(
                                "Verifies access by creating a real event tap, which is more reliable than the system's own answer."
                            )
                        if !permissions.isTrusted {
                            Button("Open Settings…") { controller.requestKeyboardAccess() }
                                .controlSize(.small)
                        }
                    }
                }
                .accessibilityLabel("Keyboard access status")
                .accessibilityValue(permissions.isTrusted ? "Granted" : "Required")

                if let verification = permissions.lastVerification {
                    verificationNote(verification)
                }

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

                Toggle(
                    "Show state in the menu bar icon", isOn: $store.settings.showsMenuBarStateInIcon
                )
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
                LabeledContent("Version") {
                    HStack(spacing: 8) {
                        Text(AppInfo.versionDescription)
                            .foregroundStyle(.secondary)
                        Button("Check for Updates…", action: onCheckForUpdates)
                            .controlSize(.small)
                            .accessibilityHint(
                                "Looks for a newer release of MechKeys on GitHub.")
                    }
                }
                .accessibilityLabel("Version")
                .accessibilityValue(AppInfo.versionDescription)

                Toggle(
                    "Check for updates automatically",
                    isOn: $store.settings.checksForUpdatesAutomatically
                )
                .accessibilityHint(
                    "Looks for a newer release a few seconds after launch and every six hours. Nothing is downloaded until you ask for it."
                )

                LabeledContent("Sounds", value: "Recorded switches, bundled")

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

    /// What the deep check found, and the way out if macOS is being stubborn.
    @ViewBuilder
    private func verificationNote(_ result: PermissionManager.VerifyResult) -> some View {
        switch result {
        case .granted:
            Label(
                "Verified — MechKeys can listen to the keyboard.", systemImage: "checkmark.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

        case .grantedAfterDisagreement:
            Label(
                "Verified. macOS was reporting no permission, but a real event tap succeeded, so MechKeys is working.",
                systemImage: "checkmark.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

        case .denied:
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    "MechKeys still cannot create an event tap.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(
                    """
                    If MechKeys is already switched on in System Settings, macOS \
                    has cached its answer for this process. Remove MechKeys from \
                    the Accessibility list, add it again, then relaunch.
                    """
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

                Button("Relaunch MechKeys") { controller.relaunch() }
                    .controlSize(.small)
                    .accessibilityHint("Quits and reopens MechKeys so macOS re-evaluates access.")
            }
        }
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
        "The one request MechKeys makes is to GitHub's public releases list, when it checks for an update. It sends nothing — no identifiers, no analytics, no telemetry.",
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
