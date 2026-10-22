import Flutter
import UIKit
import TraceletSDK

actor SyncCoordinator {
    private var syncTask: Task<Void, Never>?
    /// Set by every request and re-checked before a drain finishes, so a fix
    /// stored while a sync is in flight is never dropped (#437).
    private var requested = false

    /// Batches per run before yielding; the run then continues (#437).
    static let maxBatchesPerRun = 50

    /// Asks for a drain after the configured `autoSyncDelay` (#437).
    ///
    /// This used to return when a task already existed, and that task covered
    /// the debounce *and* the upload; and each run uploaded one batch. So a fix
    /// stored during a sync scheduled nothing, the queue shrank by at most one
    /// batch per later fix, and with `maxBatchSize: 1` it never shrank. Now a
    /// request made at any moment is picked up before the run ends, and each
    /// run drains until a batch comes back empty or fails.
    func scheduleSync(sink: TraceletSyncSink, delayMs: Int? = nil) {
        requested = true
        if syncTask != nil { return }
        let delay = delayMs ?? Int(TraceletSdk.shared.rustEngineState?.getConfig().http.autoSyncDelay ?? 10000)
        let delayNanos = UInt64(max(0, delay)) * 1_000_000

        syncTask = Task {
            while !Task.isCancelled {
                // Background time per run: without it iOS suspends the app as
                // soon as the location event returns and the sync never fires.
                let bgTaskId = BackgroundTaskHelper.shared.begin("tracelet_sync_task")
                try? await Task.sleep(nanoseconds: delayNanos)
                if Task.isCancelled {
                    BackgroundTaskHelper.shared.end(bgTaskId)
                    break
                }
                self.requested = false
                await self.drain(sink: sink)
                BackgroundTaskHelper.shared.end(bgTaskId)
                if !self.requested { break }
            }
            self.syncTask = nil
        }
    }

    /// Cancel the in-flight debounce so stop() halts background sync immediately (#213).
    func cancel() {
        syncTask?.cancel()
        syncTask = nil
        requested = false
    }

    private func drain(sink: TraceletSyncSink) async {
        var batches = 0
        while batches < Self.maxBatchesPerRun {
            if Task.isCancelled { return }
            if await uploadOneBatch(sink: sink) <= 0 { return }
            batches += 1
        }
        // Rows may remain: hand them to another run.
        requested = true
    }

    /// Uploads the oldest batch and clears it. Returns the rows cleared, or 0
    /// when the queue is empty or the upload failed.
    private func uploadOneBatch(sink: TraceletSyncSink) async -> Int {
        guard let db = TraceletSdk.shared.rustDatabase,
              let state = TraceletSdk.shared.rustEngineState else {
            return 0
        }
        let updatedHttp = state.getConfig().http
        guard let url = updatedHttp.url, !url.isEmpty, updatedHttp.autoSync else { return 0 }
        TraceletSdk.shared.logger.debug("Triggering sync to URL: \(url)")

        // CRITICAL FIX: Offload the synchronous blocking FFI call to a background
        // DispatchQueue so we do not starve the Swift Concurrency cooperative thread pool.
        // The whole read-upload-clear runs under the sink's lock, shared with a
        // manual or interval sync() (#437).
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let cleared: Int = sink.runExclusive {
                    do {
                        let limit: Int32 = updatedHttp.maxBatchSize > 0 ? updatedHttp.maxBatchSize : 250
                        // Always the OLDEST rows: `clearLocationsUpTo` deletes
                        // every id up to the one given (#437). The configured
                        // order (#138) applies inside the payload.
                        let oldest = try db.getLocationsBatch(query: LocationQuery(
                            startTimeMs: nil,
                            endTimeMs: nil,
                            limit: limit,
                            offset: nil,
                            orderDescending: false
                        ))
                        if oldest.isEmpty { return 0 }
                        let records = updatedHttp.locationsOrderDirection == 1
                            ? Array(oldest.reversed()) : oldest
                        let count = try sink.syncBatchBlocking(config: updatedHttp, records: records)
                        guard count > 0, let maxId = oldest.map({ $0.id }).max() else {
                            TraceletSdk.shared.logger.debug("No locations synced or count was 0.")
                            return 0
                        }
                        try db.clearLocationsUpTo(maxId: maxId)
                        TraceletSdk.shared.logger.debug("Synced and cleared \(count) locations.")
                        return oldest.count
                    } catch {
                        TraceletSdk.shared.logger.debug("Sync failed with error: \(error)")
                        return 0
                    }
                }
                continuation.resume(returning: cleared)
            }
        }
    }

    /// Exponential backoff from `retryBackoffBase`, capped at `retryBackoffCap`
    /// — the spacing the default path already uses (#437).
    nonisolated static func backoffNanos(attempt: Int, base: Int, cap: Int) -> UInt64 {
        let b = UInt64(base > 0 ? base : 1000)
        let c = UInt64(cap > 0 ? cap : 60_000)
        let ms = min(c, b << UInt64(min(max(attempt, 0), 20)))
        return ms * 1_000_000
    }

