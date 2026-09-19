import AVFoundation
import Foundation
import OSLog

/// The real audio engine.
///
/// ## Architecture
///
/// ```
///   [player 0] ─┐
///   [player 1] ─┼─▶ bus mixer ─▶ EQ (4 bands) ─▶ dynamics ─▶ main mixer ─▶ out
///   [player n] ─┘
/// ```
///
/// The graph is built once at launch and stays alive for the life of the
/// process. A keypress does no allocation, no file I/O and no node creation —
/// it picks an already-processed buffer and schedules it on a free player.
///
/// The dampening chain is split in two, by necessity:
///
///   * **Offline, in the buffer cache** — transient softening and ring-out.
///     These reshape the one-shot itself and are re-rendered on a background
///     queue whenever the relevant settings change.
///   * **Live, on the shared bus** — low-pass, high shelf, resonance notch,
///     low-mid shelf and compression. These are just parameter writes, so they
///     take effect on the very next keypress with no rebuild.
public final class AVSoundEngine: SoundEngine {

    // MARK: Graph

    private let engine = AVAudioEngine()
    private let busMixer = AVAudioMixerNode()
    private let equalizer = AVAudioUnitEQ(numberOfBands: 4)
    private let dynamics = DynamicsProcessor()
    private var players: [AVAudioPlayerNode] = []

    /// Frame time (on the shared clock) at which each player is free again.
    private var playerFreeAt: [Double] = []

    /// Mono float32. Player nodes feed this; the main mixer handles the
    /// conversion to whatever the hardware wants, including sample-rate
    /// conversion when the output device is running at 44.1 kHz.
    private let processingFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!

    // MARK: State

    private let library: SoundLibrary
    private let logger = Logger(subsystem: "com.mechkeys.app", category: "AudioEngine")

    /// Everything touching the engine runs here. Serialising on one
    /// user-interactive queue keeps the CGEvent callback free and keeps
    /// AVAudioEngine off the main thread.
    private let queue = DispatchQueue(label: "com.mechkeys.audio", qos: .userInteractive)

    private var settings: AppSettings = .default
    private var variation = SoundVariation()
    private var preparedBuffers: [KeyCategory: [AVAudioPCMBuffer]] = [:]
    private var preparationSignature: PreparationSignature?
    private var pendingRebuild: DispatchWorkItem?
    private var running = false
    private var restartAttempts = 0

    public private(set) var lastError: SoundEngineError?

    /// Inputs that force the offline cache to be re-rendered. Quantised so
    /// that dragging a slider does not trigger a rebuild per pixel.
    private struct PreparationSignature: Equatable {
        let profile: SoundProfile
        let transient: Int
        let resonance: Int
        let variation: Int
        let pitchVariation: Bool
        let categoryPitch: [KeyCategory: Int]

        init(settings: AppSettings) {
            let parameters = settings.effectiveDampening
            profile = settings.profile
            transient = Int((parameters.transientReduction * 50).rounded())
            resonance = Int((parameters.resonanceReduction * 50).rounded())
            variation = Int((settings.variationAmount * 20).rounded())
            pitchVariation = settings.pitchVariationEnabled
            categoryPitch = Dictionary(uniqueKeysWithValues: KeyCategory.allCases.map {
                ($0, Int((settings.settings(for: $0).pitchSemitones * 10).rounded()))
            })
        }
    }

    public var isRunning: Bool {
        queue.sync { running && engine.isRunning }
    }

    public init(library: SoundLibrary = SoundLibrary()) {
        self.library = library
        observeConfigurationChanges()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Lifecycle

    public func start() throws {
        try queue.sync {
            guard !running else { return }

            let report = library.preload(profile: settings.profile)
            guard report.isUsable else {
                let error = SoundEngineError.libraryUnavailable(
                    report.rootPath.map { "Looked in \($0)." } ?? "No Sounds folder was found in the app bundle."
                )
                lastError = error
                throw error
            }

            buildGraph()
            rebuildCacheIfNeeded(force: true)

            do {
                engine.prepare()
                try engine.start()
            } catch {
                let failure = SoundEngineError.outputUnavailable(error.localizedDescription)
                lastError = failure
                logger.error("Engine start failed: \(error.localizedDescription, privacy: .public)")
                throw failure
            }

            // Player nodes are left in the playing state for the lifetime of
            // the engine. Scheduling a buffer on an already-playing node
            // starts it immediately; calling play() per keypress would add a
            // few milliseconds of avoidable latency.
            players.forEach { $0.play() }

            running = true
            restartAttempts = 0
            lastError = nil
            applyLiveParameters()
        }
    }

    public func stop() {
        queue.sync {
            guard running else { return }
            players.forEach { $0.stop() }
            engine.stop()
            running = false
        }
    }

    // MARK: - Graph construction

    private func buildGraph() {
        // Tear down anything from a previous configuration. Called again after
        // an output-device change, when formats may be completely different.
        players.forEach { node in
            node.stop()
            engine.detach(node)
        }
        players.removeAll()
        playerFreeAt.removeAll()

        for node in [busMixer as AVAudioNode, equalizer, dynamics] where node.engine != nil {
            engine.detach(node)
        }

        engine.attach(busMixer)
        engine.attach(equalizer)
        engine.attach(dynamics)

        engine.connect(busMixer, to: equalizer, format: processingFormat)
        engine.connect(equalizer, to: dynamics, format: processingFormat)
        engine.connect(dynamics, to: engine.mainMixerNode, format: processingFormat)

        let voiceCount = settings.maximumVoices
        for _ in 0..<voiceCount {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: busMixer, format: processingFormat)
            players.append(player)
            playerFreeAt.append(0)
        }
    }

