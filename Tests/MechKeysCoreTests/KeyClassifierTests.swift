import CoreGraphics
import Testing

@testable import MechKeysCore

@Suite("Key classification")
struct KeyClassifierTests {

    @Test("Letters, digits and punctuation are all ordinary keys")
    func standardKeys() {
        // A, S, D, F, 1, comma, Escape, left arrow.
        for keyCode: CGKeyCode in [0, 1, 2, 3, 18, 43, 53, 123] {
            #expect(KeyClassifier.category(for: keyCode) == .standard)
        }
    }

    @Test("The big keys get their own categories")
    func specialKeys() {
        #expect(KeyClassifier.category(for: 49) == .space)
        #expect(KeyClassifier.category(for: 36) == .enter)
        #expect(KeyClassifier.category(for: 51) == .backspace)
        #expect(KeyClassifier.category(for: 48) == .tab)
    }

    @Test("Keypad Enter and forward delete match their main-keyboard twins")
    func keypadAndForwardDelete() {
        #expect(KeyClassifier.category(for: 76) == .enter)
        #expect(KeyClassifier.category(for: 117) == .backspace)
    }

    @Test("Every modifier, left and right, classifies as a modifier")
    func modifiers() {
        // command, right command, shift, right shift, option, right option,
        // control, right control, caps lock, fn.
        for keyCode: CGKeyCode in [55, 54, 56, 60, 58, 61, 59, 62, 57, 63] {
            #expect(KeyClassifier.category(for: keyCode) == .modifier)
            #expect(KeyClassifier.isModifier(keyCode))
        }
    }

    @Test("The function keys that arrive as key-downs are ordinary keys")
    func functionKeysThatAreKeyDowns() {
        // F3 Mission Control, F4 Spotlight, F5 dictation, F6 Focus. These are
        // the ones macOS delivers as real key-downs; the rest of the top row
        // does not arrive this way at all — see auxKeys() below.
        for keyCode: CGKeyCode in [99, 118, 96, 97] {
            #expect(KeyClassifier.category(for: keyCode) == .standard)
        }
        // And the plain F13–F15 / F16–F20 keys on a full-size keyboard.
        for keyCode: CGKeyCode in [105, 107, 113, 106, 64, 79, 80, 90] {
            #expect(KeyClassifier.category(for: keyCode) == .standard)
        }
    }

    @Test("Brightness, media and volume keys sound like ordinary keys")
    func auxKeys() {
        // These reach the app as NX_SYSDEFINED rather than as key-downs, so
        // they have their own door into the classifier. Without it F1, F2 and
        // F7 through F12 are silent — which is exactly how they behaved.
        let expected: [Int32: String] = [
            3: "F1 brightness down", 2: "F2 brightness up",
            18: "F7 previous", 16: "F8 play", 17: "F9 next",
            7: "F10 mute", 1: "F11 volume down", 0: "F12 volume up",
        ]
        for (code, name) in expected {
            #expect(KeyClassifier.auxCategory(forAuxKeyCode: code) == .standard, "\(name)")
        }
    }

    @Test("Keys that are not a finger on a keycap stay silent")
    func auxKeysThatAreNotKeys() {
        // Caps Lock has an aux code of its own *and* arrives as a
        // flagsChanged; honouring both would sound it twice. The power key is
        // Touch ID on most Macs and is not pressed to type.
        #expect(KeyClassifier.auxCategory(forAuxKeyCode: 4) == nil)  // caps lock
        #expect(KeyClassifier.auxCategory(forAuxKeyCode: 6) == nil)  // power
        #expect(KeyClassifier.auxCategory(forAuxKeyCode: 8) == nil)  // up arrow
        #expect(KeyClassifier.auxCategory(forAuxKeyCode: 9) == nil)  // down arrow
        #expect(KeyClassifier.auxCategory(forAuxKeyCode: 99) == nil)  // not a key type
    }

    @Test("Only the press of an aux key makes a sound, not the release")
    func auxKeyPressOnly() {
        #expect(KeyClassifier.isAuxKeyPress(state: 0x0A))
        #expect(KeyClassifier.isAuxKeyPress(state: 0x0B) == false)
    }

    @Test("An unknown keycode is an ordinary key rather than nothing at all")
    func unknownKeysAreStandard() {
        // Better a plain clack from an unrecognised key than silence.
        #expect(KeyClassifier.category(for: 200) == .standard)
        #expect(KeyClassifier.isModifier(200) == false)
    }

    @Test("A key event carries no more than a category, a flag and a time")
    func eventCarriesNoKeystrokeData() {
        // The type itself is the privacy guarantee: there is nowhere in it to
        // put a keycode or a character, so nothing downstream can log one.
        let event = KeyEvent(category: .space, isRepeat: false, timestamp: 12)
        #expect(event.category == .space)
        #expect(event.isRepeat == false)
        #expect(event.timestamp == 12)
        #expect(Mirror(reflecting: event).children.count == 3)
    }
}
