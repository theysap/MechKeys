import CoreGraphics
import Foundation

/// A keypress, reduced to the only three things the audio side is allowed to
/// know: how big the key was, whether it came from autorepeat, and when.
///
/// The character, the keycode and the frontmost application are deliberately
/// *not* carried here. Classification happens inside the event callback and
/// only this value escapes it.
public struct KeyEvent: Equatable, Sendable {
    public let category: KeyCategory
    public let isRepeat: Bool
    public let timestamp: TimeInterval

    public init(
        category: KeyCategory, isRepeat: Bool,
        timestamp: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) {
        self.category = category
        self.isRepeat = isRepeat
        self.timestamp = timestamp
    }
}

/// Maps a macOS virtual keycode to an acoustic category.
///
/// The numbers are the classic Carbon `kVK_*` constants from
/// `HIToolbox/Events.h`. They are layout-independent — keycode 49 is the
/// spacebar on a QWERTY, AZERTY or Dvorak Mac — which is exactly what we want,
/// because we are classifying the *physical key*, not the character it types.
public enum KeyClassifier {

    // Large / special keys.
    static let space: CGKeyCode = 49
    static let `return`: CGKeyCode = 36
    static let keypadEnter: CGKeyCode = 76
    static let delete: CGKeyCode = 51
    static let forwardDelete: CGKeyCode = 117
    static let tab: CGKeyCode = 48

    /// Keys that only ever appear as `flagsChanged` events.
    static let modifierKeyCodes: Set<CGKeyCode> = [
        54,  // right command
        55,  // command
        56,  // shift
        57,  // caps lock
        58,  // option
        59,  // control
        60,  // right shift
        61,  // right option
        62,  // right control
        63,  // fn
    ]

    public static func category(for keyCode: CGKeyCode) -> KeyCategory {
        switch keyCode {
        case space:
            return .space
        case `return`, keypadEnter:
            return .enter
        case delete, forwardDelete:
            return .backspace
        case tab:
            return .tab
        case _ where modifierKeyCodes.contains(keyCode):
            return .modifier
        default:
            return .standard
        }
    }

    public static func isModifier(_ keyCode: CGKeyCode) -> Bool {
        modifierKeyCodes.contains(keyCode)
    }

    // MARK: - The keys that are not key-downs

    /// `NX_SYSDEFINED`.
    ///
    /// On an Apple keyboard the brightness, media-transport and volume keys —
    /// F1, F2 and F7 through F12 — are not key-downs at all. The hardware
    /// reports them as system-defined events, so a tap that asks only for
    /// `keyDown` never sees them and they make no sound, while F3 to F6
    /// (Mission Control, Spotlight, Dictation, Focus) arrive as ordinary
    /// key-downs and do.
    ///
    /// `CGEventType` has no case for 14, because a system-defined event is
    /// not a Quartz event in the way a key-down is. The tap delivers it all
    /// the same, if the mask asks for it.
    public static let systemDefinedEventType: UInt32 = 14

    /// `NX_SUBTYPE_AUX_CONTROL_BUTTONS`: the one system-defined subtype that
    /// means a key was pressed. Everything else on that channel is not a key.
    public static let auxControlSubtype: Int16 = 8

    /// `NX_KEYTYPE_*` from `IOKit/hidsystem/ev_keymap.h`, for the aux keys
    /// that are a physical key under a finger.
    ///
    /// Caps Lock is deliberately absent: it has a code here *and* arrives as
    /// a `flagsChanged`, so honouring both would sound it twice. So is the
    /// power key, which on most Macs is Touch ID and is not pressed to type.
    static let audibleAuxKeyCodes: Set<Int32> = [
        0,  // sound up          F12
        1,  // sound down        F11
        2,  // brightness up     F2
        3,  // brightness down   F1
        7,  // mute              F10
        11,  // contrast up
        12,  // contrast down
        13,  // launch panel
        14,  // eject
        16,  // play/pause       F8
        17,  // next             F9
        18,  // previous         F7
        19,  // fast forward
        20,  // rewind
        21,  // illumination up
        22,  // illumination down
        23,  // illumination toggle
    ]

    /// The category for an aux key, or nil for one that should stay silent.
    ///
    /// These are ordinary-sized keys in the top row, so they draw from the
    /// ordinary pool. The sample library has no recording of its own for
    /// them — the upstream packs carry four recordings in total, of an
    /// ordinary key, the spacebar, Return and Delete — so there is nothing
    /// more specific to reach for. See `assets/LICENSES.md`.
    public static func auxCategory(forAuxKeyCode code: Int32) -> KeyCategory? {
        audibleAuxKeyCodes.contains(code) ? .standard : nil
    }

    /// Whether a decoded aux key is being pressed rather than released.
    /// `0x0A` is down, `0x0B` is up.
    public static func isAuxKeyPress(state: Int) -> Bool { state == 0x0A }
}
