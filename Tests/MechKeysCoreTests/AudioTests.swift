import AVFoundation
import Foundation
import Testing

@testable import MechKeysCore

@Suite("Sample preparation")
struct SamplePreparationTests {

    private let sampleRate: Float = 48_000

    /// A crude one-shot: an instant spike, then a slowly decaying tail. Enough
    /// to tell whether the processing does what it claims.
    private func makeImpulse(seconds: Float = 0.2) -> [Float] {
        let count = Int(seconds * sampleRate)
        return (0..<count).map { index in
            let t = Float(index) / sampleRate
            return (index < 16 ? 1.0 : 0.35) * expf(-t / 0.05)
        }
    }

    @Test("Transient shaping softens the attack without moving it")
    func transientShapingDoesNotDelay() {
        var shaped = makeImpulse()
        let original = shaped
        SamplePreparation.shapeTransient(&shaped, reduction: 0.9, sampleRate: sampleRate)

        // The peak is lower...
        #expect(shaped[0] < original[0])
        // ...but the sound still starts at sample zero. Dampening is not a
        // delay, and this is the test that holds that line.
        #expect(shaped[0] > 0)
        #expect(shaped.count == original.count)
    }

    @Test("Transient shaping leaves the body of the sound alone")
    func transientShapingIsLocal() {
        var shaped = makeImpulse()
        let original = shaped
        SamplePreparation.shapeTransient(&shaped, reduction: 1.0, sampleRate: sampleRate)

        // Well past the attack window, the samples are untouched.
        let late = Int(0.05 * sampleRate)
        #expect(shaped[late] == original[late])
    }

    @Test("More reduction means a softer attack")
    func transientShapingScales() {
        var light = makeImpulse()
        var heavy = makeImpulse()
        SamplePreparation.shapeTransient(&light, reduction: 0.25, sampleRate: sampleRate)
        SamplePreparation.shapeTransient(&heavy, reduction: 0.95, sampleRate: sampleRate)
        #expect(heavy[0] < light[0])
    }

    @Test("Zero reduction changes nothing at all")
    func transientShapingNoOp() {
        var samples = makeImpulse()
        let original = samples
        SamplePreparation.shapeTransient(&samples, reduction: 0, sampleRate: sampleRate)
        #expect(samples == original)
    }

    @Test("Resonance damping shortens the tail and spares the start")
    func resonanceDamping() {
        var damped = makeImpulse()
        let original = damped
        SamplePreparation.dampenResonance(&damped, reduction: 0.9, sampleRate: sampleRate)

        let early = Int(0.002 * sampleRate)
        let late = Int(0.12 * sampleRate)

        // The onset is before the tail starts, so it is untouched.
        #expect(damped[early] == original[early])
        // The ring is very much reduced.
        #expect(damped[late] < original[late] * 0.2)
    }

    @Test("Resampling changes length in inverse proportion to pitch")
    func resampling() {
        let samples = makeImpulse(seconds: 0.1)

        // An octave up is half as long.
        let up = SamplePreparation.resample(samples, ratio: 2.0)
        #expect(abs(up.count - samples.count / 2) <= 1)

        // An octave down is twice as long.
        let down = SamplePreparation.resample(samples, ratio: 0.5)
        #expect(abs(down.count - samples.count * 2) <= 1)

        // A ratio of one is not worth the work.
        #expect(SamplePreparation.resample(samples, ratio: 1.0).count == samples.count)
    }

    @Test("Semitones convert to the usual playback ratios")
    func semitoneConversion() {
        #expect(SamplePreparation.rate(forSemitones: 0) == 1)
        #expect(abs(SamplePreparation.rate(forSemitones: 12) - 2) < 0.0001)
        #expect(abs(SamplePreparation.rate(forSemitones: -12) - 0.5) < 0.0001)
    }

    @Test("Processing that pushes a sample over full scale is pulled back")
    func clippingGuard() {
        var hot = [Float](repeating: 2.5, count: 128)
        SamplePreparation.normalizeIfClipping(&hot)
        #expect(hot.allSatisfy { abs($0) <= 0.99 })

        // Something already within range is left exactly as it was.
        var quiet: [Float] = [0.1, -0.2, 0.3]
        let original = quiet
        SamplePreparation.normalizeIfClipping(&quiet)
        #expect(quiet == original)
    }

    @Test("Buffers survive a round trip through the audio format")
    func bufferRoundTrip() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let samples = makeImpulse(seconds: 0.01)

        let buffer = try #require(SamplePreparation.buffer(from: samples, format: format))
        #expect(Int(buffer.frameLength) == samples.count)
        #expect(SamplePreparation.samples(from: buffer) == samples)
    }

    @Test("An empty sample array produces no buffer rather than an empty one")
    func emptyBuffer() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        #expect(SamplePreparation.buffer(from: [], format: format) == nil)
    }
}

@Suite("Sound library")
struct SoundLibraryTests {

    @Test("The bundled library is found and every profile has every category")
    func bundledLibraryIsComplete() {
        let library = SoundLibrary()
        try? #require(library.rootURL != nil)

        for profile in SoundProfile.allCases {
            for category in KeyCategory.allCases {
                let samples = library.rawSamples(profile: profile, category: category)
                #expect(!samples.isEmpty, "\(profile.rawValue)/\(category.rawValue) has no samples")
                // Multiple variants are what stop repeated keys sounding
                // mechanical.
                #expect(samples.count >= 2)
            }
        }
    }

