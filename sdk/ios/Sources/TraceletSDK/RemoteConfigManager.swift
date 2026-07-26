import Foundation

/// Fetches configuration overrides from a remote HTTPS endpoint and applies them
/// on top of the local config, refreshing periodically in the background
/// (Enterprise `remoteConfigUrl`).
///
/// The endpoint returns a JSON config map — either flat or in the nested
/// `{app:{}, geo:{}, http:{}, ...}` shape that `ConfigManager.setConfig` already
/// accepts. The last successful response is cached to disk so a restart resumes
/// on the freshest known config instantly and offline, before the network
/// round-trip completes.
///
/// Only HTTPS URLs are honored. Fetches run asynchronously via `URLSession`;
/// failures are logged and never surfaced to the caller — the SDK keeps running
/// on local/cached config. Mirrors the Android `RemoteConfigManager`.
public final class RemoteConfigManager {

    private let configManager: ConfigManager
    private let log: (String) -> Void
    private let cacheFile = "tracelet_remote_config.json"
    private let queue = DispatchQueue(label: "com.tracelet.remote-config")
    private var timer: DispatchSourceTimer?

    /// Floor for the periodic refresh cadence (15 min), matching platform norms.
    private let minRefreshSeconds = 900

    public init(configManager: ConfigManager, log: @escaping (String) -> Void = { _ in }) {
        self.configManager = configManager
        self.log = log
    }

    private func cacheURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent(cacheFile)
    }

    /// Last successfully fetched remote config, or `nil` if never fetched.
    public func cachedConfig() -> [String: Any]? {
        guard let data = try? Data(contentsOf: cacheURL()),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    /// Kicks off an immediate background fetch and schedules periodic refreshes at
    /// `remoteConfigRefreshInterval` (minutes). `onConfig` is invoked on the main
    /// queue with each freshly fetched config map so the caller can apply it (e.g.
    /// via `TraceletSdk.setConfig`).
    ///
    /// A refresh interval of `0` (or negative) fetches once and never repeats.
    public func start(url: String, onConfig: @escaping ([String: Any]) -> Void) {
        stop()
        fetchOnce(url: url, onConfig: onConfig)

        let minutes = configManager.getRemoteConfigRefreshInterval()
        guard minutes > 0 else { return }
        let seconds = max(minutes * 60, minRefreshSeconds)
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + .seconds(seconds), repeating: .seconds(seconds))
        t.setEventHandler { [weak self] in self?.fetchOnce(url: url, onConfig: onConfig) }
        timer = t
        t.resume()
    }

    /// Stops periodic refreshes. Safe to call when not running.
    public func stop() {
        timer?.cancel()
        timer = nil
    }

    private func fetchOnce(url: String, onConfig: @escaping ([String: Any]) -> Void) {
        fetch(url: url) { [weak self] remote in
            guard let self = self, let remote = remote else { return }
            self.cache(remote)
            self.log("remote config: fetched \(remote.count) key(s) from \(url)")
            DispatchQueue.main.async { onConfig(remote) }
        }
    }

    private func fetch(url: String, completion: @escaping ([String: Any]?) -> Void) {
        // Reject non-HTTPS URLs — config controls tracking behavior and must not
        // be delivered over a channel an attacker can tamper with.
        guard url.hasPrefix("https://"), let endpoint = URL(string: url) else {
            log("remote config: URL rejected — only HTTPS is allowed")
            completion(nil)
            return
        }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "accept")
        let timeoutMs = max(configManager.getRemoteConfigTimeout(), 1000)
        req.timeoutInterval = Double(timeoutMs) / 1000.0
        for (key, value) in configManager.getRemoteConfigHeaders() {
            req.setValue(value, forHTTPHeaderField: key)
        }
        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            guard let self = self else { completion(nil); return }
            if let error = error {
                self.log("remote config: fetch failed (\(error.localizedDescription))")
                completion(nil)
                return
            }
            guard let http = response as? HTTPURLResponse else { completion(nil); return }
            if http.statusCode != 200 {
                self.log("remote config: HTTP \(http.statusCode) from \(url)")
                completion(nil)
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                self.log("remote config: response was not a JSON object")
                completion(nil)
                return
            }
            completion(json)
        }.resume()
    }

    private func cache(_ config: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(config),
              let data = try? JSONSerialization.data(withJSONObject: config) else { return }
        try? data.write(to: cacheURL())
    }
}
