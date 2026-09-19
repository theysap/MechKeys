import Foundation

/// The built-in acoustic profiles.
///
/// These are *inspired by* the acoustic character of common switch types. They
/// are original synthesised sounds and are not affiliated with, endorsed by, or
/// sponsored by any switch manufacturer.
public enum SoundProfile: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case red
    case brown
    case blue
    case black
    case yellow

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .red: return "Red"
        case .brown: return "Brown"
        case .blue: return "Blue"
        case .black: return "Black"
        case .yellow: return "Yellow"
        }
    }

    public var summary: String {
        switch self {
        case .red: return "Linear and smooth. Quiet, rounded bottom-out."
        case .brown: return "Tactile with a little texture. Moderate attack."
        case .blue: return "Tactile and clicky. The loudest, sharpest profile."
        case .black: return "Heavy linear. Deep body, substantial bottom-out."
        case .yellow: return "Smooth linear, between Red and Black in weight."
        }
    }

    /// One-word impression, shown next to the profile name.
    public var character: String {
        switch self {
        case .red: return "tap / clack"
        case .brown: return "tick / clack"
        case .blue: return "CLICK"
        case .black: return "thock"
        case .yellow: return "clack"
        }
    }

    /// Folder name inside `Resources/Sounds`.
    public var directoryName: String { rawValue }

    /// The fixed acoustic fingerprint of this profile.
    ///
    /// The dampening chain reads these to know *where* to cut: a Blue rings at
    /// 5.4 kHz and a Black at 2.0 kHz, so applying the same filter to both
    /// would dampen one and gut the other.
    public var voicing: ProfileVoicing {
        switch self {
        case .red:
            return ProfileVoicing(resonanceHz: 3400, resonanceQ: 1.1, bodyHz: 205,
                                  brightness: 0.48, transientSensitivity: 0.85)
        case .brown:
            return ProfileVoicing(resonanceHz: 4100, resonanceQ: 1.3, bodyHz: 198,
                                  brightness: 0.60, transientSensitivity: 0.95)
        case .blue:
            return ProfileVoicing(resonanceHz: 5400, resonanceQ: 1.8, bodyHz: 232,
                                  brightness: 0.92, transientSensitivity: 1.00)
        case .black:
            return ProfileVoicing(resonanceHz: 2100, resonanceQ: 0.9, bodyHz: 148,
                                  brightness: 0.32, transientSensitivity: 0.70)
        case .yellow:
            return ProfileVoicing(resonanceHz: 2700, resonanceQ: 1.0, bodyHz: 172,
                                  brightness: 0.41, transientSensitivity: 0.80)
        }
    }
}

/// Per-profile acoustic constants. Defined once, in `SoundProfile.voicing`.
public struct ProfileVoicing: Equatable, Hashable, Sendable {
    /// Centre of the profile's ring — the band the resonance cut targets.
    public let resonanceHz: Float
    /// Sharpness of that ring.
    public let resonanceQ: Float
    /// Centre of the low-mid body band that dampening gently lifts.
    public let bodyHz: Float
    /// Intrinsic high-frequency content, 0...1.
    public let brightness: Float
    /// How strongly transient shaping bites on this profile, 0...1.
    public let transientSensitivity: Float

    public init(resonanceHz: Float, resonanceQ: Float, bodyHz: Float,
                brightness: Float, transientSensitivity: Float) {
        self.resonanceHz = resonanceHz
        self.resonanceQ = resonanceQ
        self.bodyHz = bodyHz
        self.brightness = brightness
        self.transientSensitivity = transientSensitivity
    }
}
