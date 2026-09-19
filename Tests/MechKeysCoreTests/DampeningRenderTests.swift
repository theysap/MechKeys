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
        let magnitudes = spectrum(samples)
        let binWidth = Self.sampleRate / Double((magnitudes.count - 1) * 2)
        var totalEnergy = 0.0
        var highEnergy = 0.0
        // Bin 0 is DC and says nothing about brightness.
        for bin in 1..<magnitudes.count {
            let energy = Double(magnitudes[bin])
            totalEnergy += energy
            if Double(bin) * binWidth >= cutoff { highEnergy += energy }
        }
        return totalEnergy > 0 ? highEnergy / totalEnergy : 0
    }

    /// Magnitude-squared spectrum of the first 16384 samples.
    ///
    /// Deliberately unwindowed. A one-shot already starts at zero and decays
    /// to zero, so there is no discontinuity for a window to fix — and a Hann
    /// window is null at sample zero, which would attenuate the attack, the
    /// very part that distinguishes a clicky profile from a soft one.
    private func spectrum(_ samples: [Float]) -> [Float] {
        let log2n = 14
        let count = 1 << log2n
        guard samples.count >= count / 2 else { return [] }

        var padded = [Float](repeating: 0, count: count)
        let available = min(count, samples.count)
        for index in 0..<available { padded[index] = samples[index] }

        guard
            let fft = vDSP.FFT(
                log2n: vDSP_Length(log2n), radix: .radix2, ofType: DSPSplitComplex.self)
        else { return [] }

        var real = [Float](repeating: 0, count: count / 2)
        var imaginary = [Float](repeating: 0, count: count / 2)
        var magnitudes = [Float](repeating: 0, count: count / 2)

        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(
                    realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                padded.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: count / 2) {
                        interleaved in
                        vDSP_ctoz(interleaved, 2, &split, 1, vDSP_Length(count / 2))
                    }
                }
                fft.forward(input: split, output: &split)
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(count / 2))
            }
        }
        return magnitudes
    }

    /// Spectral centroid, in Hz — the standard measure of brightness.
    ///
    /// Not the same question as `highFrequencyRatio`, and the two genuinely
    /// disagree here. A Box Navy puts enormous energy into a click at 2.3 kHz,
    /// which sits *below* a 3 kHz band split, so its share of energy above
    /// that line is unremarkable even though it is plainly the brightest of
    /// the five. Ranking profiles is a centroid question; measuring what
    /// dampening removes is a band question.
    private func spectralCentroid(_ samples: [Float]) -> Double {
        let magnitudes = spectrum(samples)
        let binWidth = Self.sampleRate / Double((magnitudes.count - 1) * 2)
        var weighted = 0.0
        var total = 0.0
        for bin in 1..<magnitudes.count {
            let energy = Double(magnitudes[bin])
            weighted += energy * Double(bin) * binWidth
            total += energy
        }
        return total > 0 ? weighted / total : 0
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
        // 3 kHz falls from 0.56 to 0.0007 — nearly three orders of magnitude.
        #expect(ratios.first! / ratios.last! > 200, "treble barely moved: \(ratios)")
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

    @Test("Dampening softens the attack without pushing the sound later")
    func dampeningDoesNotDelay() throws {
        let sharp = try render(dampening: 0.0)
        let muted = try render(dampening: 1.0)

        // `renderOneShot` trims the offline scheduler's own leading silence,
        // so index zero is the true start of the sound. Both ends of the
        // slider have signal in that very first sample: the chain inserts no
        // silence whatsoever, which is the property that matters. Dampening is
        // not, and must never become, a delay.
        #expect(sharp.first != 0)
        #expect(muted.first != 0)

        // What dampening legitimately changes is how quickly the attack
        // arrives at full amplitude — that is what softening a transient
        // means. Measured at 4.3 ms on the shipping chain, comfortably inside
        // the ~10 ms at which a gap between key and sound starts to be felt.
        func riseTime(_ samples: [Float]) -> Double {
            let threshold = peak(samples) * 0.1
            let index = samples.firstIndex { abs($0) >= threshold } ?? samples.count
            return Double(index) / Self.sampleRate * 1000
        }

        let difference = abs(riseTime(muted) - riseTime(sharp))
        #expect(difference < 8, "attack moved by \(difference) ms")
    }

    @Test("Every profile renders, and they differ in brightness as described")
    func profilesDifferInBrightness() throws {
        var ratios: [SoundProfile: Double] = [:]
        for profile in SoundProfile.allCases {
            let samples = try render(dampening: 0.0, profile: profile)
            #expect(peak(samples) > 0.01, "\(profile.rawValue) rendered silence")
            #expect(peak(samples) <= 1.0, "\(profile.rawValue) clips")
            ratios[profile] = spectralCentroid(samples)
        }

        // Measured from the bundled recordings, brightest to darkest: Box
        // Navy, Ink Red, Ink Black, Cream, Holy Panda. Holy Panda being the
        // darkest is not an accident of the take — it is a deep tactile, and
        // that is exactly what someone choosing it is choosing.
        #expect(ratios[.blue]! > ratios[.red]!, "centroids: \(ratios)")
        #expect(ratios[.red]! > ratios[.black]!, "centroids: \(ratios)")
        #expect(ratios[.black]! > ratios[.yellow]!, "centroids: \(ratios)")
        #expect(ratios[.yellow]! > ratios[.brown]!, "centroids: \(ratios)")
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
