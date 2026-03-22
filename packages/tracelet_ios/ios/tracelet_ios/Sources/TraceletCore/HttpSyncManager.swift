import Foundation
import Network
import CommonCrypto

/// HTTP sync manager using URLSession.
///
/// Syncs unsynced locations from SQLite to the configured URL. Supports
/// batch/single mode, configurable headers/method, exponential backoff
/// with jitter, connectivity-based deferred sync, and batch continuation.
public final class HttpSyncManager: NSObject, URLSessionDelegate {
    private let configManager: ConfigManager
    private let eventDispatcher: TraceletEventSending
    private let database: TraceletDatabase

    private var session: URLSession!
    private var retryCount = 0

    /// Cached DER-encoded trusted certificates for SSL pinning.
    private var pinnedCertificates: [Data] = []
    /// Cached SHA-256 fingerprints for SSL pinning.
    private var pinnedFingerprints: [String] = []

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

    /// Called when a 401 Unauthorized response is received during sync.
    ///
    /// The closure should attempt to refresh authorization headers
    /// (e.g., by invoking a headless Dart callback that calls
    /// `ConfigManager.setDynamicHeaders`). Returns `true` if headers
    /// were successfully refreshed and the request should be retried.
    public var onAuthorizationRequired: (() -> Bool)?

