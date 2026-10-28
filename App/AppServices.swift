import Observation

/// Long-lived objects shared by all screens.
@MainActor
@Observable
final class AppServices {
    /// One motion manager for the whole app, as Apple recommends.
    let motion = MotionInput()
}
