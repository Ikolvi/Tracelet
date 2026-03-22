import Flutter
import Foundation

/// Manages headless Dart execution for processing events in the background.
///
/// Stores callback IDs in UserDefaults. Creates a FlutterEngine on demand
/// and invokes the registered Dart callback.
final class HeadlessRunner: HeadlessDispatching {
    private static let registrationKey = "com.tracelet.headless.registrationId"
    private static let dispatchKey = "com.tracelet.headless.dispatchId"
    private static let channelName = "com.tracelet/headless"
    private static let methodsChannelName = "com.tracelet/methods"

    private var engine: FlutterEngine?
    private var channel: FlutterMethodChannel?
    private var isReady = false
    private var pendingEvents: [[String: Any]] = []

    /// Background task protecting engine boot + pending event flush.
    private var engineBootTaskId: UIBackgroundTaskIdentifier?

    /// ConfigManager for handling setDynamicHeaders from headless callbacks.
    var configManager: ConfigManager?

    /// Semaphore signaled when headless Dart callback calls setDynamicHeaders.
    private var headersRefreshSemaphore: DispatchSemaphore?

    func registerCallbacks(_ registrationId: Int64, _ dispatchId: Int64) {
        let defaults = UserDefaults.standard
        defaults.set(registrationId, forKey: HeadlessRunner.registrationKey)
        defaults.set(dispatchId, forKey: HeadlessRunner.dispatchKey)
    }

    func isRegistered() -> Bool {
        let defaults = UserDefaults.standard
        return defaults.integer(forKey: HeadlessRunner.registrationKey) != 0
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
            // Request background time to complete engine boot + event flush.
            if engineBootTaskId == nil {
                engineBootTaskId = BackgroundTaskHelper.shared.begin("headlessEngineBoot")
            }
            startEngineIfNeeded()
        }
    }

    func destroy() {
        engine?.destroyContext()
        engine = nil
        channel = nil
        isReady = false
        pendingEvents.removeAll()
        BackgroundTaskHelper.shared.end(engineBootTaskId)
        engineBootTaskId = nil
    }

    /// Request a headers refresh from the headless Dart callback.
    ///
    /// Dispatches a `headersRefresh` event to the Dart headless callback
    /// registered via `registerHeadlessHeadersCallback`. The Dart callback
    /// is expected to refresh the token and call `Tracelet.setDynamicHeaders()`,
    /// which routes back here and signals this method to return.
    ///
    /// - Parameter timeout: Maximum time to wait for the Dart callback.
    /// - Returns: `true` if headers were refreshed within timeout.
    func requestHeadersRefresh(timeout: TimeInterval) -> Bool {
        let defaults = UserDefaults.standard
        let dispatchId = defaults.integer(forKey: "com.tracelet.headless.headlessHeaders_dispatchId")
        let registrationId = defaults.integer(forKey: "com.tracelet.headless.headlessHeaders_registrationId")
        guard dispatchId != 0, registrationId != 0 else {
            NSLog("[Tracelet] No headless headers callback registered")
            return false
        }

        let semaphore = DispatchSemaphore(value: 0)
        headersRefreshSemaphore = semaphore

        let event: [String: Any] = [
            "name": "headersRefresh",
            "event": [String: Any](),
            "dispatchId": dispatchId,
        ]

        if isReady, let channel = channel {
            channel.invokeMethod("headlessEvent", arguments: event)
        } else {
            pendingEvents.append(event)
            if engineBootTaskId == nil {
                engineBootTaskId = BackgroundTaskHelper.shared.begin("headlessHeadersRefresh")
            }
            startEngineIfNeeded()
        }

        let result = semaphore.wait(timeout: .now() + timeout)
        headersRefreshSemaphore = nil

        if result == .success {
            NSLog("[Tracelet] Headers refresh completed by headless callback")
            return true
        } else {
            NSLog("[Tracelet] Headers refresh timed out after \(timeout)s")
            return false
        }
    }

    // MARK: - Engine management

    private func startEngineIfNeeded() {
        guard engine == nil else { return }

        let defaults = UserDefaults.standard
        // Try main headless callback first, fall back to headlessHeaders callback
        var registrationId = defaults.integer(forKey: HeadlessRunner.registrationKey)
        if registrationId == 0 {
            registrationId = defaults.integer(forKey: "com.tracelet.headless.headlessHeaders_registrationId")
        }
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

        // Handle setDynamicHeaders from headless Dart callback.
        // When the Dart headless callback calls Tracelet.setDynamicHeaders(),
        // it goes through com.tracelet/methods. We handle it here so the
        // headless engine can update headers and signal the refresh semaphore.
        let methodsChannel = FlutterMethodChannel(
            name: HeadlessRunner.methodsChannelName,
            binaryMessenger: engine.binaryMessenger
        )
        methodsChannel.setMethodCallHandler { [weak self] call, result in
            if call.method == "setDynamicHeaders" {
                let headers = (call.arguments as? [String: Any])?
                    .mapValues { "\($0)" } ?? [:]
                self?.configManager?.setDynamicHeaders(headers)
                self?.headersRefreshSemaphore?.signal()
                result(true)
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

        // Engine is up and events are dispatched — end the boot task.
        BackgroundTaskHelper.shared.end(engineBootTaskId)
        engineBootTaskId = nil
    }
}
