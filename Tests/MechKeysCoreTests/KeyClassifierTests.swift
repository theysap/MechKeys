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
