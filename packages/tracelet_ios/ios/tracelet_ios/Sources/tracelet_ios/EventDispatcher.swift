import Flutter
import Foundation

/// Manages all 15 EventChannels, registering stream handlers and dispatching
/// events to Dart on the main thread.
///
/// When no Dart UI listener is attached for a given event, the dispatcher
/// falls back to `headlessFallback` (if set) so that events can be routed
/// to a background Dart isolate via HeadlessRunner.
final class EventDispatcher: NSObject {
    private var sinks: [String: FlutterEventSink] = [:]
    private var channels: [FlutterEventChannel] = []

    /// Optional headless fallback. When no EventSink exists for a given event,
    /// the dispatcher calls this closure so the event can be forwarded to
    /// HeadlessRunner.
    var headlessFallback: ((_ eventName: String, _ data: [String: Any]) -> Void)?

    /// All event channel paths (must match Dart TraceletEvents constants).
    static let channelPaths: [String] = [
        "com.tracelet/events/location",
        "com.tracelet/events/motionchange",
        "com.tracelet/events/activitychange",
        "com.tracelet/events/providerchange",
        "com.tracelet/events/geofence",
        "com.tracelet/events/geofenceschange",
        "com.tracelet/events/heartbeat",
        "com.tracelet/events/http",
        "com.tracelet/events/schedule",
        "com.tracelet/events/powersavechange",
        "com.tracelet/events/connectivitychange",
        "com.tracelet/events/enabledchange",
        "com.tracelet/events/notificationaction",
        "com.tracelet/events/authorization",
        "com.tracelet/events/watchposition",
    ]

    func register(messenger: FlutterBinaryMessenger) {
        for path in EventDispatcher.channelPaths {
            let channel = FlutterEventChannel(name: path, binaryMessenger: messenger)
            channel.setStreamHandler(StreamHandler(path: path, dispatcher: self))
            channels.append(channel)
        }
    }

    func unregister() {
        for channel in channels {
            channel.setStreamHandler(nil)
        }
        channels.removeAll()
        sinks.removeAll()
    }

    // MARK: - Typed senders

    func sendLocation(_ data: [String: Any]) {
        send("com.tracelet/events/location", data: data)
    }

    func sendMotionChange(_ data: [String: Any]) {
        send("com.tracelet/events/motionchange", data: data)
    }

    func sendActivityChange(_ data: [String: Any]) {
        send("com.tracelet/events/activitychange", data: data)
    }

    func sendProviderChange(_ data: [String: Any]) {
        send("com.tracelet/events/providerchange", data: data)
    }

    func sendGeofence(_ data: [String: Any]) {
        send("com.tracelet/events/geofence", data: data)
    }

    func sendGeofencesChange(_ data: [String: Any]) {
        send("com.tracelet/events/geofenceschange", data: data)
    }

    func sendHeartbeat(_ data: [String: Any]) {
        send("com.tracelet/events/heartbeat", data: data)
    }

    func sendHttp(_ data: [String: Any]) {
        send("com.tracelet/events/http", data: data)
    }

    func sendSchedule(_ data: [String: Any]) {
        send("com.tracelet/events/schedule", data: data)
    }

    func sendPowerSaveChange(_ isPowerSave: Bool) {
        send("com.tracelet/events/powersavechange", data: isPowerSave)
    }

    func sendConnectivityChange(_ data: [String: Any]) {
        send("com.tracelet/events/connectivitychange", data: data)
    }

    func sendEnabledChange(_ enabled: Bool) {
        send("com.tracelet/events/enabledchange", data: enabled)
    }

    func sendNotificationAction(_ data: [String: Any]) {
        send("com.tracelet/events/notificationaction", data: data)
    }

    func sendAuthorization(_ data: [String: Any]) {
        send("com.tracelet/events/authorization", data: data)
    }

    func sendWatchPosition(_ data: [String: Any]) {
        send("com.tracelet/events/watchposition", data: data)
    }

    // MARK: - Core dispatch

    private func send(_ path: String, data: Any) {
        DispatchQueue.main.async { [weak self] in
            if let sink = self?.sinks[path] {
                sink(data)
            } else {
                // No Dart UI listener — route to headless fallback.
                guard let fallback = self?.headlessFallback else { return }
                // Extract the short event name from the full path
                // e.g. "com.tracelet/events/location" → "location"
                let eventName = path.components(separatedBy: "/").last ?? path
                let eventData: [String: Any]
                if let mapData = data as? [String: Any] {
                    eventData = mapData
                } else {
                    eventData = ["value": data]
                }
                fallback(eventName, eventData)
            }
        }
    }

    // MARK: - Stream handler

    fileprivate func setSink(_ path: String, sink: FlutterEventSink?) {
        sinks[path] = sink
    }

    /// Internal stream handler that routes listen/cancel to the dispatcher.
    private class StreamHandler: NSObject, FlutterStreamHandler {
        let path: String
        weak var dispatcher: EventDispatcher?

        init(path: String, dispatcher: EventDispatcher) {
            self.path = path
            self.dispatcher = dispatcher
        }

        func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
            dispatcher?.setSink(path, sink: events)
            return nil
        }

        func onCancel(withArguments arguments: Any?) -> FlutterError? {
            dispatcher?.setSink(path, sink: nil)
            return nil
        }
    }
}
