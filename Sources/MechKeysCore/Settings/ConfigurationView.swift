import SwiftUI

/// The configuration window.
///
/// The popover covers the three things you change often. This covers
/// everything else, in four tabs, with a footer that can undo the whole
/// session's edits. Changes apply live — "Save & Close" confirms and dismisses,
/// it is not what makes the settings take effect.
public struct ConfigurationView: View {

    let controller: MechKeysController
    @Bindable var store: SettingsStore

    public var onClose: () -> Void

    @StateObject private var selectedTab = ViewState(Tab.sound)
    @StateObject private var showingReset = ViewState(false)

    enum Tab: String, CaseIterable, Identifiable {
        case sound, keys, behavior, general

        var id: String { rawValue }

        var title: String {
            switch self {
            case .sound: return "Sound"
            case .keys: return "Keys"
            case .behavior: return "Behaviour"
            case .general: return "General"
            }
        }

        var symbol: String {
            switch self {
            case .sound: return "waveform"
            case .keys: return "keyboard"
            case .behavior: return "dial.medium"
            case .general: return "gearshape"
            }
        }
    }

    public init(controller: MechKeysController, onClose: @escaping () -> Void = {}) {
        self.controller = controller
        self._store = Bindable(wrappedValue: controller.settingsStore)
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab.value) {
                SoundSettingsView(controller: controller)
                    .tabItem { Label(Tab.sound.title, systemImage: Tab.sound.symbol) }
                    .tag(Tab.sound)

                KeysSettingsView(controller: controller)
                    .tabItem { Label(Tab.keys.title, systemImage: Tab.keys.symbol) }
                    .tag(Tab.keys)

                BehaviorSettingsView(controller: controller)
                    .tabItem { Label(Tab.behavior.title, systemImage: Tab.behavior.symbol) }
                    .tag(Tab.behavior)

                GeneralSettingsView(
                    controller: controller,
                    showingResetConfirmation: $showingReset.value
                )
                .tabItem { Label(Tab.general.title, systemImage: Tab.general.symbol) }
                .tag(Tab.general)
            }
            .padding(.top, 10)

            Divider()
            footer
        }
        .frame(width: 500, height: 600)
        .onAppear { store.beginEditing() }
        .confirmationDialog(
            "Reset all sound settings to their defaults?",
            isPresented: $showingReset.value
        ) {
            Button("Reset Settings", role: .destructive) { store.resetToDefaults() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Onboarding and the login item are left alone.")
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Revert Changes") { store.revert() }
                .disabled(!store.canRevert)
                .accessibilityHint("Restores every setting to how it was when this window opened.")

            Spacer()

            Text(controller.statusSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Button("Save & Close") {
                store.commit()
                onClose()
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
            .accessibilityHint(
                "Saves the settings and closes this window. MechKeys keeps running in the menu bar.")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

// MARK: - Binding helpers

extension SettingsStore {
    /// Binding into one key category's overrides.
    func binding(for category: KeyCategory) -> Binding<KeyCategorySettings> {
        Binding(
            get: { self.settings.settings(for: category) },
            set: { self.settings.categorySettings[category] = $0 }
        )
    }

    /// `Slider` wants a `Double`; the DSP model stores `Float`.
    func advancedBinding(_ keyPath: WritableKeyPath<DampeningParameters, Float>) -> Binding<Double> {
        Binding(
            get: { Double(self.settings.advancedDampening[keyPath: keyPath]) },
            set: { self.settings.advancedDampening[keyPath: keyPath] = Float($0) }
        )
    }
}
