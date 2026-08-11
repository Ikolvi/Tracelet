import Flutter
import Foundation
#if canImport(TraceletSDK)
import TraceletSDK
#endif

/// Manages headless Dart execution for processing events in the background.
///
/// Stores callback IDs in UserDefaults. Creates a FlutterEngine on demand
/// and invokes the registered Dart callback.
final class HeadlessRunner: HeadlessDispatching {
    enum CallbackType {
        case main
        case headers
        case syncBody
        
        var regKey: String {
            switch self {
            case .main: return "com.tracelet.headless.registrationId"
            case .headers: return "com.tracelet.headless.headlessHeaders_registrationId"
            case .syncBody: return "com.tracelet.headless.headlessSyncBody_registrationId"
            }
        }
        var dispatchKey: String {
            switch self {
            case .main: return "com.tracelet.headless.dispatchId"
            case .headers: return "com.tracelet.headless.headlessHeaders_dispatchId"
            case .syncBody: return "com.tracelet.headless.headlessSyncBody_dispatchId"
            }
        }
    }

    private static let channelName = "com.tracelet/headless"
    private static let methodsChannelName = "com.tracelet/methods"

    /// How long a spawn may take before it is declared stalled and retried
    /// (#331). Generous — a cold engine on a loaded device legitimately takes
    /// seconds. What it must not do is wait forever in silence.
    private static let engineSpawnTimeout: TimeInterval = 30

    /// Cap on events buffered while the engine comes up (#331). The queue was
    /// unbounded, so a spawn that never completed grew it for as long as
    /// tracking ran.
    private static let maxPendingEvents = 200

    /// How far a spawn attempt got, named in the stall log so one report
    /// identifies which link broke (#331).
    private enum SpawnStage: String {
        case idle = "IDLE"
        case posted = "POSTED"
        case engineCreated = "ENGINE_CREATED"
        case ready = "READY"
    }

    /// Guards every field below. `dispatchEvent` arrives on whichever thread
    /// produced the event (location, sync, heartbeat) while `onEngineReady`
    /// runs on the platform thread; the Swift Array in particular is not
    /// thread-safe and was being mutated from both (#331).
    private let stateLock = NSRecursiveLock()

    private var engine: FlutterEngine?
    private var channel: FlutterMethodChannel?
    private var isReady = false
    private var pendingEvents: [[String: Any]] = []
    private var spawnInFlight = false
    private var spawnStage: SpawnStage = .idle
    private var spawnStartedAt: TimeInterval = 0
    private var droppedEvents = 0

    /// Background task protecting engine boot + pending event flush.
    private var engineBootTaskId: UIBackgroundTaskIdentifier?

    /// ConfigManager for handling setDynamicHeaders from headless callbacks.
    var configManager: ConfigManager?

    /// Semaphore signaled when headless Dart callback calls setDynamicHeaders.
    private var headersRefreshSemaphore: DispatchSemaphore?

    /// Semaphore signaled when headless Dart callback returns custom sync body.
    private var syncBodySemaphore: DispatchSemaphore?

    /// Custom sync body JSON returned by headless Dart callback.
    private var syncBodyResponse: String?

    func registerCallbacks(type: CallbackType, _ registrationId: Int64, _ dispatchId: Int64) {
        let defaults = UserDefaults.standard
        defaults.set(registrationId, forKey: type.regKey)
        defaults.set(dispatchId, forKey: type.dispatchKey)
    }

    func isRegistered() -> Bool {
        let defaults = UserDefaults.standard
        return defaults.integer(forKey: CallbackType.main.regKey) != 0
    }

    /// Whether `registerHeadlessSyncBodyBuilder` has persisted a callback pair.
    ///
    /// Read straight from `UserDefaults` and deliberately touching nothing else
    /// (#340): it is consulted from `requestSyncBody`'s earliest branch, which
    /// must stay safe before the SDK has finished initializing.
    func isSyncBodyBuilderRegistered() -> Bool {
        let defaults = UserDefaults.standard
        return defaults.integer(forKey: CallbackType.syncBody.regKey) != 0
            && defaults.integer(forKey: CallbackType.syncBody.dispatchKey) != 0
    }

