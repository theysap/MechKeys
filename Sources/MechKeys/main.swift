import MechKeysCore

// The App protocol's entry point. The scene and every type it needs live in
// MechKeysCore so that the test target can import them; SwiftPM test targets
// cannot @testable import an executable target.
MechKeysApp.main()
