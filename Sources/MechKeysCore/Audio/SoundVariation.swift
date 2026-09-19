import Foundation

/// Fast, allocation-free PRNG.
///
/// `SystemRandomNumberGenerator` would be fine, but this runs once per
/// keypress on a real-time-ish queue and SplitMix64 is a handful of integer
/// operations with no syscall behind it.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64 = UInt64(DispatchTime.now().uptimeNanoseconds)) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Picks which sample plays and how loud, so repeated keys never sound
/// mechanically identical.
///
/// The goal is *natural variation*, not randomness you can hear. Two rules do
/// most of the work: never play the same variant twice in a row, and keep the
/// level jitter inside a couple of dB.
public struct SoundVariation {

    /// Widest amplitude jitter, in dB, at variation = 1.
    public static let maximumGainJitterDB: Float = 2.0
    /// Widest pitch jitter, in cents, at variation = 1.
    public static let maximumPitchJitterCents: Float = 18.0
    /// Number of micro-pitch renditions cached per sample.
    public static let pitchStepCount = 3

    private var rng = SplitMix64()
    private var lastIndices: [KeyCategory: Int] = [:]

    public init() {}

    /// Chooses a variant index, avoiding an immediate repeat.
    ///
    /// At `amount` zero the slider reads "Identical", so it has to mean it:
    /// the same sample every time, not merely the same level and pitch.
    public mutating func nextIndex(count: Int, category: KeyCategory, amount: Double = 1) -> Int {
        guard count > 1, amount > 0.0001 else { return 0 }
        var index = Int(rng.next() % UInt64(count))
        if index == lastIndices[category], count > 1 {
            // One re-roll only. Forcing a different sample every time would
            // itself be a detectable pattern.
            index = Int(rng.next() % UInt64(count))
        }
        lastIndices[category] = index
        return index
    }

    /// Linear amplitude multiplier around 1.0.
    public mutating func nextAmplitudeScalar(amount: Double) -> Float {
        guard amount > 0.0001 else { return 1 }
        let jitterDB = Self.maximumGainJitterDB * Float(amount)
        let unit = Float(rng.next() % 10_000) / 10_000.0   // 0..<1
        let offsetDB = (unit * 2 - 1) * jitterDB
        return powf(10, offsetDB / 20)
    }

    /// Pitch offsets, in cents, that the cache should pre-render.
    public static func pitchOffsetsCents(amount: Double, enabled: Bool) -> [Float] {
        guard enabled, amount > 0.0001 else { return [0] }
        let spread = maximumPitchJitterCents * Float(amount)
        return [-spread, 0, spread]
    }
}
