import Foundation

/// Abstraction for dispatching events to a headless execution context
/// (e.g., Flutter background Dart isolate, React Native headless JS task).
///
/// Framework-specific implementations register themselves via
/// `TraceletBootstrapIOS.headlessDispatcherFactory`.
public protocol HeadlessDispatching: AnyObject {

    /// Whether the host framework has registered a headless callback.
    func isRegistered() -> Bool

    /// Dispatch an event to the headless context.
    func dispatchEvent(_ event: [String: Any])

    /// Tear down the headless runtime.
    func destroy()
}