struct FallbackSyncResult {
    let success: Bool
    let status: Int
    let responseText: String
}

    // `nonisolated` is required: this is awaited from a `Task` while
    // `syncBatchBlocking` blocks the actor's executor on a semaphore during the
    // auto-sync path. If it were actor-isolated, that Task could never enter the
    // (blocked) actor and the semaphore would never be signaled — a deadlock
    // that silently killed custom-body auto-sync on iOS. It touches no actor
    // state, so isolation is unnecessary.
    nonisolated func executeFallbackHttpSync(coreHttp: HttpConfig, customBody: String, interceptor: DartSyncInterceptor?) async -> FallbackSyncResult {
        var currentHeaders = coreHttp.headers
        let maxRetries = Int(coreHttp.maxRetries)
        
        var lastStatus = 0
        var lastResponse = "Unknown error"
        
        for attempt in 0...maxRetries {
            guard let urlStr = coreHttp.url, let url = URL(string: urlStr) else { 
                return FallbackSyncResult(success: false, status: 0, responseText: "Invalid URL") 
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = coreHttp.method == 1 ? "PUT" : "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            // #437: the configured timeout, not a fixed 15 s.
            request.timeoutInterval = TimeInterval(coreHttp.httpTimeout > 0 ? coreHttp.httpTimeout : 60_000) / 1000
            
            for (k, v) in currentHeaders {
                request.setValue(v, forHTTPHeaderField: k)
            }
            
            request.httpBody = customBody.data(using: .utf8)
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse {
                    let status = httpResponse.statusCode
                    lastStatus = status
                    lastResponse = String(data: data, encoding: .utf8) ?? ""
                    
                    if (200...299).contains(status) {
                        return FallbackSyncResult(success: true, status: status, responseText: lastResponse)
                    } else if status == 401, let interceptor = interceptor {
                        if interceptor.requestTokenRefresh() {
                            if let newConfig = TraceletSdk.shared.rustEngineState?.getConfig().http {
                                currentHeaders = newConfig.headers
                            }
                            continue
                        } else {
                            return FallbackSyncResult(success: false, status: status, responseText: lastResponse)
                        }
                    } else if (400...499).contains(status) && status != 408 && status != 429 {
                        // Client error, no point in retrying (except timeout/rate limits)
                        return FallbackSyncResult(success: false, status: status, responseText: lastResponse)
                    }
                }
            } catch {
                TraceletSdk.shared.logger.debug("Fallback sync error: \(error)")
                lastResponse = error.localizedDescription
                lastStatus = 0
                // A timeout may land after the server received the body; a retry
                // would deliver the batch twice. The rows stay queued (#437).
                if (error as? URLError)?.code == .timedOut {
                    return FallbackSyncResult(success: false, status: lastStatus, responseText: lastResponse)
                }
            }

            if attempt < maxRetries {
                try? await Task.sleep(nanoseconds: Self.backoffNanos(
                    attempt: attempt, base: Int(coreHttp.retryBackoffBase), cap: Int(coreHttp.retryBackoffCap)))
            }
        }
        return FallbackSyncResult(success: false, status: lastStatus, responseText: lastResponse)
    }
}

class TraceletSyncSink: LocationDataSink, SyncProvider {
    let coordinator = SyncCoordinator()
    /// Shared by auto-sync and a manual or interval `sync()` (#437).
    private let exclusive = NSLock()

    func runExclusive<T>(_ body: () throws -> T) rethrows -> T {
        exclusive.lock()
        defer { exclusive.unlock() }
        return try body()
    }

    func requestDrain() {
        Task { await coordinator.scheduleSync(sink: self, delayMs: 0) }
    }

