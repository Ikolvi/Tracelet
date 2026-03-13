import Foundation
import Network

/// HTTP sync manager using URLSession.
///
/// Syncs unsynced locations from SQLite to the configured URL. Supports
/// batch/single mode, configurable headers/method, exponential backoff
/// with jitter, connectivity-based deferred sync, and batch continuation.
final class HttpSyncManager {
    private let configManager: ConfigManager
    private let eventDispatcher: EventDispatcher
    private let database: TraceletDatabase

    private var session: URLSession
    private var retryCount = 0

    /// Serial queue protecting `_isSyncing`, `_isConnected`, `_pendingSyncOnConnect`.
    private let stateQueue = DispatchQueue(label: "com.tracelet.httpSync.state")
    private var _isSyncing = false
    private let pathMonitor = NWPathMonitor()
    private var _isConnected = true
    private var _pendingSyncOnConnect = false

    /// Thread-safe accessors for state flags.
    private var isSyncing: Bool {
        get { stateQueue.sync { _isSyncing } }
        set { stateQueue.sync { _isSyncing = newValue } }
    }
    private var isConnected: Bool {
        get { stateQueue.sync { _isConnected } }
        set { stateQueue.sync { _isConnected = newValue } }
    }
    private var pendingSyncOnConnect: Bool {
        get { stateQueue.sync { _pendingSyncOnConnect } }
        set { stateQueue.sync { _pendingSyncOnConnect = newValue } }
    }