    @Test("A missing library is reported, not crashed on")
    func missingLibrary() {
        let nowhere = URL(fileURLWithPath: "/var/empty/mechkeys-does-not-exist")
        let library = SoundLibrary(rootURL: nowhere)

        #expect(library.rawSamples(profile: .blue, category: .standard).isEmpty)

        let report = library.preload(profile: .blue)
        #expect(report.isUsable == false)
        #expect(!report.missing.isEmpty)
    }

    @Test("A category with no samples falls back to the ordinary ones")
    func fallsBackToStandard() throws {
        // A library with only `standard_01.wav` in it: the spacebar has to
        // borrow rather than fall silent.
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mechkeys-partial-\(UUID().uuidString)")
        let profileDirectory = root.appendingPathComponent(SoundProfile.blue.directoryName)
        try FileManager.default.createDirectory(
            at: profileDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = try #require(SoundLibrary().rootURL)
            .appendingPathComponent("blue/standard_01.wav")
        try FileManager.default.copyItem(
            at: source, to: profileDirectory.appendingPathComponent("standard_01.wav"))

        let library = SoundLibrary(rootURL: root)
        #expect(library.rawSamples(profile: .blue, category: .space).isEmpty)
        #expect(!library.resolvedSamples(profile: .blue, category: .space).isEmpty)
    }
}

@Suite("Sound engine contract")
struct SoundEngineTests {

    @Test("The recording double reports what it was asked to play")
    func recordingEngine() throws {
        let engine = RecordingSoundEngine()
        #expect(engine.isRunning == false)

        try engine.start()
        #expect(engine.isRunning)

        engine.play(keyCategory: .space, profile: .blue)
        engine.play(keyCategory: .standard, profile: .blue)
        #expect(engine.played.count == 2)
        #expect(engine.played.first?.category == .space)

        engine.setVolume(0.4)
        engine.setDampening(0.7)
        #expect(engine.volume == 0.4)
        #expect(engine.dampening == 0.7)

        engine.stop()
        #expect(engine.isRunning == false)
    }

    @Test("A start failure surfaces as an error rather than a silent no-op")
    func startFailure() {
        let engine = RecordingSoundEngine()
        engine.startError = SoundEngineError.outputUnavailable("no device")

        #expect(throws: SoundEngineError.self) { try engine.start() }
        #expect(engine.isRunning == false)
    }

    @Test("Engine errors explain themselves")
    func errorMessages() {
        let error = SoundEngineError.libraryUnavailable("Looked in /tmp.")
        #expect(error.errorDescription?.isEmpty == false)
        #expect(error.recoverySuggestion?.contains("/tmp") == true)
    }
}

@Suite("Natural variation")
struct SoundVariationTests {

    @Test("The same variant is not played twice in a row")
    func avoidsImmediateRepeats() {
        var variation = SoundVariation()
        var previous = variation.nextIndex(count: 5, category: .standard)
        var repeats = 0

        for _ in 0..<400 {
            let next = variation.nextIndex(count: 5, category: .standard)
            if next == previous { repeats += 1 }
            previous = next
        }

        // One re-roll, not a guarantee: forcing a different sample every time
        // would itself be an audible pattern. With five samples, chance alone
        // gives 20%; one re-roll should bring it well under half that.
        #expect(repeats < 40)
    }

    @Test("Indices stay inside the pool")
    func indicesInRange() {
        var variation = SoundVariation()
        for _ in 0..<200 {
            let index = variation.nextIndex(count: 3, category: .space)
            #expect((0..<3).contains(index))
        }
        // A single-sample pool has exactly one answer.
        #expect(variation.nextIndex(count: 1, category: .enter) == 0)
    }

    @Test("Amplitude jitter stays within a couple of dB")
    func amplitudeJitterIsSubtle() {
        var variation = SoundVariation()
        for _ in 0..<300 {
            let scalar = variation.nextAmplitudeScalar(amount: 1.0)
            // ±2 dB is roughly 0.79...1.26. Anything outside that would be
            // heard as a random volume generator rather than as natural.
            #expect(scalar > 0.75 && scalar < 1.30)
        }
    }

    @Test("Variation turned off means no variation at all")
    func noVariation() {
        var variation = SoundVariation()
        #expect(variation.nextAmplitudeScalar(amount: 0) == 1)
        #expect(SoundVariation.pitchOffsetsCents(amount: 0, enabled: true) == [0])
        #expect(SoundVariation.pitchOffsetsCents(amount: 1, enabled: false) == [0])
    }

    @Test("Pitch offsets are symmetrical and small")
    func pitchOffsets() {
        let offsets = SoundVariation.pitchOffsetsCents(amount: 1, enabled: true)
        #expect(offsets.count == 3)
        #expect(offsets[1] == 0)
        #expect(offsets[0] == -offsets[2])
        // Under a fifth of a semitone: perceptible as life, not as detuning.
        #expect(abs(offsets[2]) <= 20)
    }
}

@Suite("Variation determinism")
struct VariationDeterminismTests {

    @Test("Variation at zero means the same sample every time")
    func zeroVariationIsDeterministic() {
        var variation = SoundVariation()
        // "Identical" on the slider has to mean identical, not just the same
        // level and pitch with a different recording underneath.
        let indices = (0..<50).map { _ in
            variation.nextIndex(count: 5, category: .standard, amount: 0)
        }
        #expect(indices.allSatisfy { $0 == 0 })
    }

    @Test("Variation above zero does move between samples")
    func nonZeroVariationRotates() {
        var variation = SoundVariation()
        let indices = Set(
            (0..<80).map { _ in
                variation.nextIndex(count: 5, category: .standard, amount: 1)
            })
        #expect(indices.count > 1)
    }
}
