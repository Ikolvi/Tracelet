import Foundation

/// Abstraction for dispatching events to a headless runtime (background Dart
/// isolate, React Native HeadlessJsTaskService, etc.).
///
/// The host framework provides a concrete implementation via
/// ``TraceletBootstrapIOS/headlessDispatcherFactory``.
public protocol HeadlessDispatching: AnyObject {
    /// Returns true if a headless callback has been registered.
    func isRegistered() -> Bool

    /// Dispatches an event to the headless runtime.
    func dispatchEvent(_ event: [String: Any])

    /// Tears down the headless runtime.
    func destroy()
}
