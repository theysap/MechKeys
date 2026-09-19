import Foundation

/// How to treat the stream of events macOS sends while a key is held down.
public enum KeyRepeatMode: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Hold a key, hear one sound. Quietest and the default.
    case silent
    /// Repeats sound, but no faster than the minimum interval allows.
    case throttled
    /// Every repeat event makes a sound. Machine-gun mode.
    case everyRepeat

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .silent: return "Silent"
        case .throttled: return "Throttled"
        case .everyRepeat: return "Every repeat"
        }
    }

    public var summary: String {
        switch self {
        case .silent: return "Holding a key plays one sound."
        case .throttled: return "Holding a key repeats, rate-limited."
        case .everyRepeat: return "Every repeat event plays."
        }
    }
}

/// Per-key-category overrides. Lets the spacebar sit deeper, or modifiers go
/// quiet, without touching the profile itself.
public struct KeyCategorySettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    /// Gain trim in dB, applied on top of the profile.
    public var gainDB: Double
    /// Pitch trim in semitones. Negative is deeper.
    public var pitchSemitones: Double

    public static let gainRange: ClosedRange<Double> = -18...12
    public static let pitchRange: ClosedRange<Double> = -7...7

    public init(isEnabled: Bool = true, gainDB: Double = 0, pitchSemitones: Double = 0) {
        self.isEnabled = isEnabled
        self.gainDB = gainDB
        self.pitchSemitones = pitchSemitones
    }

    public func normalized() -> KeyCategorySettings {
        KeyCategorySettings(
            isEnabled: isEnabled,
            gainDB: gainDB.clamped(to: Self.gainRange),
            pitchSemitones: pitchSemitones.clamped(to: Self.pitchRange)
        )
    }
}

/// Everything the user can change, in one Codable value.
///
/// A single struct (rather than a scatter of `@AppStorage` keys) keeps the
/// advanced dampening override and the per-category table in the same
/// snapshot, which is what makes "Revert Changes" possible.
public struct AppSettings: Codable, Equatable, Sendable {

    // MARK: Core

    public var isEnabled: Bool
    public var profile: SoundProfile
    /// Dampening slider position, 0 (sharp) ... 1 (muted).
    public var dampening: Double
    /// Master output level, 0 ... 1.
    public var volume: Double

    // MARK: Advanced dampening

    /// When true the six DSP parameters are taken from `advancedDampening`
    /// instead of from the curve.
    public var usesAdvancedDampening: Bool
    public var advancedDampening: DampeningParameters
    /// Extra output trim in dB applied after the dampening chain.
    public var makeupGainOffsetDB: Double

    // MARK: Keys

    public var playModifierSounds: Bool
    public var categorySettings: [KeyCategory: KeyCategorySettings]

    // MARK: Variation

    /// Scales the whole natural-variation system, 0 (identical every time) ... 1.
    public var variationAmount: Double
    public var pitchVariationEnabled: Bool

    // MARK: Behaviour

    public var keyRepeatMode: KeyRepeatMode
    /// Floor on the gap between two sounds, in seconds. Protects the engine
    /// from an autorepeat storm.
    public var minimumKeyInterval: Double
    /// Size of the player-node pool: how many keypresses can overlap.
    public var maximumVoices: Int

    // MARK: App

    public var hasCompletedOnboarding: Bool
    public var showsMenuBarStateInIcon: Bool

    // MARK: Ranges

    public static let dampeningRange: ClosedRange<Double> = 0...1
    public static let volumeRange: ClosedRange<Double> = 0...1
    public static let variationRange: ClosedRange<Double> = 0...1
    public static let minimumKeyIntervalRange: ClosedRange<Double> = 0.005...0.200
    public static let voiceCountRange: ClosedRange<Int> = 4...32
    public static let makeupOffsetRange: ClosedRange<Double> = -12...12

    /// Sensible out-of-the-box configuration.
    public static let `default` = AppSettings(
        isEnabled: true,
        profile: .brown,
        dampening: 0.35,
        volume: 0.50,
        usesAdvancedDampening: false,
        advancedDampening: DampeningCurve.parameters(for: 0.35),
        makeupGainOffsetDB: 0,
        playModifierSounds: false,
        categorySettings: Self.defaultCategorySettings,
        variationAmount: 0.6,
        pitchVariationEnabled: true,
        keyRepeatMode: .silent,
        minimumKeyInterval: 0.022,
        maximumVoices: 16,
        hasCompletedOnboarding: false,
        showsMenuBarStateInIcon: true
    )

    public static var defaultCategorySettings: [KeyCategory: KeyCategorySettings] {
        Dictionary(uniqueKeysWithValues: KeyCategory.allCases.map { ($0, KeyCategorySettings()) })
    }

