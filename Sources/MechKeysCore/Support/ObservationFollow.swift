import Observation

/// Runs `body` now, and again every time any observable property it read
/// changes.
///
/// `withObservationTracking` fires its change handler once and then stops, so
/// following a value continuously means re-arming it each time. This wraps
/// that loop up for the parts of the app that live outside SwiftUI and still
/// need to react to `@Observable` state — here, the audio engine and the
/// keyboard monitor reacting to a settings change.
@MainActor
func follow(_ body: @escaping @MainActor () -> Void) {
    withObservationTracking {
        body()
    } onChange: {
        // The handler runs before the value has actually changed, so the next
        // read has to happen afterwards.
        Task { @MainActor in
            follow(body)
        }
    }
}