    func dispatchEvent(_ event: [String: Any]) {
        // Include the dispatch callback ID so the Dart-side dispatcher
        // can look up the user's headless callback.
        let defaults = UserDefaults.standard
        let dispatchId = defaults.integer(forKey: CallbackType.main.dispatchKey)
        var enrichedEvent = event
        enrichedEvent["dispatchId"] = dispatchId

        dispatchOrQueue(enrichedEvent, taskName: "headlessEngineBoot")
    }

    /// Tears the engine down and discards anything still queued.
    ///
    /// Only for a real teardown. A *failed spawn* must not come through here —
    /// clearing the queue there threw away the events the engine was being
    /// spawned to deliver (#331); ``resetSpawn`` keeps them for the next
    /// attempt.
    func destroy() {
        stateLock.lock()
        let abandoned = pendingEvents.count
        pendingEvents.removeAll()
        stateLock.unlock()
        if abandoned > 0 {
            TraceletLog.warning("headless: destroy() discarding \(abandoned) undelivered event(s)")
        }
        resetSpawn()
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
            TraceletSdk.shared.logger.debug("No headless headers callback registered")
            return false
        }

        let semaphore = DispatchSemaphore(value: 0)
        headersRefreshSemaphore = semaphore

        let event: [String: Any] = [
            "name": "headersRefresh",
            "event": [String: Any](),
            "dispatchId": dispatchId,
        ]

        dispatchOrQueue(event, taskName: "headlessHeadersRefresh")

        let result = semaphore.wait(timeout: .now() + timeout)
        headersRefreshSemaphore = nil

