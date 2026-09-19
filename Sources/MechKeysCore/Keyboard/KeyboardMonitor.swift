import CoreGraphics
import Foundation

/// Watches for key-down events system-wide.
///
/// ## What this does and does not do
///
/// The tap is created `.listenOnly`, which means macOS will not let it modify
/// or swallow events even if it tried to. Inside the callback the keycode is
/// turned into a `KeyCategory` — one of six values — and the keycode itself
/// goes out of scope. Nothing is stored, buffered, written to disk or sent
/// anywhere. There is no keystroke history in this process, by construction.
///
/// The callback is also the latency budget for the whole app, so it does the
/// smallest possible amount of work: classify, check two rate limits, hand a
/// six-case enum to the audio queue, return.
/// Every mutable member is guarded by `lock`, which is what makes the
/// unchecked conformance sound. The compiler cannot see that invariant, and
/// the Core Foundation types involved — `CFMachPort`, `CFRunLoop` — predate
/// `Sendable` entirely.
public final class KeyboardMonitor: @unchecked Sendable {

    /// Called for every keypress that survives filtering. Invoked on the
    /// monitor's own thread — never block in here.
    public var onKeyEvent: ((KeyEvent) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var thread: Thread?
    private var threadRunLoop: CFRunLoop?

    /// Guards the few values the callback reads. Uncontended, so effectively
    /// free; it exists because settings are written from the main thread.
    private let lock = NSLock()
    private var repeatMode: KeyRepeatMode = AppSettings.default.keyRepeatMode
    private var minimumInterval: Double = AppSettings.default.minimumKeyInterval
    private var playModifiers: Bool = AppSettings.default.playModifierSounds

    /// Per-category time of the last sound, on the monotonic clock.
    private var lastSoundAt: Double = 0
    private var running = false

    public init() {}

    deinit {
        stop()
    }

    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }

    // MARK: - Settings

    public func update(from settings: AppSettings) {
        lock.lock()
        repeatMode = settings.keyRepeatMode
        minimumInterval = settings.minimumKeyInterval
        playModifiers = settings.playModifierSounds
        lock.unlock()
    }

    // MARK: - Lifecycle

    /// Starts the tap. Returns false if Accessibility permission is missing,
    /// which is the only expected failure.
    @discardableResult
    public func start() -> Bool {
        guard !isRunning else { return true }
        guard PermissionManager.currentStatus() else {
            AppLog.keyboard.info("Not starting: Accessibility permission has not been granted.")
            return false
        }

        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                // Listen-only: the tap is physically incapable of altering or
                // dropping the user's keystrokes.
                options: .listenOnly,
                eventsOfInterest: CGEventMask(mask),
                callback: keyboardMonitorCallback,
                userInfo: context
            )
        else {
            AppLog.keyboard.error("CGEvent.tapCreate failed.")
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            AppLog.keyboard.error("Could not create a run loop source for the event tap.")
            return false
        }

        eventTap = tap
        runLoopSource = source

        lock.lock(); running = true; lock.unlock()

        // The tap runs on its own thread with its own run loop. Servicing it
        // from the main run loop would put every keystroke behind whatever
        // SwiftUI happens to be doing.
        // The tap and its run loop source are carried across to the new
        // thread in a box: both are Core Foundation types from before
        // `Sendable` existed, and this is the one hand-off.
        let tapContext = TapContext(tap: tap, source: source)
        let thread = Thread { [weak self] in
            guard let self else { return }
            self.threadRunLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), tapContext.source, .commonModes)
            CGEvent.tapEnable(tap: tapContext.tap, enable: true)
            while self.isRunning {
                CFRunLoopRunInMode(.defaultMode, 0.25, false)
            }
        }
        thread.name = "com.mechkeys.keyboard"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.thread = thread

        AppLog.keyboard.info("Keyboard monitor started.")
        return true
    }

    public func stop() {
        lock.lock()
        guard running else { lock.unlock(); return }
        running = false
        lock.unlock()

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource, let threadRunLoop {
            CFRunLoopRemoveSource(threadRunLoop, runLoopSource, .commonModes)
            CFRunLoopStop(threadRunLoop)
        }
        eventTap = nil
        runLoopSource = nil
        threadRunLoop = nil
        thread = nil
        AppLog.keyboard.info("Keyboard monitor stopped.")
    }

    /// macOS disables a tap that takes too long to respond, or during a secure
    /// input session. Re-enabling is the documented recovery.
    fileprivate func reenableTap() {
        guard let eventTap else { return }
        AppLog.keyboard.warning("Event tap was disabled by the system; re-enabling.")
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    // MARK: - Event handling

    /// The hot path. Everything here is O(1) and allocation-free.
    fileprivate func handle(type: CGEventType, event: CGEvent) {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let category = KeyClassifier.category(for: keyCode)

        var isRepeat = false

        if type == .flagsChanged {
            // A modifier produces one event on press and one on release. Only
            // the press should make a sound.
            guard isModifierPress(keyCode: keyCode, flags: event.flags) else { return }
        } else {
            isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        }

        lock.lock()
        let mode = repeatMode
        let interval = minimumInterval
        let modifiersAudible = playModifiers
        lock.unlock()

        if category == .modifier && !modifiersAudible { return }

        if isRepeat && mode == .silent { return }

        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000

        // Two separate guards. `everyRepeat` deliberately skips the floor so a
        // held key really does machine-gun; everything else is protected from
        // an autorepeat storm flooding the voice pool.
        if !(isRepeat && mode == .everyRepeat) {
            lock.lock()
            let elapsed = now - lastSoundAt
            if elapsed < interval {
                lock.unlock()
                return
            }
            lastSoundAt = now
            lock.unlock()
        }

        // Hand off a six-case enum. The keycode does not leave this function.
        onKeyEvent?(KeyEvent(category: category, isRepeat: isRepeat, timestamp: now))
    }

    private func isModifierPress(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        switch keyCode {
        case 56, 60: return flags.contains(.maskShift)
        case 59, 62: return flags.contains(.maskControl)
        case 58, 61: return flags.contains(.maskAlternate)
        case 55, 54: return flags.contains(.maskCommand)
        // Caps Lock latches rather than holds, so both the on and the off
        // press are real presses of a real key.
        case 57: return true
        case 63: return flags.contains(.maskSecondaryFn)
        default: return false
        }
    }
}

/// Carries the tap across the thread boundary once, at start-up.
private struct TapContext: @unchecked Sendable {
    let tap: CFMachPort
    let source: CFRunLoopSource
}

/// C callback for the event tap. Kept free of Swift runtime work.
private func keyboardMonitorCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        monitor.reenableTap()
    case .keyDown, .flagsChanged:
        monitor.handle(type: type, event: event)
    default:
        break
    }

    // The event is passed straight through, unmodified, always.
    return Unmanaged.passUnretained(event)
}
