import Foundation

/// Static factory registry for creating framework-specific implementations
/// during background restarts (significant location change, background fetch, etc.).
///
/// The host framework (Flutter plugin, React Native module) sets these
/// factories during initialization. Core engine code uses them when it
/// needs to bootstrap tracking without a live UI connection.
public enum TraceletBootstrapIOS {
    /// Factory for creating a ``TraceletEventSending`` during headless/background restart.
    /// Set by the host framework adapter during plugin initialization.
    public static var eventSenderFactory: (() -> TraceletEventSending)?

    /// Factory for creating a ``HeadlessDispatching`` during background execution.
    /// Set by the host framework adapter during plugin initialization.
    public static var headlessDispatcherFactory: (() -> HeadlessDispatching)?
}
