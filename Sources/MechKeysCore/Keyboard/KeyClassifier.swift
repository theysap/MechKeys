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
}
