import AVFoundation
import Accelerate
import Foundation
import Testing

@testable import MechKeysCore

/// End-to-end measurements of the real audio graph, rendered offline.
///
/// These are the tests that hold the product's central claim: moving the
/// dampening slider changes the *sound*, not the *level*. Everything is
/// rendered through `AVAudioEngine`'s manual rendering mode, so no speaker,
/// no output device and no audio hardware of any kind is involved.
/// Serialised: each test here builds a real `AVAudioEngine` graph, and several
/// of them rendering at once contend for CPU enough to jitter the offline
/// scheduling — which showed up as an onset measurement that passed alone and
/// failed in a full parallel run.
@Suite("Dampening, measured", .serialized)
struct DampeningRenderTests {

    private static let sampleRate: Double = 48_000

    private func settings(dampening: Double, profile: SoundProfile = .blue) -> AppSettings {
        var settings = AppSettings.default
        settings.profile = profile
        settings.dampening = dampening
        settings.volume = 0.8
        // Variation off: two renders must be comparable, and a different
        // sample or a different detune each time would drown the signal.
        settings.variationAmount = 0
        settings.pitchVariationEnabled = false
        return settings.normalized()
    }

    private func render(dampening: Double, profile: SoundProfile = .blue) throws -> [Float] {
        let engine = AVSoundEngine()
        let samples = try engine.renderOneShot(
            category: .standard, settings: settings(dampening: dampening, profile: profile))
        try #require(!samples.isEmpty, "the graph rendered nothing")
        return samples
    }

    /// Energy above `cutoff`, as a fraction of total energy.
    ///
    /// Measuring the *proportion* rather than the absolute amount is what
    /// separates dampening from a volume cut: turning something down scales
    /// both halves equally and leaves this number unchanged.
    ///
    /// A real FFT, not a handful of sampled bins — a sparse DFT aliases badly
    /// on broadband material like this and produced ratios that disagreed with
    /// the known spectra of the samples.
    private func highFrequencyRatio(_ samples: [Float], above cutoff: Double = 3_000) -> Double {
        let log2n = 14  // 16384 samples, ≈341 ms at 48 kHz
        let count = 1 << log2n
        guard samples.count >= count / 2 else { return 0 }

        // Zero-padded to the transform length, and Hann-windowed so the abrupt
        // end of a one-shot does not smear energy across the whole spectrum.
        var windowed = [Float](repeating: 0, count: count)
        let available = min(count, samples.count)
        var hann = [Float](repeating: 0, count: available)
        vDSP_hann_window(&hann, vDSP_Length(available), Int32(vDSP_HANN_NORM))
        for index in 0..<available {
            windowed[index] = samples[index] * hann[index]
        }

        guard
            let fft = vDSP.FFT(
                log2n: vDSP_Length(log2n), radix: .radix2, ofType: DSPSplitComplex.self)
        else { return 0 }

        var real = [Float](repeating: 0, count: count / 2)
        var imaginary = [Float](repeating: 0, count: count / 2)
        var magnitudes = [Float](repeating: 0, count: count / 2)

        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(
                    realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)

                windowed.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(
                        to: DSPComplex.self, capacity: count / 2
                    ) { interleaved in
                        vDSP_ctoz(interleaved, 2, &split, 1, vDSP_Length(count / 2))
                    }
                }

