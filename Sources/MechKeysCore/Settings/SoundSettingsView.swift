import SwiftUI

/// The main tab: which switch, how dampened, how loud.
struct SoundSettingsView: View {

    let controller: MechKeysController
    @Bindable var store: SettingsStore

    init(controller: MechKeysController) {
        self.controller = controller
        self._store = Bindable(wrappedValue: controller.settingsStore)
    }

    var body: some View {
        Form {
            Section {
                ForEach(SoundProfile.allCases) { profile in
                    profileRow(profile)
                }
            } header: {
                Text("Switch")
            } footer: {
                Text(
                    """
                    Acoustic profiles inspired by the character of common switch \
                    types. Original synthesised sounds, not affiliated with or \
                    endorsed by any manufacturer.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                LabeledSlider(
                    title: "Dampening",
                    leadingLabel: "Sharp",
                    trailingLabel: "Muted",
                    value: $store.settings.dampening,
                    accessibilityHint:
                        "Zero per cent is a bare, ringing board. One hundred per cent is heavily dampened and thuddy."
                )
                .disabled(store.settings.usesAdvancedDampening)
                .opacity(store.settings.usesAdvancedDampening ? 0.45 : 1)

                Text(Self.dampeningDescription(for: store.settings.dampening))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    controller.playTestSound()
                } label: {
                    Label("Test Sound", systemImage: "play.circle")
                }
                .accessibilityHint("Plays one keypress so you can hear the current dampening.")

                AdvancedDampeningView(controller: controller)
            } header: {
                Text("Dampening")
            } footer: {
                Text(
                    """
                    Foam, gaskets and silicone, as a slider. It softens the attack, \
                    rolls off the top end and stops the case ringing — it never \
                    delays the sound, and it is not a volume control.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Volume") {
                LabeledSlider(
                    title: "Volume",
                    leadingLabel: "Quiet",
                    trailingLabel: "Loud",
                    value: $store.settings.volume,
                    accessibilityHint: "Master output level for keyboard sounds."
                )
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Profile row

    @ViewBuilder
    private func profileRow(_ profile: SoundProfile) -> some View {
        let isSelected = store.settings.profile == profile

        Button {
            store.settings.profile = profile
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(profile.swatch)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(profile.displayName)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        Text(profile.character)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    Text(profile.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                // Audition and switch in one tap: you cannot judge a profile
                // you have not heard.
                Button {
                    store.settings.profile = profile
                    controller.playTestSound()
                } label: {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Preview \(profile.displayName)")

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(profile.displayName). \(profile.summary)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    /// Plain-language read-out of what the current slider position does.
    static func dampeningDescription(for amount: Double) -> String {
        switch amount {
        case ..<0.12:
            return "Undampened. Full high-frequency energy, sharp transient, a long ring."
        case ..<0.37:
            return "Lightly dampened. The transient is softened and the top end pulled back a little."
        case ..<0.62:
            return "Noticeably smoother. Reduced sharpness and resonance, a fuller and rounder sound."
        case ..<0.87:
            return "Strongly softened. Highs substantially reduced, very little ring left."
        default:
            return "Heavily dampened. Soft attack, filtered highs, minimal ringing — muffled and thuddy."
        }
    }
}
