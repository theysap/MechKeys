import AVFoundation
import Foundation

/// Finds and decodes the bundled sample library.
///
/// Everything ships inside the app bundle — there is no download step, no
/// network call and no API. The library is a folder of plain WAV files under
/// `MechKeys.app/Contents/Resources/Sounds`.
public final class SoundLibrary {

    public struct Report: Equatable, Sendable {
        public var loadedSamples: Int = 0
        public var missing: [String] = []
        public var rootPath: String?

        public var isUsable: Bool { loadedSamples > 0 }
    }

    private let fileManager = FileManager.default

    public let rootURL: URL?
    private var cache: [CacheKey: [[Float]]] = [:]
    private var reportedMissing: Set<String> = []
    private let lock = NSLock()

    private struct CacheKey: Hashable {
        let profile: SoundProfile
        let category: KeyCategory
    }

    public init(rootURL: URL? = SoundLibrary.defaultRootURL()) {
        self.rootURL = rootURL
        if rootURL == nil {
            AppLog.library.error("No sound library directory could be located.")
        }
    }

    /// Where the samples live.
    ///
    /// The environment override exists so tests and the sample-tuning workflow
    /// can point at a freshly generated library without rebuilding the app.
    public static func defaultRootURL() -> URL? {
        let fileManager = FileManager.default

        if let override = ProcessInfo.processInfo.environment["MECHKEYS_SOUNDS_DIR"] {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            if fileManager.fileExists(atPath: url.path) { return url }
        }

        // The shipping case: inside the .app bundle.
        if let resources = Bundle.main.resourceURL {
            let url = resources.appendingPathComponent("Sounds", isDirectory: true)
            if fileManager.fileExists(atPath: url.path) { return url }
        }

        // Running from a checkout (`swift test`, or the executable straight out
        // of .build): walk up from this source file to the package root.
        var candidate = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            candidate.deleteLastPathComponent()
            let url = candidate.appendingPathComponent("Resources/Sounds", isDirectory: true)
            if fileManager.fileExists(atPath: url.path) { return url }
        }

        return nil
    }

    /// Raw, unprocessed samples for one profile/category, decoded once and
    /// kept in memory. The whole library is ~2.5 MB, so caching all of it
    /// costs less than re-reading any of it.
    public func rawSamples(profile: SoundProfile, category: KeyCategory) -> [[Float]] {
        let key = CacheKey(profile: profile, category: category)

        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let loaded = loadSamples(profile: profile, category: category)

        lock.lock()
        cache[key] = loaded
        lock.unlock()

        return loaded
    }

    /// Samples for a category, falling back to `.standard` if that category's
    /// pool is missing or unreadable. A missing asset must never be fatal.
    public func resolvedSamples(profile: SoundProfile, category: KeyCategory) -> [[Float]] {
        let direct = rawSamples(profile: profile, category: category)
        if !direct.isEmpty { return direct }
        guard category != .standard else { return [] }
        AppLog.library.warning("Falling back to standard samples for \(category.rawValue, privacy: .public)")
        return rawSamples(profile: profile, category: .standard)
    }

    private func loadSamples(profile: SoundProfile, category: KeyCategory) -> [[Float]] {
        guard let rootURL else { return [] }
        let directory = rootURL.appendingPathComponent(profile.directoryName, isDirectory: true)

        guard let entries = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            noteMissing("\(profile.directoryName)/")
            return []
        }

        let matches = entries
            .filter { $0.hasPrefix("\(category.rawValue)_") && $0.hasSuffix(".wav") }
            .sorted()

        guard !matches.isEmpty else {
            noteMissing("\(profile.directoryName)/\(category.rawValue)_*.wav")
            return []
        }

        return matches.compactMap { name in
            let url = directory.appendingPathComponent(name)
            do {
                let file = try AVAudioFile(forReading: url)
                let frameCount = AVAudioFrameCount(file.length)
                guard frameCount > 0,
                      let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                    frameCapacity: frameCount)
                else {
                    noteMissing(name)
                    return nil
                }
                try file.read(into: buffer)
                let samples = SamplePreparation.samples(from: buffer)
                return samples.isEmpty ? nil : samples
            } catch {
                // A corrupt or unreadable file costs us one variant, nothing more.
                noteMissing(name)
                AppLog.library.error("Could not read \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    private func noteMissing(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        reportedMissing.insert(name)
    }

    /// Eagerly decodes one profile so the first keypress never waits on disk.
    @discardableResult
    public func preload(profile: SoundProfile) -> Report {
        var report = Report(rootPath: rootURL?.path)
        for category in KeyCategory.allCases {
            report.loadedSamples += rawSamples(profile: profile, category: category).count
        }
        lock.lock()
        report.missing = reportedMissing.sorted()
        lock.unlock()
        return report
    }

    /// Checks every profile — used by the diagnostics row in Settings.
    public func auditAllProfiles() -> Report {
        var report = Report(rootPath: rootURL?.path)
        for profile in SoundProfile.allCases {
            for category in KeyCategory.allCases {
                report.loadedSamples += rawSamples(profile: profile, category: category).count
            }
        }
        lock.lock()
        report.missing = reportedMissing.sorted()
        lock.unlock()
        return report
    }
}