    private static let syncBodySourceLock = NSLock()
    private static var lastSyncBodySource: String?

    /// Records which body the sync is posting — but only when the answer
    /// changes (#340).
    ///
    /// The per-sync lines around the call sites are `debug`, so on a release
    /// build at the shipped log levels they are dropped and a device posting
    /// the default payload when the app registered a custom builder leaves no
    /// trace of it. The lifecycle channel is never level-gated, which is
    /// exactly what a release build needs.
    ///
    /// It cannot simply be written per sync, though: syncs fire every few
    /// seconds while tracking, and ``TraceletLogger/lifecycle(_:)`` is
    /// explicitly reserved for events that fire a handful of times per session
    /// because its rows share a bounded cap with the killed-state trail. One
    /// entry per sync would evict the trail it exists to preserve.
    ///
    /// Reporting only transitions costs a handful of rows per session and still
    /// answers the whole question: which body is this app sending, and did that
    /// ever change mid-session?
    private static func reportSyncBodySource(_ source: String, _ detail: String) {
        syncBodySourceLock.lock()
        let changed = lastSyncBodySource != source
        if changed { lastSyncBodySource = source }
        syncBodySourceLock.unlock()
        guard changed else { return }
        TraceletSdk.shared.logger.lifecycle("sync-body: \(detail)")
    }
    
    @discardableResult
    func insertLocation(_ location: [String: Any]) -> String {
        // #437: autoSyncThreshold was stored and passed to Rust but never read.
        if let http = TraceletSdk.shared.rustEngineState?.getConfig().http,
           http.autoSyncThreshold > 0,
           let pending = try? TraceletSdk.shared.rustDatabase?.getLocationsCount(),
           Int64(pending) < Int64(http.autoSyncThreshold) {
            return ""
        }
        Task {
            await coordinator.scheduleSync(sink: self)
        }
        return ""
    }

    // Cancel the in-flight debounce on stop() so background sync halts
    // immediately instead of firing ~autoSyncDelay later (#213).
    func cancelPendingSync() {
        Task { await coordinator.cancel() }
    }

    /// POSTs telematics to their own endpoint (#368).
    ///
    /// Reuses `executeFallbackHttpSync` so the dedicated endpoint gets the same
    /// headers, timeouts, retry/backoff and 401 token-refresh handling as the
    /// location path — the only difference is the URL and the body. Blocks on a
    /// semaphore like the custom-body path above, since the caller is a
    /// synchronous sync routine.
    func postTelematicsBlocking(config: HttpConfig, url: String, body: String) throws -> Bool {
        var telematicsHttp = config
        telematicsHttp.url = url

        let sem = DispatchSemaphore(value: 0)
        var fallbackResult: SyncCoordinator.FallbackSyncResult? = nil
        Task {
            fallbackResult = await coordinator.executeFallbackHttpSync(
                coreHttp: telematicsHttp,
                customBody: body,
                interceptor: TraceletSdk.shared.dartSyncInterceptor
            )
            sem.signal()
        }
        sem.wait()

        let result = fallbackResult ?? SyncCoordinator.FallbackSyncResult(
            success: false, status: 0, responseText: "Unknown error")
        TraceletSdk.shared.getEventSender().sendHttp([
            "success": result.success,
            "status": result.status,
            "responseText": result.responseText,
            "isRetry": false,
            "retryCount": 0
        ])
        return result.success
    }
    
