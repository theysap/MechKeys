import SwiftUI

/// A stand-in for `@State`.
///
/// In the macOS 26+ SDK, `@State` is declared as a Swift macro backed by a
/// `SwiftUIMacros` compiler plugin that ships only inside Xcode — not in the
/// Command Line Tools. MechKeys builds with either, so view-local state is
/// held in a one-value `ObservableObject` and declared with `@StateObject`,
/// which has the same lifetime and the same `$`-projected `Binding`.
///
/// ```swift
/// @StateObject private var tab = ViewState(Tab.sound)
/// TabView(selection: $tab.value) { … }
/// ```
final class ViewState<Value>: ObservableObject {
    @Published var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