        if result == .success {
            TraceletSdk.shared.logger.debug("Headers refresh completed by headless callback")
            return true
        } else {
            TraceletSdk.shared.logger.debug("Headers refresh timed out after \(timeout)s")
            return false
        }
    }

    /// Request a custom sync body from the headless Dart callback.
    ///
    /// Dispatches a `syncBodyBuild` event to the Dart headless callback
    /// registered via `registerHeadlessSyncBodyBuilder`. The Dart callback
    /// is expected to transform the locations and call
    /// `Tracelet.setSyncBodyResponse()`, which routes back here and signals
    /// this method to return.
    ///
    /// - Parameters:
    ///   - locations: The batch of locations to include in the body.
    ///   - timeout: Maximum time to wait for the Dart callback.
    /// - Returns: The custom JSON body string, or `nil` if timed out or unavailable.
    // #214: telematics defaults to empty so existing callers/headless callbacks
    // keep working unchanged.
    func requestCustomSyncBody(_ locations: [[String: Any]], timeout: TimeInterval, telematics: [[String: Any]] = []) -> String? {
        let defaults = UserDefaults.standard
        let dispatchId = defaults.integer(forKey: "com.tracelet.headless.headlessSyncBody_dispatchId")
        let registrationId = defaults.integer(forKey: "com.tracelet.headless.headlessSyncBody_registrationId")
        guard dispatchId != 0, registrationId != 0 else {
            // No headless builder registered → sentinel so the sync provider
            // falls through to the default payload rather than aborting.
            TraceletSdk.shared.logger.debug("No headless sync body callback registered")
            return traceletNoSyncBodyBuilderSentinel
        }

        guard !Thread.isMainThread else {
            // A builder is registered but we cannot run it here → abort (nil).
            TraceletSdk.shared.logger.debug("requestCustomSyncBody must not be called on the main thread")
            return nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        syncBodySemaphore = semaphore
        syncBodyResponse = nil

        let event: [String: Any] = [
            "name": "syncBodyBuild",
            // #214: include telematics so headless custom builders can read
            // event['telematics'] (empty unless syncTelematics is enabled).
            "event": ["locations": locations, "telematics": telematics],
            "dispatchId": dispatchId,
        ]

        dispatchOrQueue(event, taskName: "headlessSyncBody")

        let result = semaphore.wait(timeout: .now() + timeout)
        let response = syncBodyResponse
        syncBodySemaphore = nil
        syncBodyResponse = nil

        if result == .success {
            TraceletSdk.shared.logger.debug("Sync body build completed by headless callback")
            return response
        } else {
            TraceletSdk.shared.logger.debug("Sync body build timed out after \(timeout)s")
            return nil
        }
    }

    // MARK: - Queueing

    /// Sends the event if the engine is live, otherwise buffers it and asks for
    /// an engine — the shared body of the three dispatch entry points.
    private func dispatchOrQueue(_ event: [String: Any], taskName: String) {
        stateLock.lock()
        let liveChannel = isReady ? channel : nil
        stateLock.unlock()

        if let liveChannel = liveChannel {
            liveChannel.invokeMethod("headlessEvent", arguments: event)
            return
        }

        enqueue(event)
        stateLock.lock()
        let needsTask = engineBootTaskId == nil
        stateLock.unlock()
        if needsTask {
            let taskId = BackgroundTaskHelper.shared.begin(taskName)
            stateLock.lock()
            engineBootTaskId = taskId
            stateLock.unlock()
        }
        startEngineIfNeeded()
    }

    /// Buffers an event for the engine that is coming up, capped at
    /// ``maxPendingEvents`` (#331). The array was unbounded, so a spawn that
    /// never completed grew it by one entry per fix for the life of the
    /// process. Oldest-first eviction keeps the freshest events, and the drop
    /// is reported rather than silent.
    private func enqueue(_ event: [String: Any]) {
        stateLock.lock()
        var dropped = 0
        while pendingEvents.count >= HeadlessRunner.maxPendingEvents {
            pendingEvents.removeFirst()
            dropped += 1
        }
        pendingEvents.append(event)
        droppedEvents += dropped
        let total = droppedEvents
        let stage = spawnStage
        stateLock.unlock()

        guard dropped > 0 else { return }
        if total == dropped {
            // Once per queue, on the always-on channel: a report showing this
            // has a headless engine that never came up.
            TraceletLog.lifecycle(
                "headless: pending-event queue hit its \(HeadlessRunner.maxPendingEvents) cap — "
                    + "dropping the oldest events while stage \(stage.rawValue)")
        }
        TraceletLog.warning("headless: queue full — dropped \(dropped) event(s) (total \(total))")
    }

    // MARK: - Engine management

    private func startEngineIfNeeded() {
        // A spawn that never finished used to leave `engine` non-null forever,
        // and this method's guard then made every later event a silent no-op.
        // Give up on it and try again instead (#331).
        failStalledSpawn()

        let defaults = UserDefaults.standard
        // Try main headless callback first, fall back to headers, then sync body
        var registrationId = defaults.integer(forKey: CallbackType.main.regKey)
        if registrationId == 0 {
            registrationId = defaults.integer(forKey: CallbackType.headers.regKey)
        }
        if registrationId == 0 {
            registrationId = defaults.integer(forKey: CallbackType.syncBody.regKey)
        }

        stateLock.lock()
        guard engine == nil, !spawnInFlight else {
            stateLock.unlock()
            return
        }
        guard registrationId != 0 else {
            let abandoned = pendingEvents.count
            pendingEvents.removeAll()
            stateLock.unlock()
            TraceletLog.warning(
                "headless: no callbacks registered — dropping \(abandoned) queued event(s)")
            return
        }
        spawnInFlight = true
        spawnStage = .posted
        spawnStartedAt = ProcessInfo.processInfo.systemUptime
        let queued = pendingEvents.count
        stateLock.unlock()

        // The anchor for every "headless never fired" report: it says a spawn
        // was asked for. Its absence means routing never reached this runner;
        // its presence without a matching `engine ready` names the stall (#331).
        TraceletLog.lifecycle("headless: spawning a FlutterEngine (\(queued) event(s) queued)")

        // FlutterEngine must be created and run on the main thread. This used
        // to run on whichever thread produced the event — a location callback
        // queue, or the sync thread blocked on a semaphore (#331).
        if Thread.isMainThread {
            spawnEngine(registrationId: registrationId)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.spawnEngine(registrationId: registrationId)
            }
        }
    }

    private func spawnEngine(registrationId: Int) {
        guard let callback = FlutterCallbackCache.lookupCallbackInformation(Int64(registrationId)) else {
            // Nothing can ever consume these events: the callback the engine
            // exists to run is gone from the app bundle.
            TraceletLog.lifecycle(
                "headless: no callback info for ID \(registrationId) — "
                    + "the registered Dart entrypoint is gone from this build")
            destroy()
            return
        }

        let newEngine = FlutterEngine(
            name: "com.tracelet.headless", project: nil, allowHeadlessExecution: true)
        let success = newEngine.run(
            withEntrypoint: callback.callbackName,
            libraryURI: callback.callbackLibraryPath
        )

        guard success else {
            TraceletLog.lifecycle(
                "headless: engine spawn FAILED at stage \(currentStage()) — "
                    + "FlutterEngine.run returned false for \(callback.callbackName ?? "?")")
            // resetSpawn, not destroy: the queued events are what the engine
            // was being spawned to deliver. Keep them for the next attempt.
            resetSpawn()
            return
        }

        // Set up method channel for bidirectional communication
        let newChannel = FlutterMethodChannel(
            name: HeadlessRunner.channelName,
            binaryMessenger: newEngine.binaryMessenger
        )

        newChannel.setMethodCallHandler { [weak self] call, result in
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
            binaryMessenger: newEngine.binaryMessenger
        )
        methodsChannel.setMethodCallHandler { [weak self] call, result in
            if call.method == "setDynamicHeaders" {
                let headers = (call.arguments as? [String: Any])?
                    .mapValues { "\($0)" } ?? [:]
                self?.configManager?.setDynamicHeaders(headers)
                self?.headersRefreshSemaphore?.signal()
                result(true)
            } else if call.method == "setSyncBodyResponse" {
                self?.syncBodyResponse = call.arguments as? String
                self?.syncBodySemaphore?.signal()
                result(true)
            } else {
                result(FlutterMethodNotImplemented)
            }
        }

        // Published only once the engine is fully wired, so a failure above
        // cannot leave a half-built engine behind for the guard in
        // startEngineIfNeeded() to trust (#331).
        stateLock.lock()
        engine = newEngine
        channel = newChannel
        spawnStage = .engineCreated
        stateLock.unlock()
    }

    private func onEngineReady() {
        stateLock.lock()
        isReady = true
        spawnInFlight = false
        spawnStage = .ready
        let events = pendingEvents
        pendingEvents.removeAll()
        let liveChannel = channel
        let taskId = engineBootTaskId
        engineBootTaskId = nil
        stateLock.unlock()

        TraceletLog.lifecycle("headless: engine ready — draining \(events.count) queued event(s)")

        for event in events {
            liveChannel?.invokeMethod("headlessEvent", arguments: event)
        }

        // Engine is up and events are dispatched — end the boot task.
        BackgroundTaskHelper.shared.end(taskId)
    }

    /// Abandons an in-flight spawn that has outlived ``engineSpawnTimeout`` so
    /// the next event can start a fresh one (#331).
    ///
    /// The reported failure was permanent: no timeout, retry, or log ever
    /// followed a spawn that did not complete, and events accumulated for as
    /// long as tracking ran. The stage recorded here is the diagnostic — it
    /// names how far the attempt got.
    private func failStalledSpawn() {
        stateLock.lock()
        guard spawnInFlight, !isReady, spawnStartedAt > 0 else {
            stateLock.unlock()
            return
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - spawnStartedAt
        guard elapsed >= HeadlessRunner.engineSpawnTimeout else {
            stateLock.unlock()
            return
        }
        let stage = spawnStage
        let queued = pendingEvents.count
        stateLock.unlock()

        TraceletLog.lifecycle(
            "headless: engine spawn STALLED at stage \(stage.rawValue) after "
                + "\(Int(elapsed * 1000))ms — retrying (\(queued) event(s) queued)")
        resetSpawn()
    }

    /// Returns to a spawnable state, keeping ``pendingEvents`` intact. Unlike
    /// ``destroy`` this is recoverable: the next dispatched event starts a new
    /// spawn and drains everything buffered in the meantime.
    private func resetSpawn() {
        stateLock.lock()
        let oldEngine = engine
        engine = nil
        channel = nil
        isReady = false
        spawnInFlight = false
        spawnStage = .idle
        spawnStartedAt = 0
        let taskId = engineBootTaskId
        engineBootTaskId = nil
        stateLock.unlock()

        BackgroundTaskHelper.shared.end(taskId)

        guard let oldEngine = oldEngine else { return }
        if Thread.isMainThread {
            oldEngine.destroyContext()
        } else {
            DispatchQueue.main.async { oldEngine.destroyContext() }
        }
    }

    private func currentStage() -> String {
        stateLock.lock()
        defer { stateLock.unlock() }
        return spawnStage.rawValue
    }
}