    func syncBatchBlocking(config: HttpConfig, records: [DbLocationRecord]) throws -> UInt32 {
        let syncRecords: [tracelet_sync.SyncLocationRecord] = records.map { r in
            tracelet_sync.SyncLocationRecord(
                id: r.id,
                uuid: r.uuid,
                timestamp: r.timestamp,
                latitude: r.latitude,
                longitude: r.longitude,
                accuracy: r.accuracy,
                speed: r.speed,
                heading: r.heading,
                altitude: r.altitude,
                isMock: r.isMock,
                isMoving: r.isMoving,
                activity: r.activity,
                event: r.eventType,
                routeContext: r.routeContext,
                address: r.address,  // #212: carry reverse-geocoded address into the default payload
                // #402: carried from the row, not resolved at flush time.
                tripId: r.tripId
            )
        }
        
        // INTERCEPTOR LOGIC
        if let interceptor = TraceletSdk.shared.dartSyncInterceptor {
            if interceptor.requestFreshHeaders() {
                TraceletSdk.shared.logger.debug("Headers refreshed in syncBatchBlocking")
            }
            let updatedHttp = TraceletSdk.shared.rustEngineState?.getConfig().http ?? config
            
            // Issue #126: emit the SAME nested schema as onLocation/getLocations
            // (nested coords/activity/battery + route_context) so the Dart
            // custom-body builder receives a consistent shape instead of a flat
            // map with a raw String activity.
            let syncRecordsMap: [[String: Any]] = records.map {
                TraceletSdk.shared.mapRecordToLocation($0)
            }
            
            let customBody = interceptor.requestSyncBody(locations: syncRecordsMap)
            if customBody == nil {
                // A builder is registered but it timed out or threw.
                // requestSyncBody returns the sentinel (not nil) when no builder
                // exists, so nil here unambiguously means failure: abort the sync
                // rather than posting an error object or the default payload.
                TraceletSdk.shared.logger.error("Custom sync body failed to build; aborting sync.")
                TraceletSdk.shared.getEventSender().sendHttp([
                    "success": false,
                    "status": 0,
                    "responseText": "custom sync body failed to build",
                    "isRetry": false,
                    "retryCount": 0
                ])
                return 0
            }
            if let body = customBody, body != traceletNoSyncBodyBuilderSentinel {
                TraceletSdk.shared.logger.debug("customBody from interceptor (syncBatchBlocking): \(body)")
                TraceletSyncSink.reportSyncBodySource(
                    "custom", "posting the app's custom sync body")
                let sem = DispatchSemaphore(value: 0)
                var fallbackResult: SyncCoordinator.FallbackSyncResult? = nil

                Task {
                    fallbackResult = await coordinator.executeFallbackHttpSync(coreHttp: updatedHttp, customBody: body, interceptor: interceptor)
                    sem.signal()
                }

                sem.wait()

                if let result = fallbackResult, result.success {
                    // #214 dedup: the custom builder may have included the
                    // telematics we exposed; the POST succeeded, so mark exactly
                    // those synced so they aren't re-sent.
                    TraceletSdk.shared.markExposedTelematicsSynced()
                    TraceletSdk.shared.getEventSender().sendHttp([
                        "success": true,
                        "status": result.status,
                        "responseText": result.responseText,
                        "isRetry": false,
                        "retryCount": 0
                    ])
                    return UInt32(records.count)
                } else {
                    let result = fallbackResult ?? SyncCoordinator.FallbackSyncResult(success: false, status: 0, responseText: "Unknown error")
                    TraceletSdk.shared.logger.debug("Custom body sync failed with status \(result.status)")
                    TraceletSdk.shared.getEventSender().sendHttp([
                        "success": false,
                        "status": result.status,
                        "responseText": result.responseText,
                        "isRetry": false,
                        "retryCount": 0
                    ])
                    return 0
                }
            }
            // sentinel → no builder → fall through to the default sync below.
            TraceletSyncSink.reportSyncBodySource(
                "no-builder",
                "posting the DEFAULT payload — no custom sync body builder reached native "
                    + "(setSyncBodyBuilder registered in Dart?)")
        } else {
            // #340: a nil interceptor and a registered-but-unreported builder
            // both ended up here posting the default payload, and neither said
            // so. Naming this branch is what separates "the plugin never
            // attached itself to the SDK" from "Dart never registered a
            // builder" — see the matching log in `requestSyncBody`.
            TraceletSdk.shared.logger.debug(
                "syncBatchBlocking: no dartSyncInterceptor attached — using the default payload")
            TraceletSyncSink.reportSyncBodySource(
                "no-interceptor",
                "posting the DEFAULT payload — no dartSyncInterceptor attached to the SDK")
        }

        let syncHttp = tracelet_sync.SyncHttpConfig(
            url: config.url,
            method: config.method,
            headers: config.headers,
            batchSync: config.batchSync,
            maxBatchSize: config.maxBatchSize,
            autoSync: config.autoSync,
            maxRetries: config.maxRetries,
            retryBackoffBase: config.retryBackoffBase,
            retryBackoffCap: config.retryBackoffCap,
            sslPinningCertificates: config.sslPinningCertificates,
            sslPinningFingerprints: config.sslPinningFingerprints,
            httpRootProperty: config.httpRootProperty,
            params: config.params,
            extras: config.extras,
            disableAutoSyncOnCellular: config.disableAutoSyncOnCellular,
            enableDeltaCompression: config.enableDeltaCompression,
            deltaCoordinatePrecision: config.deltaCoordinatePrecision,
            locationsOrderDirection: config.locationsOrderDirection
        )
        
        let syncManager = SyncManager()
        do {
            let count = try syncManager.syncBatchBlocking(config: syncHttp, records: syncRecords)
            if count > 0 {
                TraceletSdk.shared.getEventSender().sendHttp([
                    "success": true,
                    "status": 200,
                    "responseText": "Synced \(count) locations",
                    "isRetry": false,
                    "retryCount": 0
                ])
            } else {
                TraceletSdk.shared.getEventSender().sendHttp([
                    "success": false,
                    "status": 0,
                    "responseText": "Sync failed",
                    "isRetry": false,
                    "retryCount": 0
                ])
            }
            return count
        } catch {
            TraceletSdk.shared.getEventSender().sendHttp([
                "success": false,
                "status": 0,
                "responseText": error.localizedDescription,
                "isRetry": false,
                "retryCount": 0
            ])
            throw error
        }
    }
}

