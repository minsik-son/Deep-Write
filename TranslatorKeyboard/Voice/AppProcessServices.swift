import Foundation

/// Process-level service container.
/// Owned by AppDelegate — survives scene lifecycle events.
final class AppProcessServices {
    let dictationRuntime = AppDictationRuntime()
}