    public init(
        isEnabled: Bool,
        profile: SoundProfile,
        dampening: Double,
        volume: Double,
        usesAdvancedDampening: Bool,
        advancedDampening: DampeningParameters,
        makeupGainOffsetDB: Double,
        playModifierSounds: Bool,
        categorySettings: [KeyCategory: KeyCategorySettings],
        variationAmount: Double,
        pitchVariationEnabled: Bool,
        keyRepeatMode: KeyRepeatMode,
        minimumKeyInterval: Double,
        maximumVoices: Int,
        hasCompletedOnboarding: Bool,
        showsMenuBarStateInIcon: Bool
    ) {
        self.isEnabled = isEnabled
        self.profile = profile
        self.dampening = dampening
        self.volume = volume
        self.usesAdvancedDampening = usesAdvancedDampening
        self.advancedDampening = advancedDampening
        self.makeupGainOffsetDB = makeupGainOffsetDB
        self.playModifierSounds = playModifierSounds
        self.categorySettings = categorySettings
        self.variationAmount = variationAmount
        self.pitchVariationEnabled = pitchVariationEnabled
        self.keyRepeatMode = keyRepeatMode
        self.minimumKeyInterval = minimumKeyInterval
        self.maximumVoices = maximumVoices
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.showsMenuBarStateInIcon = showsMenuBarStateInIcon
    }

    /// Decoding tolerates a settings file written by an older build: anything
    /// missing falls back to the default rather than throwing the whole file
    /// away.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppSettings.default
        func value<T: Decodable>(_ key: CodingKeys, _ defaultValue: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)).flatMap { $0 } ?? defaultValue
        }
        isEnabled = value(.isEnabled, fallback.isEnabled)
        profile = value(.profile, fallback.profile)
        dampening = value(.dampening, fallback.dampening)
        volume = value(.volume, fallback.volume)
        usesAdvancedDampening = value(.usesAdvancedDampening, fallback.usesAdvancedDampening)
        advancedDampening = value(.advancedDampening, fallback.advancedDampening)
        makeupGainOffsetDB = value(.makeupGainOffsetDB, fallback.makeupGainOffsetDB)
        playModifierSounds = value(.playModifierSounds, fallback.playModifierSounds)
        categorySettings = value(.categorySettings, fallback.categorySettings)
        variationAmount = value(.variationAmount, fallback.variationAmount)
        pitchVariationEnabled = value(.pitchVariationEnabled, fallback.pitchVariationEnabled)
        keyRepeatMode = value(.keyRepeatMode, fallback.keyRepeatMode)
        minimumKeyInterval = value(.minimumKeyInterval, fallback.minimumKeyInterval)
        maximumVoices = value(.maximumVoices, fallback.maximumVoices)
        hasCompletedOnboarding = value(.hasCompletedOnboarding, fallback.hasCompletedOnboarding)
        showsMenuBarStateInIcon = value(.showsMenuBarStateInIcon, fallback.showsMenuBarStateInIcon)
        self = self.normalized()
    }

    /// Clamps every stored value into its legal range. Called on decode and on
    /// every mutation, so out-of-range values can never reach the audio units.
    public func normalized() -> AppSettings {
        var copy = self
        copy.dampening = dampening.clamped(to: Self.dampeningRange)
        copy.volume = volume.clamped(to: Self.volumeRange)
        copy.variationAmount = variationAmount.clamped(to: Self.variationRange)
        copy.minimumKeyInterval = minimumKeyInterval.clamped(to: Self.minimumKeyIntervalRange)
        copy.maximumVoices = Swift.min(
            Swift.max(maximumVoices, Self.voiceCountRange.lowerBound),
            Self.voiceCountRange.upperBound)
        copy.makeupGainOffsetDB = makeupGainOffsetDB.clamped(to: Self.makeupOffsetRange)
        copy.advancedDampening = advancedDampening.clamped()
        var categories = categorySettings
        for category in KeyCategory.allCases {
            categories[category] = (categories[category] ?? KeyCategorySettings()).normalized()
        }
        copy.categorySettings = categories
        return copy
    }

    public func settings(for category: KeyCategory) -> KeyCategorySettings {
        categorySettings[category] ?? KeyCategorySettings()
    }

    /// The DSP parameters actually in force: either the curve, or the manual
    /// override when the user has taken control.
    public var effectiveDampening: DampeningParameters {
        usesAdvancedDampening
            ? advancedDampening.clamped()
            : DampeningCurve.parameters(for: Float(dampening))
    }

    /// Output trim in dB: loudness compensation for the dampening chain, plus
    /// the user's own offset.
    public var effectiveMakeupGainDB: Float {
        let automatic =
            usesAdvancedDampening ? 0 : DampeningCurve.makeupGainDB(for: Float(dampening))
        return automatic + Float(makeupGainOffsetDB)
    }

    /// Whether a category should make any sound at all right now.
    public func isAudible(_ category: KeyCategory) -> Bool {
        if category == .modifier && !playModifierSounds { return false }
        return settings(for: category).isEnabled
    }
}