    init(configManager: ConfigManager,
         eventDispatcher: EventDispatcher,
         database: TraceletDatabase) {
        self.configManager = configManager
        self.eventDispatcher = eventDispatcher
        self.database = database

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config)
    }

    func start() {
        // Start network path monitor for cellular detection and connectivity
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let wasConnected = self.isConnected
            self.isConnected = path.status == .satisfied

            if self.isConnected && !wasConnected {
                self.eventDispatcher.sendConnectivityChange(["connected": true])
                if self.pendingSyncOnConnect {
                    self.pendingSyncOnConnect = false
                    self.sync(completion: nil)
                }
            } else if !self.isConnected && wasConnected {
                self.eventDispatcher.sendConnectivityChange(["connected": false])
            }
        }
        pathMonitor.start(queue: DispatchQueue.global(qos: .utility))
    }

    func stop() {
        // Cancel all in-flight tasks without invalidating the session (I-M3).
        // invalidateAndCancel() renders the session permanently unusable;
        // if start() is called again later, sync requests would silently fail.
        session.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
        pathMonitor.cancel()
    }

    // MARK: - Trigger sync

    func onLocationInserted() {
        guard configManager.getAutoSync() else { return }
        guard !configManager.getUrl().isEmpty else { return }

        // Skip auto-sync on cellular if configured
        if configManager.getDisableAutoSyncOnCellular() && isCellular() { return }

        let threshold = configManager.getAutoSyncThreshold()
        if threshold > 0 {
            let count = database.getLocationCount()
            guard count >= threshold else { return }
        }

        sync(completion: nil)
    }

    // MARK: - Manual sync

    func sync(completion: (([[String: Any]]) -> Void)?) {
        guard !isSyncing else {
            completion?([])
            return
        }
        guard !configManager.getUrl().isEmpty else {
            completion?([])
            return
        }

        isSyncing = true

        // Request background execution time so iOS doesn't suspend us
        // mid-sync (network I/O + DB markSynced).
        let bgTaskId = BackgroundTaskHelper.shared.begin("httpSync")

        syncNextBatch(allSynced: [], bgTaskId: bgTaskId, completion: completion)
    }

    // MARK: - Batch continuation loop

    /// Fetches and syncs batches in sequence until no more unsynced locations
    /// remain or a failure occurs.
    private func syncNextBatch(allSynced: [[String: Any]],
                               bgTaskId: UIBackgroundTaskIdentifier?,
                               completion: (([[String: Any]]) -> Void)?) {
        let maxBatch = configManager.getMaxBatchSize()
        let limit = maxBatch > 0 ? maxBatch : 100

        let locations = database.getUnsyncedLocations(limit: limit)
        guard !locations.isEmpty else {
            // All done — no more unsynced locations
            isSyncing = false
            if let bgTaskId = bgTaskId { BackgroundTaskHelper.shared.end(bgTaskId) }
            completion?(allSynced)
            return
        }

        // Check connectivity before sending
        guard isConnected else {
            pendingSyncOnConnect = true
            isSyncing = false
            if let bgTaskId = bgTaskId { BackgroundTaskHelper.shared.end(bgTaskId) }
            completion?(allSynced)
            return
        }

        let batchSync = configManager.getBatchSync()
        if batchSync {
            syncBatch(locations) { [weak self] synced in
                guard let self = self else { return }
                if synced.isEmpty {
                    // Failure — stop
                    self.isSyncing = false
                    if let bgTaskId = bgTaskId { BackgroundTaskHelper.shared.end(bgTaskId) }
                    completion?(allSynced)
                } else {
                    // Continue to next batch
                    self.syncNextBatch(
                        allSynced: allSynced + synced,
                        bgTaskId: bgTaskId,
                        completion: completion
                    )
                }
            }
        } else {
            syncOneByOne(locations, index: 0, synced: []) { [weak self] synced in
                guard let self = self else { return }
                let combined = allSynced + synced
                if synced.count < locations.count {
                    // Partial failure — stop
                    self.isSyncing = false
                    if let bgTaskId = bgTaskId { BackgroundTaskHelper.shared.end(bgTaskId) }
                    completion?(combined)
                } else {
                    // All succeeded — continue to next batch
                    self.syncNextBatch(
                        allSynced: combined,
                        bgTaskId: bgTaskId,
                        completion: completion
                    )
                }
            }
        }
    }

    // MARK: - Batch sync

    private func syncBatch(_ locations: [[String: Any]],
                           completion: @escaping ([[String: Any]]) -> Void) {
        let rootProperty = configManager.getHttpRootProperty()
        let useDelta = configManager.getEnableDeltaCompression() && locations.count > 1
        let payload: [[String: Any]] = useDelta
            ? DeltaEncoder.encode(locations, precision: configManager.getDeltaCoordinatePrecision())
            : locations
        let body: [String: Any]
        if rootProperty.isEmpty {
            body = ["locations": payload]
        } else {
            body = [rootProperty: payload]
        }

        sendRequest(body: body) { [weak self] success, statusCode, responseBody in
            guard let self = self else { return }

            if success {
                let uuids = locations.compactMap { $0["uuid"] as? String }
                self.database.markSynced(uuids: uuids)
                self.retryCount = 0

                self.eventDispatcher.sendHttp([
                    "success": true,
                    "status": statusCode,
                    "responseText": responseBody,
                    "isRetry": false,
                    "retryCount": 0,
                ])
                completion(locations)
            } else {
                self.handleFailure(
                    statusCode: statusCode,
                    responseBody: responseBody,
                    locations: locations,
                    isBatch: true,
                    completion: completion
                )
            }
        }
    }

    // MARK: - One-by-one sync

    private func syncOneByOne(_ locations: [[String: Any]],
                              index: Int,
                              synced: [[String: Any]],
                              completion: @escaping ([[String: Any]]) -> Void) {
        guard index < locations.count else {
            completion(synced)
            return
        }

        let location = locations[index]
        let rootProperty = configManager.getHttpRootProperty()
        let body: [String: Any]
        if rootProperty.isEmpty {
            body = location
        } else {
            body = [rootProperty: location]
        }

        sendRequest(body: body) { [weak self] success, statusCode, responseBody in
            guard let self = self else { return }

            var updatedSynced = synced
            if success {
                if let uuid = location["uuid"] as? String {
                    self.database.markSynced(uuids: [uuid])
                }
                updatedSynced.append(location)
                self.retryCount = 0

                self.eventDispatcher.sendHttp([
                    "success": true,
                    "status": statusCode,
                    "responseText": responseBody,
                    "isRetry": false,
                    "retryCount": 0,
                ])
            } else {
                self.handleFailure(
                    statusCode: statusCode,
                    responseBody: responseBody,
                    locations: [location],
                    isBatch: false
                ) { retryResult in
                    // If retry succeeded, continue; otherwise stop
                    if !retryResult.isEmpty {
                        if let uuid = location["uuid"] as? String {
                            self.database.markSynced(uuids: [uuid])
                        }
                        updatedSynced.append(location)
                        self.syncOneByOne(locations, index: index + 1,
                                         synced: updatedSynced, completion: completion)
                    } else {
                        completion(updatedSynced)
                    }
                }
                return
            }

            self.syncOneByOne(locations, index: index + 1,
                             synced: updatedSynced, completion: completion)
        }
    }

    // MARK: - HTTP request

    private func sendRequest(body: [String: Any],
                             completion: @escaping (Bool, Int, String) -> Void) {
        guard let url = URL(string: configManager.getUrl()) else {
            completion(false, 0, "Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = configManager.getHttpMethod()

        // Headers
        let headers = configManager.getHttpHeaders()
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if request.value(forHTTPHeaderField: "Content-Type") == nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        // Timeout
        let timeout = configManager.getHttpTimeout()
        request.timeoutInterval = TimeInterval(timeout) / 1000.0

        // Body
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(false, 0, "JSON serialization failed")
            return
        }
        request.httpBody = jsonData

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(false, 0, error.localizedDescription)
                return
            }

            let httpResponse = response as? HTTPURLResponse
            let statusCode = httpResponse?.statusCode ?? 0
            let responseBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

            let success = (200..<300).contains(statusCode)
            completion(success, statusCode, responseBody)
        }
        task.resume()
    }

    // MARK: - Error handling

    private func handleFailure(statusCode: Int,
                               responseBody: String,
                               locations: [[String: Any]],
                               isBatch: Bool,
                               completion: @escaping ([[String: Any]]) -> Void) {
        let maxRetries = configManager.getMaxRetries()
        let baseMs = Double(configManager.getRetryBackoffBase()) / 1000.0
        let capMs = Double(configManager.getRetryBackoffCap()) / 1000.0

        retryCount += 1

        eventDispatcher.sendHttp([
            "success": false,
            "status": statusCode,
            "responseText": responseBody,
            "isRetry": retryCount > 1,
            "retryCount": retryCount - 1,
        ])

        // Transient error: 0 (network), 408 (timeout), 429 (rate-limit), 5xx
        if isTransientError(statusCode) && retryCount <= maxRetries {
            let delay = min(capMs, baseMs * pow(2.0, Double(retryCount - 1)))
            let jitter = Double.random(in: 0...delay * 0.1)
            DispatchQueue.global().asyncAfter(deadline: .now() + delay + jitter) { [weak self] in
                guard let self = self else { return }
                // Re-send the same payload
                let body: [String: Any]
                if isBatch {
                    let rootProperty = self.configManager.getHttpRootProperty()
                    body = rootProperty.isEmpty
                        ? ["locations": locations]
                        : [rootProperty: locations]
                } else {
                    let rootProperty = self.configManager.getHttpRootProperty()
                    body = rootProperty.isEmpty
                        ? locations[0]
                        : [rootProperty: locations[0]]
                }

                self.sendRequest(body: body) { success, code, response in
                    if success {
                        self.retryCount = 0
                        self.eventDispatcher.sendHttp([
                            "success": true,
                            "status": code,
                            "responseText": response,
                            "isRetry": true,
                            "retryCount": self.retryCount,
                        ])
                        completion(locations)
                    } else {
                        self.handleFailure(
                            statusCode: code,
                            responseBody: response,
                            locations: locations,
                            isBatch: isBatch,
                            completion: completion
                        )
                    }
                }
            }
        } else {
            // Permanent failure or max retries exceeded — reset and stop
            retryCount = 0
            completion([])
        }
    }

    private func isTransientError(_ statusCode: Int) -> Bool {
        return statusCode == 0 || statusCode == 408 || statusCode == 429 ||
               (statusCode >= 500 && statusCode < 600)
    }

    /// Returns true if the current network path is cellular only.
    private func isCellular() -> Bool {
        let path = pathMonitor.currentPath
        return path.usesInterfaceType(.cellular) && !path.usesInterfaceType(.wifi)
    }
}
