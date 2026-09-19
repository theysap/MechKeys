import SwiftUI

/// How the app reacts to the keyboard: repeats, rate limits, variation and how
/// many sounds may overlap.
struct BehaviorSettingsView: View {

    let controller: MechKeysController
    @Bindable var store: SettingsStore

    init(controller: MechKeysController) {
        self.controller = controller
        self._store = Bindable(wrappedValue: controller.settingsStore)
    }

    var body: some View {
        Form {
            Section {
                Picker("Held keys", selection: $store.settings.keyRepeatMode) {
                    ForEach(KeyRepeatMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Key repeat behaviour")
                .accessibilityValue(store.settings.keyRepeatMode.displayName)

                Text(store.settings.keyRepeatMode.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledSlider(
                    title: "Minimum Interval",
                    leadingLabel: "5 ms",
                    trailingLabel: "200 ms",
                    value: $store.settings.minimumKeyInterval,
                    range: AppSettings.minimumKeyIntervalRange,
                    accessibilityHint:
                        "The shortest gap allowed between two key sounds. Protects the engine from an autorepeat storm.",
                    format: { String(format: "%.0f ms", $0 * 1000) }
                )
            } header: {
                Text("Key Repeat")
            } footer: {
                Text(
                    """
                    What happens while a key is held and macOS starts repeating it. \
                    A higher minimum interval drops sounds during very fast typing; \
                    a lower one lets every keystroke through.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                LabeledSlider(
                    title: "Variation",
                    leadingLabel: "Identical",
                    trailingLabel: "Lively",
                    value: $store.settings.variationAmount,
                    accessibilityHint: "How much the level and pitch of each keypress vary."
                )

                Toggle("Vary pitch as well as level", isOn: $store.settings.pitchVariationEnabled)
                    .accessibilityHint("Pre-renders slightly detuned copies of each sample.")

                Button {
                    controller.playTestSound()
                } label: {
                    Label("Test Sound", systemImage: "play.circle")
                }
                .accessibilityHint("Press repeatedly to hear the variation.")
            } header: {
                Text("Natural Variation")
            } footer: {
                Text(
                    """
                    Real keyboards never sound identical twice. MechKeys picks \
                    between five recordings per key, never the same one twice in a \
                    row, and nudges the level and pitch a fraction each time.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Stepper(
                    value: $store.settings.maximumVoices,
                    in: AppSettings.voiceCountRange,
                    step: 2
                ) {
                    LabeledContent("Overlapping sounds", value: "\(store.settings.maximumVoices)")
                }
                .accessibilityLabel("Maximum overlapping sounds")
                .accessibilityValue("\(store.settings.maximumVoices)")
            } header: {
                Text("Performance")
            } footer: {
                Text(
                    """
                    How many keypresses may overlap. Each voice is one player node \
                    held ready in the audio graph; sixteen is comfortable for fast \
                    typing. Changing this rebuilds the graph, which is briefly silent.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
