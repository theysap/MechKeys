import AVFoundation
import Foundation

/// Offline sample processing.
///
/// Two parts of the dampening chain cannot be done by a filter on the output
/// bus, because they are about the *shape* of a one-shot rather than its
/// spectrum:
///
///   * **Transient shaping** — softening the first few milliseconds of attack.
///     A compressor would need lookahead to do this, and lookahead is latency.
///   * **Resonance / ring-out** — choking the decaying tail so a heavily
///     dampened board stops ringing.
///
/// Both are applied here, offline, when the cache is built. Nothing in this
/// file runs on a keypress: by the time a key is pressed the processed buffer
/// already exists and is simply scheduled. That is what keeps latency down.
public enum SamplePreparation {

    /// How far into the sample the attack is considered to run.
    public static let attackWindowSeconds: Float = 0.007
    /// Where the tail starts, for ring-out purposes.
    public static let tailStartSeconds: Float = 0.009
    /// Shortest extra decay time constant at full resonance reduction.
    public static let minimumTailTimeConstant: Float = 0.018

    /// Softens the leading edge without moving it.
    ///
    /// The first sample is attenuated by `reduction`, recovering to unity by
    /// the end of the attack window. The onset stays at sample zero — the
    /// sound is never delayed, it just arrives less sharply.
    public static func shapeTransient(_ samples: inout [Float],
                                      reduction: Float,
                                      sensitivity: Float = 1.0,
                                      sampleRate: Float) {
        let amount = (reduction * sensitivity).clamped(to: 0...1)
        guard amount > 0.0001 else { return }

        let window = Int(attackWindowSeconds * sampleRate)
        guard window > 1 else { return }
        let limit = min(window, samples.count)

        for index in 0..<limit {
            let progress = Float(index) / Float(window)
            // Smoothstep back to unity: no corner in the gain curve, so the
            // softening itself cannot be heard as a click.
            let recovery = progress * progress * (3 - 2 * progress)
            samples[index] *= (1 - amount) + amount * recovery
        }
    }

    /// Chokes the decaying tail, so a dampened board stops ringing.
    public static func dampenResonance(_ samples: inout [Float],
                                       reduction: Float,
                                       sampleRate: Float) {
        let amount = reduction.clamped(to: 0...1)
        guard amount > 0.0001 else { return }

        let start = Int(tailStartSeconds * sampleRate)
        guard start < samples.count else { return }

        // Time constant sweeps from "no extra decay" to a very fast choke.
        let timeConstant = minimumTailTimeConstant / amount
        let step = 1.0 / sampleRate

        var elapsed: Float = 0
        for index in start..<samples.count {
            samples[index] *= expf(-elapsed / timeConstant)
            elapsed += step
        }
    }

    /// Linear-interpolating resampler used for pitch trim and micro-variation.
    ///
    /// A ratio above 1 shortens the sample and raises the pitch, exactly as
    /// playing a recording faster would. Linear interpolation is more than
    /// adequate here: the shifts are small and the material is noisy.
    public static func resample(_ samples: [Float], ratio: Float) -> [Float] {
        guard abs(ratio - 1.0) > 0.0001, ratio > 0.01, !samples.isEmpty else { return samples }

        let outputCount = max(1, Int(Float(samples.count) / ratio))
        var output = [Float](repeating: 0, count: outputCount)

        for index in 0..<outputCount {
            let position = Float(index) * ratio
            let lower = Int(position)
            guard lower + 1 < samples.count else {
                output[index] = samples[samples.count - 1]
                continue
            }
            let fraction = position - Float(lower)
            output[index] = samples[lower] * (1 - fraction) + samples[lower + 1] * fraction
        }
        return output
    }

    /// Converts semitones to a playback-rate ratio.
    public static func rate(forSemitones semitones: Float) -> Float {
        powf(2, semitones / 12)
    }

    /// Guards against a processed buffer exceeding full scale.
    public static func normalizeIfClipping(_ samples: inout [Float], ceiling: Float = 0.99) {
        var peak: Float = 0
        for sample in samples { peak = max(peak, abs(sample)) }
        guard peak > ceiling else { return }
        let scale = ceiling / peak
        for index in samples.indices { samples[index] *= scale }
    }

    // MARK: - Buffer bridging

    public static func samples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let data = buffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
    }

    public static func buffer(from samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let data = buffer.floatChannelData
        else { return nil }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        // Mono source fanned out to however many channels the format declares.
        for channel in 0..<Int(format.channelCount) {
            samples.withUnsafeBufferPointer { source in
                data[channel].update(from: source.baseAddress!, count: samples.count)
            }
        }
        return buffer
    }
}