    public init(configManager: ConfigManager,
         eventDispatcher: TraceletEventSending,
         database: TraceletDatabase) {
        self.configManager = configManager
        self.eventDispatcher = eventDispatcher
        self.database = database
        super.init()

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: sessionConfig, delegate: self, delegateQueue: nil)
    }

    /// Testing initializer — allows injecting a custom `URLSessionConfiguration`
    /// (e.g. with `protocolClasses` set to a mock `URLProtocol` subclass).
    public init(configManager: ConfigManager,
         eventDispatcher: TraceletEventSending,
         database: TraceletDatabase,
         sessionConfiguration: URLSessionConfiguration) {
        self.configManager = configManager
        self.eventDispatcher = eventDispatcher
        self.database = database
        super.init()
        self.session = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
    }

    public func start() {
        // Configure SSL pinning from config
        configureSslPinning()

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

    public func stop() {
        // Cancel all in-flight tasks without invalidating the session (I-M3).
        // invalidateAndCancel() renders the session permanently unusable;
        // if start() is called again later, sync requests would silently fail.
        session.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
        pathMonitor.cancel()
    }

    // MARK: - Trigger sync

    public func onLocationInserted() {
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

    public func sync(completion: (([[String: Any]]) -> Void)?) {
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

        // Headers (merged: static config + dynamic)
        let headers = configManager.getMergedHttpHeaders()
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
                               authRetried: Bool = false,
                               completion: @escaping ([[String: Any]]) -> Void) {
        let maxRetries = configManager.getMaxRetries()
        let baseMs = Double(configManager.getRetryBackoffBase()) / 1000.0
        let capMs = Double(configManager.getRetryBackoffCap()) / 1000.0

        retryCount += 1

        eventDispatcher.sendHttp([
            "success": false,
            "status": statusCode,
            "responseText": responseBody,
            "isRetry": retryCount > 1 || authRetried,
            "retryCount": retryCount - 1,
        ])

        // 401 Unauthorized — attempt to refresh authorization headers once.
        if statusCode == 401 && !authRetried {
            NSLog("[Tracelet] HTTP sync 401 Unauthorized — requesting headers refresh")
            let refreshed = onAuthorizationRequired?() ?? false
            if refreshed {
                NSLog("[Tracelet] Headers refreshed, retrying request")
                retryCount = 0
                // Re-send with updated headers
                let body: [String: Any]
                if isBatch {
                    let rootProperty = configManager.getHttpRootProperty()
                    body = rootProperty.isEmpty
                        ? ["locations": locations]
                        : [rootProperty: locations]
                } else {
                    let rootProperty = configManager.getHttpRootProperty()
                    body = rootProperty.isEmpty
                        ? locations[0]
                        : [rootProperty: locations[0]]
                }

                sendRequest(body: body) { success, code, response in
                    if success {
                        self.retryCount = 0
                        self.eventDispatcher.sendHttp([
                            "success": true,
                            "status": code,
                            "responseText": response,
                            "isRetry": true,
                            "retryCount": 0,
                        ])
                        completion(locations)
                    } else {
                        self.handleFailure(
                            statusCode: code,
                            responseBody: response,
                            locations: locations,
                            isBatch: isBatch,
                            authRetried: true,
                            completion: completion
                        )
                    }
                }
                return
            }
            NSLog("[Tracelet] Headers refresh failed or unavailable — treating 401 as permanent failure")
            retryCount = 0
            completion([])
            return
        }

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
                            authRetried: authRetried,
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

    // MARK: - SSL Pinning

    /// Loads SSL pinning certificates and fingerprints from config.
    private func configureSslPinning() {
        // Load base64-encoded DER certificates
        let certStrings = configManager.getSslPinningCertificates()
        pinnedCertificates = certStrings.compactMap { Data(base64Encoded: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }

        // Load SHA-256 fingerprints (format: "sha256/BASE64HASH")
        pinnedFingerprints = configManager.getSslPinningFingerprints()

        if !pinnedCertificates.isEmpty || !pinnedFingerprints.isEmpty {
            NSLog("[Tracelet] SSL pinning configured: %d certificates, %d fingerprints",
                  pinnedCertificates.count, pinnedFingerprints.count)
        }
    }

    /// URLSessionDelegate — validates server trust against pinned certificates/fingerprints.
    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // If no pinning is configured, use default system validation
        guard !pinnedCertificates.isEmpty || !pinnedFingerprints.isEmpty else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Evaluate server trust first
        var error: CFError?
        let isValid = SecTrustEvaluateWithError(serverTrust, &error)
        guard isValid else {
            NSLog("[Tracelet] SSL pinning: server trust evaluation failed")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Check certificate pinning
        if !pinnedCertificates.isEmpty {
            let certCount = SecTrustGetCertificateCount(serverTrust)
            var matched = false
            for i in 0..<certCount {
                if let serverCert = SecTrustGetCertificateAtIndex(serverTrust, i) {
                    let serverCertData = SecCertificateCopyData(serverCert) as Data
                    if pinnedCertificates.contains(serverCertData) {
                        matched = true
                        break
                    }
                }
            }
            if !matched {
                NSLog("[Tracelet] SSL pinning: certificate mismatch")
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
        }

        // Check fingerprint pinning
        if !pinnedFingerprints.isEmpty {
            let certCount = SecTrustGetCertificateCount(serverTrust)
            var matched = false
            for i in 0..<certCount {
                if let serverCert = SecTrustGetCertificateAtIndex(serverTrust, i) {
                    let serverCertData = SecCertificateCopyData(serverCert) as Data
                    let hash = sha256(serverCertData)
                    let fingerprint = "sha256/" + hash.base64EncodedString()
                    if pinnedFingerprints.contains(fingerprint) {
                        matched = true
                        break
                    }
                }
            }
            if !matched {
                NSLog("[Tracelet] SSL pinning: fingerprint mismatch")
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
        }

        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }

    /// Computes SHA-256 hash of data using CommonCrypto.
    private func sha256(_ data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { bytes in
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }

    // MARK: - Remote Config (Enterprise)

    /// Fetches remote configuration from an HTTPS URL with ETag caching.
    ///
    /// - Parameters:
    ///   - url: The HTTPS URL to fetch config from.
    ///   - headers: Additional HTTP headers.
    ///   - timeoutMs: Request timeout in milliseconds.
    ///   - completion: Called with the parsed config dictionary, or nil on failure.
    func fetchRemoteConfig(
        url: String,
        headers: [String: String],
        timeoutMs: Int,
        completion: @escaping ([String: Any]?) -> Void
    ) {
        guard let requestUrl = URL(string: url), requestUrl.scheme == "https" else {
            NSLog("[Tracelet] [RemoteConfig] URL must use HTTPS: %@", url)
            completion(nil)
            return
        }

        var request = URLRequest(url: requestUrl)
        request.httpMethod = "GET"
        request.timeoutInterval = TimeInterval(timeoutMs) / 1000.0
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let defaults = UserDefaults.standard
        if let savedETag = defaults.string(forKey: "com.tracelet.remoteConfig.etag") {
            request.setValue(savedETag, forHTTPHeaderField: "If-None-Match")
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let httpResponse = response as? HTTPURLResponse else {
                NSLog("[Tracelet] [RemoteConfig] Request failed: %@", error?.localizedDescription ?? "unknown")
                completion(nil)
                return
            }

            if httpResponse.statusCode == 304 {
                if let cachedData = defaults.data(forKey: "com.tracelet.remoteConfig.cached"),
                   let cached = try? JSONSerialization.jsonObject(with: cachedData) as? [String: Any] {
                    completion(cached)
                } else {
                    completion(nil)
                }
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                NSLog("[Tracelet] [RemoteConfig] HTTP %d", httpResponse.statusCode)
                completion(nil)
                return
            }

            guard let data = data, data.count <= 100_000 else {
                NSLog("[Tracelet] [RemoteConfig] Response too large or empty")
                completion(nil)
                return
            }

            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
            guard contentType.contains("json") else {
                NSLog("[Tracelet] [RemoteConfig] Invalid content type: %@", contentType)
                completion(nil)
                return
            }

            guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                NSLog("[Tracelet] [RemoteConfig] Failed to parse JSON")
                completion(nil)
                return
            }

            if let etag = httpResponse.value(forHTTPHeaderField: "ETag") {
                defaults.set(etag, forKey: "com.tracelet.remoteConfig.etag")
            }
            defaults.set(data, forKey: "com.tracelet.remoteConfig.cached")

            completion(parsed)
        }
        task.resume()
    }
}
