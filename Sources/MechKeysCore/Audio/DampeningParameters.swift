import Foundation

/// The complete acoustic-treatment state of the signal chain.
///
/// Dampening is not a delay and it is not a volume cut. It models what happens
/// when you pack a keyboard with foam, silicone and plate gaskets: the attack
/// softens, the top end rolls away, the case stops ringing, and what is left is
/// a shorter, rounder, low-mid-heavy thud.
public struct DampeningParameters: Equatable, Codable, Sendable {
    /// Corner frequency of the low-pass, in Hz. Falls as dampening rises.
    public var highFrequencyCutoff: Float
    /// High-shelf gain in dB. Negative values remove air and sharpness.
    public var highFrequencyGain: Float
    /// How much of the initial attack spike is softened, 0...1.
    /// Applied to the sample buffer, never as a delay.
    public var transientReduction: Float
    /// How hard the profile's ring is cut and how fast the tail is choked, 0...1.
    public var resonanceReduction: Float
    /// Amount of gentle compression, 0...1. Evens out the remaining peaks.
    public var compressionAmount: Float
    /// Low-mid shelf gain in dB. Rises with dampening to keep the sound full
    /// rather than merely quiet.
    public var lowMidGain: Float

    public init(highFrequencyCutoff: Float,
                highFrequencyGain: Float,
                transientReduction: Float,
                resonanceReduction: Float,
                compressionAmount: Float,
                lowMidGain: Float) {
        self.highFrequencyCutoff = highFrequencyCutoff
        self.highFrequencyGain = highFrequencyGain
        self.transientReduction = transientReduction
        self.resonanceReduction = resonanceReduction
        self.compressionAmount = compressionAmount
        self.lowMidGain = lowMidGain
    }

    /// Clamps every field to the range the audio units will accept.
    public func clamped() -> DampeningParameters {
        DampeningParameters(
            highFrequencyCutoff: highFrequencyCutoff.clamped(to: DampeningCurve.cutoffRange),
            highFrequencyGain: highFrequencyGain.clamped(to: DampeningCurve.shelfGainRange),
            transientReduction: transientReduction.clamped(to: 0...1),
            resonanceReduction: resonanceReduction.clamped(to: 0...1),
            compressionAmount: compressionAmount.clamped(to: 0...1),
            lowMidGain: lowMidGain.clamped(to: DampeningCurve.bodyGainRange)
        )
    }
}

/// The single source of truth for how the dampening slider maps to DSP.
///
/// Two anchor points and an interpolation, rather than five discrete presets,
/// so that any position on the slider is a valid and musical sound.
public enum DampeningCurve {
    public static let cutoffRange: ClosedRange<Float> = 400...20_000
    public static let shelfGainRange: ClosedRange<Float> = -40...12
    public static let bodyGainRange: ClosedRange<Float> = -12...12

    /// 0% — an undampened board on a bare desk. Full top end, long ring.
    public static let sharp = DampeningParameters(
        highFrequencyCutoff: 19_000,
        highFrequencyGain: 1.5,
        transientReduction: 0.0,
        resonanceReduction: 0.0,
        compressionAmount: 0.0,
        lowMidGain: 0.0
    )

    /// 100% — foam, gaskets, tape mod, silicone in every cavity.
    public static let muted = DampeningParameters(
        highFrequencyCutoff: 1_250,
        highFrequencyGain: -23.0,
        transientReduction: 0.88,
        resonanceReduction: 0.92,
        compressionAmount: 0.80,
        lowMidGain: 5.0
    )

    /// Interpolates the full parameter set for a slider position in 0...1.
    ///
    /// The cutoff moves logarithmically because pitch perception is
    /// logarithmic — a linear sweep would do almost nothing for the first half
    /// of the slider and then collapse.
    public static func parameters(for amount: Float) -> DampeningParameters {
        let t = amount.clamped(to: 0...1)

        // Transient softening leads slightly: the very first movement of the
        // slider should already take the edge off the attack.
        let transientT = t.eased(power: 0.82)
        // Body lift lags: it should only become obvious once the top end has
        // actually gone, otherwise low dampening just sounds boomy.
        let bodyT = t.eased(power: 1.45)
        // Ring-out lags too. Choking the tail removes low-frequency case
        // resonance, and early in the slider that happens faster than the
        // filter removes treble — measured: the high-frequency energy ratio
        // rose from 0% to 12% before falling. The brief is "slightly less
        // resonance" there, so it should barely have started.
        let resonanceT = t.eased(power: 1.35)

        return DampeningParameters(
            highFrequencyCutoff: logLerp(sharp.highFrequencyCutoff, muted.highFrequencyCutoff, t),
            highFrequencyGain: lerp(sharp.highFrequencyGain, muted.highFrequencyGain, t.eased(power: 1.15)),
            transientReduction: lerp(sharp.transientReduction, muted.transientReduction, transientT),
            resonanceReduction: lerp(sharp.resonanceReduction, muted.resonanceReduction, resonanceT),
            compressionAmount: lerp(sharp.compressionAmount, muted.compressionAmount, t.eased(power: 1.25)),
            lowMidGain: lerp(sharp.lowMidGain, muted.lowMidGain, bodyT)
        ).clamped()
    }

    /// Makeup gain that keeps perceived loudness roughly constant as the top
    /// end is filtered away, so the slider reads as *dampening* and not as
    /// *volume*. Without this the control is indistinguishable from turning it
    /// down, which is exactly what it must not be.
    public static func makeupGainDB(for amount: Float) -> Float {
        let t = amount.clamped(to: 0...1)
        return lerp(0.0, 7.5, t.eased(power: 0.9))
    }

    private static func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * t
    }

    private static func logLerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        let la = log2(max(a, 1))
        let lb = log2(max(b, 1))
        return pow(2, la + (lb - la) * t)
    }
}

extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }

    /// Monotonic easing. `power` < 1 front-loads, > 1 back-loads.
    func eased(power: Float) -> Float {
        pow(clamped(to: 0...1), power)
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