@objc(TraceletSyncPlugin)
public class TraceletSyncPlugin: NSObject, FlutterPlugin {
  /// The one and only sink for this process (#286).
  ///
  /// `register(with:)` runs once per `FlutterPluginRegistrar`, i.e. once per
  /// `FlutterEngine`, and it used to build a brand-new `TraceletSyncSink` every
  /// time, append it to the shared `TraceletSdk.shared.locationEngine` and assign
  /// it as the SDK's `syncProvider`. Nothing ever removed it: iOS had no
  /// `detachFromEngine(for:)` here, `LocationEngine.registerSink` was a bare
  /// `append`, and there was no replace-and-unregister step. Hosts that create
  /// secondary engines (`workmanager` does so per background task, plus headless
  /// engines and engine groups) therefore accumulated sinks, each with its own
  /// `SyncCoordinator` actor — so the per-sink debounce could not serialize
  /// across them and one persisted fix fanned out into N concurrent syncs.
  ///
  /// `TraceletSdk` is a singleton and only one sync provider can be active, so
  /// the sink is created on first registration and reused by every later engine.
  private static var sharedSink: TraceletSyncSink?
  private static let sharedSinkLock = NSLock()

  /// The process-wide sink, created on first use. `created` is true only for the
  /// very first registrar, which keeps the log honest about how many exist.
  static func obtainSharedSink() -> (sink: TraceletSyncSink, created: Bool) {
    sharedSinkLock.lock()
    defer { sharedSinkLock.unlock() }
    if let existing = sharedSink {
      return (existing, false)
    }
    let sink = TraceletSyncSink()
    sharedSink = sink
    return (sink, true)
  }

  /// Visible for tests: forget the process-wide sink between cases.
  static func resetSharedSinkForTesting() {
    sharedSinkLock.lock()
    defer { sharedSinkLock.unlock() }
    sharedSink = nil
  }

  private var channel: FlutterMethodChannel?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "tracelet_sync", binaryMessenger: registrar.messenger())
    let instance = TraceletSyncPlugin()
    instance.channel = channel

    let (sink, created) = obtainSharedSink()
    // Assign the provider only — its `didSet` subscribes the sink to the
    // LocationEngine, and `initialize()` re-subscribes the current provider when
    // it builds a new engine. Subscribing here as well used to add the same sink
    // to the engine's list twice per engine, and it force unwrapped the engine,
    // which made registration order-dependent.
    if (TraceletSdk.shared.syncProvider as AnyObject?) !== sink {
      TraceletSdk.shared.syncProvider = sink
    }
    print("TraceletSync: Native iOS sink \(created ? "registered" : "reused for an additional engine (process-wide, #286)")!")

    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "initialize" {
      result(true)
    } else {
      result(FlutterMethodNotImplemented)
    }
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    channel?.setMethodCallHandler(nil)
    channel = nil
    // The sink is deliberately NOT torn down: it is process-wide now, so there is
    // nothing to accumulate, and native tracking keeps persisting locations after
    // an engine (often a short-lived background one) goes away. TraceletSdk.stop()
    // still calls cancelPendingSync() when the user stops tracking (#213).
  }
}
