import SwiftUI

/// The six DSP parameters behind the dampening slider, exposed for anyone who
/// wants to dial in their own treatment.
///
/// Collapsed by default. Switching on manual control detaches the slider and
/// hands over the raw values — seeded from wherever the slider currently sits,
/// so taking manual control never changes the sound at the moment you do it.
struct AdvancedDampeningView: View {

    let controller: MechKeysController
    @Bindable var store: SettingsStore

    @StateObject private var expanded = ViewState(false)

    init(controller: MechKeysController) {
        self.controller = controller
        self._store = Bindable(wrappedValue: controller.settingsStore)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded.value) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Set these manually", isOn: manualBinding)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 11))
                    .accessibilityHint(
                        "Detaches the dampening slider and uses the values below directly.")

                Group {
                    LabeledSlider(
                        title: "High-Frequency Cutoff",
                        leadingLabel: "Dark",
                        trailingLabel: "Open",
                        value: store.advancedBinding(\.highFrequencyCutoff),
                        range: Double(
                            DampeningCurve.cutoffRange.lowerBound)...Double(
                                DampeningCurve.cutoffRange.upperBound),
                        accessibilityHint: "Low-pass corner frequency.",
                        format: {
                            $0 >= 1000
                                ? String(format: "%.1f kHz", $0 / 1000)
                                : String(format: "%.0f Hz", $0)
                        }
                    )

                    LabeledSlider(
                        title: "High-Frequency Gain",
                        leadingLabel: "Cut",
                        trailingLabel: "Boost",
                        value: store.advancedBinding(\.highFrequencyGain),
                        range: Double(
                            DampeningCurve.shelfGainRange.lowerBound)...Double(
                                DampeningCurve.shelfGainRange.upperBound),
                        accessibilityHint: "High shelf gain above 3.2 kilohertz.",
                        format: { String(format: "%.1f dB", $0) }
                    )

                    LabeledSlider(
                        title: "Transient Softening",
                        leadingLabel: "Sharp",
                        trailingLabel: "Soft",
                        value: store.advancedBinding(\.transientReduction),
                        accessibilityHint:
                            "How much of the initial attack spike is smoothed. Does not delay the sound."
                    )

                    LabeledSlider(
                        title: "Resonance Reduction",
                        leadingLabel: "Ringy",
                        trailingLabel: "Dead",
                        value: store.advancedBinding(\.resonanceReduction),
                        accessibilityHint: "Cuts the profile's ring and shortens the tail."
                    )

                    LabeledSlider(
                        title: "Compression",
                        leadingLabel: "None",
                        trailingLabel: "Firm",
                        value: store.advancedBinding(\.compressionAmount),
                        accessibilityHint: "Evens out the remaining peaks."
                    )

                    LabeledSlider(
                        title: "Low-Mid Body",
                        leadingLabel: "Thin",
                        trailingLabel: "Full",
                        value: store.advancedBinding(\.lowMidGain),
                        range: Double(
                            DampeningCurve.bodyGainRange.lowerBound)...Double(
                                DampeningCurve.bodyGainRange.upperBound),
                        accessibilityHint: "Low shelf gain around the profile's body frequency.",
                        format: { String(format: "%.1f dB", $0) }
                    )
                }
                .disabled(!store.settings.usesAdvancedDampening)
                .opacity(store.settings.usesAdvancedDampening ? 1 : 0.45)

                Divider()

                LabeledSlider(
                    title: "Output Trim",
                    leadingLabel: "−12 dB",
                    trailingLabel: "+12 dB",
                    value: $store.settings.makeupGainOffsetDB,
                    range: AppSettings.makeupOffsetRange,
                    accessibilityHint:
                        "Extra gain after the dampening chain, on top of automatic loudness compensation.",
                    format: { String(format: "%+.1f dB", $0) }
                )

                HStack {
                    Button("Match Slider") {
                        store.settings.advancedDampening =
                            DampeningCurve.parameters(for: Float(store.settings.dampening))
                    }
                    .controlSize(.small)
                    .disabled(!store.settings.usesAdvancedDampening)
                    .accessibilityHint(
                        "Copies the values the dampening slider would produce at its current position."
                    )

                    Spacer()

                    Button {
                        controller.playTestSound()
                    } label: {
                        Label("Test", systemImage: "play.circle")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            }
            .padding(.top, 10)
        } label: {
            HStack(spacing: 6) {
                Text("Advanced")
                    .font(.system(size: 12, weight: .medium))
                if store.settings.usesAdvancedDampening {
                    Text("manual")
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                }
            }
        }
        .accessibilityLabel("Advanced dampening parameters")
    }

    /// Seeds the manual values from the curve on the way in, so switching to
    /// manual control is audibly a no-op.
    private var manualBinding: Binding<Bool> {
        Binding(
            get: { store.settings.usesAdvancedDampening },
            set: { enabled in
                if enabled {
                    store.settings.advancedDampening =
                        DampeningCurve.parameters(for: Float(store.settings.dampening))
                }
                store.settings.usesAdvancedDampening = enabled
            }
        )
    }
}
