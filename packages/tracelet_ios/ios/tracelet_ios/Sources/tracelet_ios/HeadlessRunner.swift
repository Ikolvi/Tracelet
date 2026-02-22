import Flutter
import Foundation

/// Manages headless Dart execution for processing events in the background.
///
/// Stores callback IDs in UserDefaults. Creates a FlutterEngine on demand
/// and invokes the registered Dart callback.
final class HeadlessRunner {
    private static let registrationKey = "com.tracelet.headless.registrationId"
    private static let dispatchKey = "com.tracelet.headless.dispatchId"
    private static let channelName = "com.tracelet/headless"

    private var engine: FlutterEngine?
    private var channel: FlutterMethodChannel?
    private var isReady = false
    private var pendingEvents: [[String: Any]] = []

    func registerCallbacks(_ registrationId: Int64, _ dispatchId: Int64) {
        let defaults = UserDefaults.standard
        defaults.set(registrationId, forKey: HeadlessRunner.registrationKey)
        defaults.set(dispatchId, forKey: HeadlessRunner.dispatchKey)
    }

    func dispatchEvent(_ event: [String: Any]) {
        // Include the dispatch callback ID so the Dart-side dispatcher
        // can look up the user's headless callback.
        let defaults = UserDefaults.standard
        let dispatchId = defaults.integer(forKey: HeadlessRunner.dispatchKey)
        var enrichedEvent = event
        enrichedEvent["dispatchId"] = dispatchId

        if isReady, let channel = channel {
            channel.invokeMethod("headlessEvent", arguments: enrichedEvent)
        } else {
            pendingEvents.append(enrichedEvent)
            startEngineIfNeeded()
        }
    }

    func destroy() {
        engine?.destroyContext()
        engine = nil
        channel = nil
        isReady = false
        pendingEvents.removeAll()
    }

    // MARK: - Engine management

    private func startEngineIfNeeded() {
        guard engine == nil else { return }

        let defaults = UserDefaults.standard
        let registrationId = defaults.integer(forKey: HeadlessRunner.registrationKey)
        guard registrationId != 0 else {
            NSLog("[Tracelet] No headless callback registered")
            return
        }

        guard let callback = FlutterCallbackCache.lookupCallbackInformation(Int64(registrationId)) else {
            NSLog("[Tracelet] Failed to find callback for registration ID: \(registrationId)")
            return
        }

        engine = FlutterEngine(name: "com.tracelet.headless", project: nil, allowHeadlessExecution: true)
        guard let engine = engine else { return }

        let success = engine.run(
            withEntrypoint: callback.callbackName,
            libraryURI: callback.callbackLibraryPath
        )

        guard success else {
            NSLog("[Tracelet] Failed to start headless engine")
            self.engine = nil
            return
        }

        // Set up method channel for bidirectional communication
        channel = FlutterMethodChannel(
            name: HeadlessRunner.channelName,
            binaryMessenger: engine.binaryMessenger
        )

        channel?.setMethodCallHandler { [weak self] call, result in
            if call.method == "initialized" {
                self?.onEngineReady()
                result(nil)
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func onEngineReady() {
        isReady = true
        // Flush pending events
        for event in pendingEvents {
            channel?.invokeMethod("headlessEvent", arguments: event)
        }
        pendingEvents.removeAll()
    }
}
