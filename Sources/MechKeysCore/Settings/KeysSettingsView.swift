import SwiftUI

/// Per-key-category tuning: which keys make a sound, and how each one sits
/// relative to the profile.
struct KeysSettingsView: View {

    let controller: MechKeysController
    @Bindable var store: SettingsStore

    init(controller: MechKeysController) {
        self.controller = controller
        self._store = Bindable(wrappedValue: controller.settingsStore)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Play modifier sounds", isOn: $store.settings.playModifierSounds)
                    .accessibilityHint(
                        "Whether pressing Shift, Control, Option or Command makes a sound.")
            } header: {
                Text("Modifiers")
            } footer: {
                Text(
                    """
                    Off by default: modifiers fire constantly while you type, and \
                    a sound on every one of them gets tiring quickly.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                ForEach(KeyCategory.allCases) { category in
                    categoryRow(category)
                }
            } header: {
                Text("Key Categories")
            } footer: {
                Text(
                    """
                    Every key belongs to one of these. Trim the level and pitch of \
                    each to taste — pitching a key down makes it feel physically larger.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func categoryRow(_ category: KeyCategory) -> some View {
        let binding = store.binding(for: category)
        let isModifierAndMuted = category == .modifier && !store.settings.playModifierSounds

        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Image(systemName: category.symbolName)
                    .frame(width: 16)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(category.displayName)
                        .font(.system(size: 12, weight: .medium))
                    Text(category.summary)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    controller.playTestSound(category: category)
                } label: {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Preview \(category.displayName)")

                Toggle("", isOn: binding.isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .accessibilityLabel("\(category.displayName) enabled")
            }

            HStack(spacing: 16) {
                LabeledSlider(
                    title: "Level",
                    leadingLabel: "−18 dB",
                    trailingLabel: "+12 dB",
                    value: binding.gainDB,
                    range: KeyCategorySettings.gainRange,
                    accessibilityHint: "Level trim for \(category.displayName).",
                    format: { String(format: "%+.1f dB", $0) }
                )

                LabeledSlider(
                    title: "Pitch",
                    leadingLabel: "Deeper",
                    trailingLabel: "Higher",
                    value: binding.pitchSemitones,
                    range: KeyCategorySettings.pitchRange,
                    accessibilityHint: "Pitch trim for \(category.displayName), in semitones.",
                    format: { String(format: "%+.1f st", $0) }
                )
            }
            .disabled(!binding.wrappedValue.isEnabled || isModifierAndMuted)
            .opacity(binding.wrappedValue.isEnabled && !isModifierAndMuted ? 1 : 0.4)
        }
        .padding(.vertical, 2)
    }
}
