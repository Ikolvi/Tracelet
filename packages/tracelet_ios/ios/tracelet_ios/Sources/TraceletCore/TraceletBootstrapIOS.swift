import Foundation

/// Static factory registry for framework-agnostic engine boot.
///
/// Framework plugins (Flutter, React Native) register their factory closures
/// during plugin initialisation. Engines that need to construct event senders
/// or headless dispatchers (e.g., after a killed-state relaunch) call these
/// factories instead of referencing concrete framework types.
public enum TraceletBootstrapIOS {

    /// Factory that creates an event sender bound to the current framework.
    public static var eventSenderFactory: (() -> TraceletEventSending)?

    /// Factory that creates a headless dispatcher for background execution.
    public static var headlessDispatcherFactory: (() -> HeadlessDispatching)?
}
