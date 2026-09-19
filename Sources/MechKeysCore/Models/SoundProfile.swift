import Foundation

/// The built-in acoustic profiles.
///
/// Each is a set of recordings of the switch it is named after — Gateron Ink
/// Red, Drop Holy Panda, Kailh Box Navy, Gateron Ink Black and NovelKeys
/// Cream. The switch name identifies the recording; MechKeys is not affiliated
/// with, endorsed by, or sponsored by any switch manufacturer. See
/// `assets/LICENSES.md` for provenance.
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
        case .brown: return "Deep tactile. Dark and rounded, with a full bottom-out."
        case .blue: return "Tactile and clicky. The loudest, sharpest profile."
        case .black: return "Heavy linear. Substantial bottom-out with a firm clack."
        case .yellow: return "Smooth, creamy linear. Even and unfussy."
        }
    }

    /// One-word impression, shown next to the profile name.
    public var character: String {
        switch self {
        case .red: return "tap / clack"
        case .brown: return "thock"
        case .blue: return "CLICK"
        case .black: return "clack"
        case .yellow: return "creamy"
        }
    }

    /// Folder name inside `Resources/Sounds`.
    public var directoryName: String { rawValue }

    /// The fixed acoustic fingerprint of this profile.
    ///
    /// Measured from the bundled recordings, not guessed: `resonanceHz` is the
    /// dominant peak between 1.5 and 9 kHz, `bodyHz` the energy centroid below
    /// 600 Hz, `brightness` the overall spectral centroid normalised across
    /// the five, and `transientSensitivity` how quickly the sample reaches its
    /// peak. The dampening chain reads these to know *where* to cut: a Box
    /// Navy rings at 2.3 kHz with a far peakier resonance than an Ink Black,
    /// and one fixed filter would dampen one and hollow out the other.
    public var voicing: ProfileVoicing {
        switch self {
        case .red:
            return ProfileVoicing(
                resonanceHz: 3012, resonanceQ: 1.30, bodyHz: 229,
                brightness: 0.62, transientSensitivity: 0.99)
        case .brown:
            return ProfileVoicing(
                resonanceHz: 2312, resonanceQ: 1.60, bodyHz: 341,
                brightness: 0.28, transientSensitivity: 0.70)
        case .blue:
            return ProfileVoicing(
                resonanceHz: 2285, resonanceQ: 2.00, bodyHz: 257,
                brightness: 0.96, transientSensitivity: 0.78)
        case .black:
            return ProfileVoicing(
                resonanceHz: 2152, resonanceQ: 1.20, bodyHz: 283,
                brightness: 0.59, transientSensitivity: 1.00)
        case .yellow:
            return ProfileVoicing(
                resonanceHz: 3331, resonanceQ: 1.30, bodyHz: 216,
                brightness: 0.51, transientSensitivity: 0.99)
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

    public init(
        resonanceHz: Float, resonanceQ: Float, bodyHz: Float,
        brightness: Float, transientSensitivity: Float
    ) {
        self.resonanceHz = resonanceHz
        self.resonanceQ = resonanceQ
        self.bodyHz = bodyHz
        self.brightness = brightness
        self.transientSensitivity = transientSensitivity
    }
}