                fft.forward(input: split, output: &split)
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(count / 2))
            }
        }

        let binWidth = Self.sampleRate / Double(count)
        var totalEnergy = 0.0
        var highEnergy = 0.0
        // Bin 0 is DC and carries no information about brightness.
        for bin in 1..<(count / 2) {
            let energy = Double(magnitudes[bin])
            totalEnergy += energy
            if Double(bin) * binWidth >= cutoff { highEnergy += energy }
        }

        return totalEnergy > 0 ? highEnergy / totalEnergy : 0
    }

    private func peak(_ samples: [Float]) -> Float {
        samples.reduce(0) { max($0, abs($1)) }
    }

    private func rms(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        return (sum / Double(samples.count)).squareRoot()
    }

    @Test("The graph actually produces sound")
    func producesAudio() throws {
        let samples = try render(dampening: 0.3)
        #expect(peak(samples) > 0.01, "rendered output is silent")
        #expect(peak(samples) <= 1.0, "rendered output clips")
    }

    @Test("Dampening removes high-frequency energy")
    func dampeningRemovesTreble() throws {
        let sharp = try render(dampening: 0.0)
        let muted = try render(dampening: 1.0)

        let sharpRatio = highFrequencyRatio(sharp)
        let mutedRatio = highFrequencyRatio(muted)

        // The whole point of the control. A heavily dampened board has
        // markedly less of its energy up top.
        #expect(
            mutedRatio < sharpRatio * 0.5,
            "high-frequency ratio went \(sharpRatio) -> \(mutedRatio)")
    }

    @Test("High-frequency content falls monotonically across the slider")
    func trebleFallsMonotonically() throws {
        var ratios: [Double] = []
        for position in [0.0, 0.25, 0.5, 0.75, 1.0] {
            ratios.append(highFrequencyRatio(try render(dampening: position)))
        }

        for (lower, higher) in zip(ratios, ratios.dropFirst()) {
            #expect(higher <= lower, "treble rose somewhere along the slider: \(ratios)")
        }

        // Measured on the shipping chain: the proportion of energy above
        // 3 kHz falls by more than two orders of magnitude end to end.
        #expect(ratios.first! / ratios.last! > 50, "treble barely moved: \(ratios)")
    }

    @Test("Dampening is not a volume control")
    func dampeningIsNotVolume() throws {
        let sharp = try render(dampening: 0.0)
        let muted = try render(dampening: 1.0)

        // Loudness compensation exists precisely so that the two ends of the
        // slider are comparable in level. If full dampening were much quieter,
        // the control would be indistinguishable from the volume slider.
        let ratio = rms(muted) / rms(sharp)
        #expect(
            ratio > 0.3, "fully dampened output is \(ratio)x the level — too quiet to be dampening")
    }

    @Test("Dampening does not delay the sound")
    func dampeningDoesNotDelay() throws {
        func onset(_ samples: [Float]) -> Int {
            let threshold = peak(samples) * 0.1
            return samples.firstIndex { abs($0) >= threshold } ?? samples.count
        }

        let sharpOnset = onset(try render(dampening: 0.0))
        let mutedOnset = onset(try render(dampening: 1.0))

        // Softening an attack moves the moment the sound reaches full
        // amplitude, but it must not push the *start* of the sound later in
        // any way a typist could feel. Measured drift across the whole slider
        // is about a third of a millisecond; 3 ms is a generous ceiling and
        // still an order of magnitude below the ~10 ms where a delay between
        // keypress and sound starts to be noticed.
        let driftMilliseconds = Double(abs(mutedOnset - sharpOnset)) / Self.sampleRate * 1000
        #expect(driftMilliseconds < 3, "onset moved by \(driftMilliseconds) ms")
    }

    @Test("Every profile renders, and they differ in brightness as described")
    func profilesDifferInBrightness() throws {
        var ratios: [SoundProfile: Double] = [:]
        for profile in SoundProfile.allCases {
            let samples = try render(dampening: 0.0, profile: profile)
            #expect(peak(samples) > 0.01, "\(profile.rawValue) rendered silence")
            ratios[profile] = highFrequencyRatio(samples)
        }

        // Blue is the clicky one and Black the deep one; that ordering is the
        // entire reason someone picks one over the other.
        #expect(ratios[.blue]! > ratios[.brown]!)
        #expect(ratios[.brown]! > ratios[.red]!)
        #expect(ratios[.red]! > ratios[.yellow]!)
        #expect(ratios[.yellow]! > ratios[.black]!)
    }

    @Test("Bigger keys are deeper than ordinary ones")
    func largeKeysAreDeeper() throws {
        let engine = AVSoundEngine()
        let configuration = settings(dampening: 0.0)

        let standard = try engine.renderOneShot(category: .standard, settings: configuration)
        let space = try AVSoundEngine().renderOneShot(category: .space, settings: configuration)

        #expect(highFrequencyRatio(space) < highFrequencyRatio(standard))
    }

    @Test("Manual DSP values override the slider in the rendered output")
    func manualOverrideReachesTheGraph() throws {
        var manual = settings(dampening: 0.0)
        manual.usesAdvancedDampening = true
        manual.advancedDampening = DampeningCurve.parameters(for: 1.0)

        let rendered = try AVSoundEngine().renderOneShot(category: .standard, settings: manual)
        let sharp = try render(dampening: 0.0)

        // The slider says 0%, the manual values say 100%. The sound must
        // follow the manual values.
        #expect(highFrequencyRatio(rendered) < highFrequencyRatio(sharp) * 0.6)
    }
}