    /// macOS posts this when the user switches to AirPods, unplugs a monitor,
    /// or changes the default output device. The engine has stopped by the
    /// time it arrives, and the old connections reference a format that no
    /// longer exists, so the graph is rebuilt from scratch.
    private func observeConfigurationChanges() {
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    private func handleConfigurationChange() {
        queue.async { [weak self] in
            guard let self, self.running else { return }
            self.logger.info("Audio configuration changed; rebuilding graph.")
            self.running = false
            self.engine.stop()
            self.buildGraph()
            self.rebuildCacheIfNeeded(force: true)
            do {
                self.engine.prepare()
                try self.engine.start()
                self.players.forEach { $0.play() }
                self.running = true
                self.restartAttempts = 0
                self.lastError = nil
                self.applyLiveParameters()
            } catch {
                self.lastError = .outputUnavailable(error.localizedDescription)
                self.logger.error("Restart after device change failed: \(error.localizedDescription, privacy: .public)")
                self.scheduleRecovery()
            }
        }
    }

    /// If the output device is momentarily unavailable — waking from sleep,
    /// a Bluetooth device still connecting — back off and try again a few
    /// times rather than giving up silently.
    private func scheduleRecovery() {
        guard restartAttempts < 5 else { return }
        restartAttempts += 1
        let delay = Double(restartAttempts) * 1.5
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.running else { return }
            do {
                self.engine.prepare()
                try self.engine.start()
                self.players.forEach { $0.play() }
                self.running = true
                self.lastError = nil
                self.applyLiveParameters()
                self.logger.info("Audio output recovered.")
            } catch {
                self.scheduleRecovery()
            }
        }
    }

    // MARK: - Settings

    public func apply(_ settings: AppSettings) {
        queue.async { [weak self] in
            guard let self else { return }
            let previousVoiceCount = self.settings.maximumVoices
            self.settings = settings.normalized()

            if self.running && previousVoiceCount != self.settings.maximumVoices {
                // Changing the pool size means rebuilding connections.
                self.engine.stop()
                self.buildGraph()
                try? self.engine.start()
                self.players.forEach { $0.play() }
            }

            self.applyLiveParameters()
            self.scheduleCacheRebuild()
        }
    }

    public func setVolume(_ volume: Float) {
        queue.async { [weak self] in
            guard let self else { return }
            self.settings.volume = Double(volume).clamped(to: AppSettings.volumeRange)
            self.applyLiveParameters()
        }
    }

    public func setDampening(_ value: Float) {
        queue.async { [weak self] in
            guard let self else { return }
            self.settings.dampening = Double(value).clamped(to: AppSettings.dampeningRange)
            self.applyLiveParameters()
            self.scheduleCacheRebuild()
        }
    }

    /// Writes the filter and dynamics parameters. Cheap — this is what makes
    /// the dampening slider feel instant.
    private func applyLiveParameters() {
        let parameters = settings.effectiveDampening
        let voicing = settings.profile.voicing

        // 1. Low-pass: the main "close the lid" control.
        let lowPass = equalizer.bands[0]
        lowPass.filterType = .lowPass
        lowPass.frequency = parameters.highFrequencyCutoff
        lowPass.bypass = parameters.highFrequencyCutoff >= 18_000

        // 2. High shelf: removes air and the top of the click transient.
        let shelf = equalizer.bands[1]
        shelf.filterType = .highShelf
        shelf.frequency = 3_200
        shelf.gain = parameters.highFrequencyGain
        shelf.bypass = abs(parameters.highFrequencyGain) < 0.1

        // 3. Parametric cut aimed at *this profile's* ring. A Blue rings at
        //    5.4 kHz and a Black at 2.1 kHz; one fixed notch would dampen one
        //    and hollow out the other.
        let notch = equalizer.bands[2]
        notch.filterType = .parametric
        notch.frequency = voicing.resonanceHz
        notch.bandwidth = max(0.15, 1.0 / voicing.resonanceQ)
        notch.gain = -16.0 * parameters.resonanceReduction
        notch.bypass = parameters.resonanceReduction < 0.01

        // 4. Low shelf: puts body back, so heavy dampening reads as "thock"
        //    rather than "quiet".
        let body = equalizer.bands[3]
        body.filterType = .lowShelf
        body.frequency = max(80, voicing.bodyHz * 1.15)
        body.gain = parameters.lowMidGain
        body.bypass = abs(parameters.lowMidGain) < 0.1

        equalizer.globalGain = 0
        equalizer.bypass = false

        // Gentle compression: evens out what is left of the peaks. A lower
        // threshold with less headroom means a harder squeeze.
        let amount = parameters.compressionAmount
        dynamics.configure(
            threshold: -6 - (24 * amount),
            headRoom: 14 - (11.5 * amount),
            attackTime: 0.002 + (0.006 * amount),
            releaseTime: 0.05 + (0.07 * amount),
            overallGain: settings.effectiveMakeupGainDB.clamped(to: -40...40)
        )

        // Perceptual taper: a linear slider mapped straight to amplitude puts
        // almost all of the useful range in the bottom third.
        engine.mainMixerNode.outputVolume = powf(Float(settings.volume), 1.6)
    }

