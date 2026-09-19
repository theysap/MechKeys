import Foundation

/// The audio system, as the rest of the app sees it.
///
/// Keeping this behind a protocol means the keyboard layer can be tested with
/// a recording double, and no test needs a speaker.
public protocol SoundEngine: AnyObject {
    var isRunning: Bool { get }

    func start() throws
    func stop()

    /// Plays one keypress. Must return immediately and must never block the
    /// caller — it is called from the event path.
    func play(keyCategory: KeyCategory, profile: SoundProfile)

    func setVolume(_ volume: Float)
    func setDampening(_ value: Float)

    /// Applies the full settings snapshot: profile, DSP, variation, voices.
    func apply(_ settings: AppSettings)
}

/// Why the engine could not start, in terms a person can act on.
public enum SoundEngineError: LocalizedError, Equatable {
    case libraryUnavailable(String)
    case outputUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .libraryUnavailable:
            return "MechKeys could not load its sound library."
        case .outputUnavailable:
            return "MechKeys could not open an audio output device."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .libraryUnavailable(let detail):
            return "The bundled samples are missing or unreadable. \(detail)"
        case .outputUnavailable(let detail):
            return "Check that an output device is available in Sound settings. \(detail)"
        }
    }
}

/// A no-op engine used by previews and by unit tests, which records what it
/// was asked to play instead of playing it.
public final class RecordingSoundEngine: SoundEngine {
    public private(set) var isRunning = false
    public private(set) var played: [(category: KeyCategory, profile: SoundProfile)] = []
    public private(set) var volume: Float = 0
    public private(set) var dampening: Float = 0
    public private(set) var appliedSettings: AppSettings?
    public var startError: Error?

    public init() {}

    public func start() throws {
        if let startError { throw startError }
        isRunning = true
    }

    public func stop() { isRunning = false }

    public func play(keyCategory: KeyCategory, profile: SoundProfile) {
        played.append((keyCategory, profile))
    }

    public func setVolume(_ volume: Float) { self.volume = volume }
    public func setDampening(_ value: Float) { dampening = value }
    public func apply(_ settings: AppSettings) { appliedSettings = settings }

    public func reset() { played.removeAll() }
}
