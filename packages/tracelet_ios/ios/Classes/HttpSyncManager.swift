import Foundation

/// HTTP sync manager using URLSession.
///
/// Syncs unsynced locations from SQLite to the configured URL. Supports
/// batch/single mode, configurable headers/method, and exponential backoff.
final class HttpSyncManager {
    private let configManager: ConfigManager
    private let eventDispatcher: EventDispatcher
    private let database: TraceletDatabase

    private let session: URLSession
    private var retryCount = 0
    private let maxRetries = 10
    private var isSyncing = false

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
        // Auto-sync is driven by onLocationInserted calls
    }

    func stop() {
        session.invalidateAndCancel()
    }

    // MARK: - Trigger sync

    func onLocationInserted() {
        guard configManager.getAutoSync() else { return }
        guard !configManager.getUrl().isEmpty else { return }

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
        let batchSync = configManager.getBatchSync()
        let maxBatch = configManager.getMaxBatchSize()
        let limit = maxBatch > 0 ? maxBatch : 100

        let locations = database.getUnsyncedLocations(limit: limit)
        guard !locations.isEmpty else {
            isSyncing = false
            completion?([])
            return
        }

        if batchSync {
            syncBatch(locations, completion: completion)
        } else {
            syncOneByOne(locations, index: 0, synced: [], completion: completion)
        }
    }

    // MARK: - Batch sync

    private func syncBatch(_ locations: [[String: Any]],
                           completion: (([[String: Any]]) -> Void)?) {
        let rootProperty = configManager.getHttpRootProperty()
        let body: [String: Any]
        if rootProperty.isEmpty {
            body = ["locations": locations]
        } else {
            body = [rootProperty: locations]
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
                ])
            } else {
                self.handleFailure(statusCode: statusCode, responseBody: responseBody)
            }

            self.isSyncing = false
            completion?(success ? locations : [])
        }
    }

    // MARK: - One-by-one sync

    private func syncOneByOne(_ locations: [[String: Any]],
                              index: Int,
                              synced: [[String: Any]],
                              completion: (([[String: Any]]) -> Void)?) {
        guard index < locations.count else {
            isSyncing = false
            completion?(synced)
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
                ])
            } else {
                self.handleFailure(statusCode: statusCode, responseBody: responseBody)
                // Stop syncing on failure
                self.isSyncing = false
                completion?(updatedSynced)
                return
            }

            self.syncOneByOne(locations, index: index + 1, synced: updatedSynced, completion: completion)
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

    private func handleFailure(statusCode: Int, responseBody: String) {
        retryCount += 1

        eventDispatcher.sendHttp([
            "success": false,
            "status": statusCode,
            "responseText": responseBody,
        ])

        // Exponential backoff for transient errors
        if isTransientError(statusCode) && retryCount < maxRetries {
            let delay = min(pow(2.0, Double(retryCount)), 300.0)
            let jitter = Double.random(in: 0...delay * 0.1)
            DispatchQueue.global().asyncAfter(deadline: .now() + delay + jitter) { [weak self] in
                self?.sync(completion: nil)
            }
        }
    }

    private func isTransientError(_ statusCode: Int) -> Bool {
        return statusCode == 0 || statusCode == 408 || statusCode == 429 ||
               (statusCode >= 500 && statusCode < 600)
    }
}