    // MARK: - Offline cache

    private func scheduleCacheRebuild() {
        pendingRebuild?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.rebuildCacheIfNeeded(force: false)
        }
        pendingRebuild = work
        // Coalesce: dragging the dampening slider should re-render once, when
        // the drag settles, not sixty times a second.
        queue.asyncAfter(deadline: .now() + 0.06, execute: work)
    }

    private func rebuildCacheIfNeeded(force: Bool) {
        let signature = PreparationSignature(settings: settings)
        guard force || signature != preparationSignature else { return }
        preparationSignature = signature

        let parameters = settings.effectiveDampening
        let voicing = settings.profile.voicing
        let sampleRate = Float(processingFormat.sampleRate)
        let offsets = SoundVariation.pitchOffsetsCents(amount: settings.variationAmount,
                                                       enabled: settings.pitchVariationEnabled)

        var built: [KeyCategory: [AVAudioPCMBuffer]] = [:]
        for category in KeyCategory.allCases {
            let raw = library.resolvedSamples(profile: settings.profile, category: category)
            guard !raw.isEmpty else { continue }

            let categoryPitch = Float(settings.settings(for: category).pitchSemitones)
            var buffers: [AVAudioPCMBuffer] = []
            buffers.reserveCapacity(raw.count * offsets.count)

            for source in raw {
                for cents in offsets {
                    var samples = source
                    let ratio = SamplePreparation.rate(forSemitones: categoryPitch + cents / 100)
                    samples = SamplePreparation.resample(samples, ratio: ratio)
                    SamplePreparation.shapeTransient(&samples,
                                                     reduction: parameters.transientReduction,
                                                     sensitivity: voicing.transientSensitivity,
                                                     sampleRate: sampleRate)
                    SamplePreparation.dampenResonance(&samples,
                                                      reduction: parameters.resonanceReduction,
                                                      sampleRate: sampleRate)
                    SamplePreparation.normalizeIfClipping(&samples)
                    if let buffer = SamplePreparation.buffer(from: samples, format: processingFormat) {
                        buffers.append(buffer)
                    }
                }
            }
            built[category] = buffers
        }

        guard !built.isEmpty else {
            logger.error("Sample cache rebuild produced nothing for \(self.settings.profile.rawValue, privacy: .public)")
            return
        }
        preparedBuffers = built
    }

    // MARK: - Playback

    public func play(keyCategory: KeyCategory, profile: SoundProfile) {
        // Returns immediately. The caller may be the CGEvent tap callback, and
        // that callback must never wait for audio.
        queue.async { [weak self] in
            self?.performPlay(category: keyCategory)
        }
    }

    private func performPlay(category: KeyCategory) {
        guard running, engine.isRunning else { return }
        guard let buffers = preparedBuffers[category] ?? preparedBuffers[.standard], !buffers.isEmpty else { return }

        let index = variation.nextIndex(count: buffers.count, category: category)
        let buffer = buffers[index]

        let now = AVAudioTime.seconds(forHostTime: mach_absolute_time())
        let player = claimPlayer(at: now, duration: Double(buffer.frameLength) / processingFormat.sampleRate)

        let categorySettings = settings.settings(for: category)
        let trim = powf(10, Float(categorySettings.gainDB) / 20)
        player.volume = min(trim * variation.nextAmplitudeScalar(amount: settings.variationAmount), 4.0)

        // `.interrupts` matters when a voice is stolen under very fast typing:
        // the new sound starts now instead of queueing behind the old one.
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    /// Round-robins over the pool, preferring whichever voice has been free
    /// the longest. Under normal typing a voice is always free; under a
    /// deliberate mash the oldest one is stolen, which is inaudible.
    private func claimPlayer(at now: Double, duration: Double) -> AVAudioPlayerNode {
        var bestIndex = 0
        var bestFreeAt = Double.greatestFiniteMagnitude
        for (index, freeAt) in playerFreeAt.enumerated() {
            if freeAt <= now { bestIndex = index; bestFreeAt = freeAt; break }
            if freeAt < bestFreeAt { bestFreeAt = freeAt; bestIndex = index }
        }
        playerFreeAt[bestIndex] = now + duration
        return players[bestIndex]
    }
}
