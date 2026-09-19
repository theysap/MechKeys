import Testing

@testable import MechKeysCore

@Suite("Dampening curve")
struct DampeningTests {

    /// The positions called out in the design: 0, 25, 50, 75, 100 per cent.
    private static let positions: [Float] = [0, 0.25, 0.5, 0.75, 1.0]

    @Test("Every parameter moves monotonically across the slider")
    func monotonic() {
        let steps = Self.positions.map { DampeningCurve.parameters(for: $0) }

        for (lower, higher) in zip(steps, steps.dropFirst()) {
            // More dampening means a lower low-pass corner and less treble.
            #expect(higher.highFrequencyCutoff < lower.highFrequencyCutoff)
            #expect(higher.highFrequencyGain < lower.highFrequencyGain)

            // ...and more of everything that softens and shortens the sound.
            #expect(higher.transientReduction > lower.transientReduction)
            #expect(higher.resonanceReduction > lower.resonanceReduction)
            #expect(higher.compressionAmount > lower.compressionAmount)
            #expect(higher.lowMidGain > lower.lowMidGain)
        }
    }

    @Test("The ends of the slider are the stated anchor points")
    func endpoints() {
        let sharp = DampeningCurve.parameters(for: 0)
        #expect(sharp.transientReduction == 0)
        #expect(sharp.resonanceReduction == 0)
        #expect(sharp.compressionAmount == 0)
        #expect(sharp.lowMidGain == 0)

        let muted = DampeningCurve.parameters(for: 1)
        #expect(muted.transientReduction > 0.8)
        #expect(muted.resonanceReduction > 0.85)
        #expect(muted.highFrequencyCutoff < 2000)
    }

    @Test("Input outside 0...1 is clamped rather than extrapolated")
    func clampsInput() {
        #expect(DampeningCurve.parameters(for: -5) == DampeningCurve.parameters(for: 0))
        #expect(DampeningCurve.parameters(for: 42) == DampeningCurve.parameters(for: 1))
    }

    @Test("Every parameter stays inside the range its audio unit accepts")
    func parametersStayInRange() {
        // Walked finely, because an interpolation that overshoots in the
        // middle would pass a check of only the endpoints.
        for step in 0...100 {
            let parameters = DampeningCurve.parameters(for: Float(step) / 100)
            #expect(DampeningCurve.cutoffRange.contains(parameters.highFrequencyCutoff))
            #expect(DampeningCurve.shelfGainRange.contains(parameters.highFrequencyGain))
            #expect(DampeningCurve.bodyGainRange.contains(parameters.lowMidGain))
            #expect((0...1).contains(parameters.transientReduction))
            #expect((0...1).contains(parameters.resonanceReduction))
            #expect((0...1).contains(parameters.compressionAmount))
        }
    }

    @Test("Out-of-range parameters are clamped, not passed through")
    func clampsParameters() {
        let absurd = DampeningParameters(
            highFrequencyCutoff: 99_000,
            highFrequencyGain: 500,
            transientReduction: 9,
            resonanceReduction: -3,
            compressionAmount: 7,
            lowMidGain: -99
        ).clamped()

        #expect(absurd.highFrequencyCutoff == DampeningCurve.cutoffRange.upperBound)
        #expect(absurd.highFrequencyGain == DampeningCurve.shelfGainRange.upperBound)
        #expect(absurd.transientReduction == 1)
        #expect(absurd.resonanceReduction == 0)
        #expect(absurd.compressionAmount == 1)
        #expect(absurd.lowMidGain == DampeningCurve.bodyGainRange.lowerBound)
    }

    @Test("Loudness makeup rises with dampening")
    func makeupGain() {
        // Without this the slider would be indistinguishable from turning the
        // volume down, which is the one thing dampening must not be.
        #expect(DampeningCurve.makeupGainDB(for: 0) == 0)
        #expect(DampeningCurve.makeupGainDB(for: 0.5) > 0)
        #expect(DampeningCurve.makeupGainDB(for: 1) > DampeningCurve.makeupGainDB(for: 0.5))
    }

    @Test("The cutoff sweep is logarithmic, not linear")
    func logarithmicCutoff() {
        // A linear sweep would put almost the whole audible change in the last
        // few per cent of the slider. Halfway along, the corner should be far
        // below the arithmetic midpoint of the two ends.
        let midpoint = DampeningCurve.parameters(for: 0.5).highFrequencyCutoff
        let arithmeticMean =
            (DampeningCurve.sharp.highFrequencyCutoff + DampeningCurve.muted.highFrequencyCutoff)
            / 2
        #expect(midpoint < arithmeticMean)
    }
}
