import Foundation
import Testing

@testable import MechKeysCore

@Suite("Settings")
struct SettingsTests {

    /// A private defaults domain per test, so tests cannot see each other's
    /// writes or the developer's real preferences.
    private func makeDefaults(_ function: String = #function) -> UserDefaults {
        let name = "com.mechkeys.tests.\(function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Defaults are the documented ones")
    func defaults() {
        let settings = AppSettings.default
        #expect(settings.profile == .brown)
        #expect(settings.dampening == 0.35)
        #expect(settings.volume == 0.50)
        #expect(settings.playModifierSounds == true)
        #expect(settings.hasCompletedOnboarding == false)
        #expect(settings.keyRepeatMode == .silent)
        #expect(settings.usesAdvancedDampening == false)
        // Every category is present, so a lookup never has to invent one.
        #expect(settings.categorySettings.count == KeyCategory.allCases.count)
    }

    @Test("Values outside their range are clamped")
    func clamping() {
        var settings = AppSettings.default
        settings.dampening = 4.2
        settings.volume = -1
        settings.variationAmount = 88
        settings.minimumKeyInterval = 10
        settings.maximumVoices = 9_000
        settings.makeupGainOffsetDB = -400

        let normalized = settings.normalized()
        #expect(normalized.dampening == 1)
        #expect(normalized.volume == 0)
        #expect(normalized.variationAmount == 1)
        #expect(normalized.minimumKeyInterval == AppSettings.minimumKeyIntervalRange.upperBound)
        #expect(normalized.maximumVoices == AppSettings.voiceCountRange.upperBound)
        #expect(normalized.makeupGainOffsetDB == AppSettings.makeupOffsetRange.lowerBound)
    }

    @Test("Per-category trims are clamped too")
    func categoryClamping() {
        var settings = AppSettings.default
        settings.categorySettings[.space] = KeyCategorySettings(
            isEnabled: true, gainDB: 99, pitchSemitones: -99)

        let space = settings.normalized().settings(for: .space)
        #expect(space.gainDB == KeyCategorySettings.gainRange.upperBound)
        #expect(space.pitchSemitones == KeyCategorySettings.pitchRange.lowerBound)
    }

    @Test("A round trip through JSON preserves every field")
    func codableRoundTrip() throws {
        var settings = AppSettings.default
        settings.profile = .blue
        settings.dampening = 0.72
        settings.usesAdvancedDampening = true
        settings.categorySettings[.enter] = KeyCategorySettings(
            isEnabled: false, gainDB: -3, pitchSemitones: 1.5)

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded == settings)
    }

    @Test("Settings written by an older build still load")
    func tolerantDecoding() throws {
        // Only two fields, and one of them unknown. A strict decoder would
        // throw the whole file away and silently reset the user's setup.
        let json = #"{"profile":"black","somethingRemoved":true}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        #expect(decoded.profile == .black)
        #expect(decoded.volume == AppSettings.default.volume)
        #expect(decoded.keyRepeatMode == AppSettings.default.keyRepeatMode)
    }

    @Test("A value stored out of range is clamped on the way back in")
    func decodingClamps() throws {
        let json = #"{"dampening":9.5,"volume":-2}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(decoded.dampening == 1)
        #expect(decoded.volume == 0)
    }

    @Test("Category dictionaries encode as a JSON object, not a flat array")
    func categoryEncoding() throws {
        // Without CodingKeyRepresentable, a dictionary keyed by an enum
        // encodes as [key, value, key, value…], which is unreadable and
        // brittle.
        let data = try JSONEncoder().encode(AppSettings.default)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["categorySettings"] is [String: Any])
    }

    @MainActor
    @Test("Changes persist and are read back by the next store")
    func persistence() {
        let defaults = makeDefaults()

        let store = SettingsStore(defaults: defaults)
        store.settings.profile = .yellow
        store.settings.dampening = 0.8
        store.settings.playModifierSounds = true

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.settings.profile == .yellow)
        #expect(reloaded.settings.dampening == 0.8)
        #expect(reloaded.settings.playModifierSounds == true)
    }

    @MainActor
    @Test("Unreadable stored settings fall back to defaults instead of throwing")
    func corruptedStorage() {
        let defaults = makeDefaults()
        defaults.set(Data("this is not json".utf8), forKey: SettingsStore.defaultsKey)

        let store = SettingsStore(defaults: defaults)
        #expect(store.settings == AppSettings.default)
    }

    @MainActor
    @Test("Assigning an out-of-range value through the store clamps it")
    func storeClampsOnAssignment() {
        let store = SettingsStore(defaults: makeDefaults())
        store.settings.volume = 5
        #expect(store.settings.volume == 1)
    }

    @MainActor
    @Test("Revert restores the snapshot taken when editing began")
    func revert() {
        let store = SettingsStore(defaults: makeDefaults())
        store.settings.profile = .red

        store.beginEditing()
        #expect(store.canRevert == false)

        store.settings.profile = .blue
        store.settings.dampening = 0.9
        #expect(store.canRevert == true)

        store.revert()
        #expect(store.settings.profile == .red)
        #expect(store.settings.dampening == AppSettings.default.dampening)
    }

    @MainActor
    @Test("Resetting keeps the things the user would hate to redo")
    func resetPreservesOnboarding() {
        let store = SettingsStore(defaults: makeDefaults())
        store.settings.hasCompletedOnboarding = true
        store.settings.profile = .black

        store.resetToDefaults()
        #expect(store.settings.profile == AppSettings.default.profile)
        #expect(store.settings.hasCompletedOnboarding == true)
    }

    @Test("Modifier sounds are gated by their own preference")
    func modifierAudibility() {
        var settings = AppSettings.default
        settings.playModifierSounds = false
        #expect(settings.isAudible(.modifier) == false)
        #expect(settings.isAudible(.standard) == true)

        settings.playModifierSounds = true
        #expect(settings.isAudible(.modifier) == true)

        // A disabled category stays silent whatever the modifier setting says.
        settings.categorySettings[.modifier] = KeyCategorySettings(isEnabled: false)
        #expect(settings.isAudible(.modifier) == false)
    }

    @Test("Manual dampening overrides the curve")
    func effectiveDampening() {
        var settings = AppSettings.default
        settings.dampening = 0.2
        #expect(settings.effectiveDampening == DampeningCurve.parameters(for: 0.2))

        settings.usesAdvancedDampening = true
        settings.advancedDampening = DampeningCurve.parameters(for: 0.9)
        #expect(settings.effectiveDampening == DampeningCurve.parameters(for: 0.9))

        // Automatic loudness makeup belongs to the curve, so manual mode drops
        // it and leaves only the user's own trim.
        settings.makeupGainOffsetDB = 3
        #expect(settings.effectiveMakeupGainDB == 3)
    }
}
