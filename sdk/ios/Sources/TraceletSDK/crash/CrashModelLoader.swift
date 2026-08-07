import Foundation
import CryptoKit

/// Acquires + decrypts the opt-in crash ML model (#183) on iOS, or returns `nil`
/// so the SDK falls back to the rule-based detector. Never throws to the caller.
///
/// Mirrors the Android `CrashModelLoader`: use the cached **encrypted** blob if
/// present, else download it; verify the optional SHA-256; AES-256-GCM-decrypt
/// via the Rust core (`CrashModel.fromEncrypted`). Only the *encrypted* blob is
/// ever written to disk — the decrypted model lives in memory only.
public enum CrashModelLoader {
    /// Prefix shared by every cached model blob, so stale ones can be pruned.
    private static let cachePrefix = "tracelet_crash_model"

    /// AES-256-GCM decryption key (32 bytes), supplied at runtime by the host —
    /// injected from a build-time secret or fetched from a key endpoint. Never
    /// stored in this open-source repo. When unset, loading is skipped.
    public static var decryptionKey: Data?

    /// Optional host-supplied provider of an App Attest / DeviceCheck token for
    /// `prod` licenses during ``unlock``. Kept as a callback so the base SDK does
    /// not depend on attestation frameworks — apps that want production licensing
    /// supply it. `nil` ⇒ no token sent (fine for `dev` licenses).
    public static var integrityTokenProvider: (() -> String?)?

    /// Cache location for [url] (#314).
    ///
    /// Two fixes over the previous fixed-name-in-Application-Support scheme:
    ///
    /// - The filename is derived from the model **URL**. Cache invalidation used
    ///   to depend entirely on the optional `crashModelSha256`; that field is
    ///   only "recommended" and the unlock path may return no digest, so
    ///   repointing `crashModelUrl` at a new model kept loading the old blob
    ///   forever with no signal to the host.
    /// - `Library/Application Support` is **created if missing**. iOS does not
    ///   create it by default, so the best-effort `try?` write silently failed
    ///   and the model was re-downloaded on every `initBehaviorEngines()` — that
    ///   is, every `ready()` and every behaviour-config `setConfig()`.
    private static func cacheURL(for url: String) -> URL {
        return cacheDirectory().appendingPathComponent(cacheFileName(for: url))
    }

    private static func cacheFileName(for url: String) -> String {
        let digest = sha256Hex(Data(url.utf8)).prefix(16)
        return "\(cachePrefix)_\(digest).enc"
    }

    private static func cacheDirectory() -> URL {
        let fm = FileManager.default
        guard let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return fm.temporaryDirectory
        }
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        } catch {
            return fm.temporaryDirectory
        }
    }

    /// Deletes cached model blobs other than `keep` (#314).
    private static func pruneStaleCaches(keep: String) {
        let fm = FileManager.default
        let dir = cacheDirectory()
        guard let entries = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        for name in entries where name.hasPrefix(cachePrefix) && name != keep {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    /// Loads the model for [url], or `nil` to fall back to the rule engine.
    /// - Parameter sha256: optional hex digest of the encrypted blob, verified
    ///   after fetch; a mismatch discards the cache and returns `nil`.
    public static func load(url: String, sha256: String?, log: (String) -> Void = { _ in }) -> CrashModel? {
        guard let key = decryptionKey else {
            log("crash model: no decryption key set — using rule engine")
            return nil
        }
        if key.count != 32 {
            log("crash model: decryption key must be 32 bytes — using rule engine")
            return nil
        }
        let cache = cacheURL(for: url)
        // Drop blobs cached for any other model URL — only one model is ever
        // active, so keeping the others just wastes disk (#314).
        pruneStaleCaches(keep: cache.lastPathComponent)
        do {
            var blob = (try? Data(contentsOf: cache)).flatMap { $0.isEmpty ? nil : $0 }
            var fromCache = blob != nil
            if blob == nil {
                guard let downloaded = download(url) else {
                    log("crash model: download failed — using rule engine")
                    return nil
                }
                blob = downloaded
                writeCache(downloaded, to: cache, log: log)
            }
            guard var data = blob else { return nil }
            if let sha = sha256, sha256Hex(data).lowercased() != sha.lowercased() {
                // Cache is stale (e.g. a new model version was published with a
                // fresh digest). Re-download once so the new model loads in this
                // same session instead of falling back for a cycle (#183).
                if fromCache {
                    log("crash model: cached blob is stale — re-downloading new version")
                    try? FileManager.default.removeItem(at: cache)
                    guard let downloaded = download(url) else {
                        log("crash model: download failed — using rule engine")
                        return nil
                    }
                    data = downloaded
                    writeCache(downloaded, to: cache, log: log)
                    fromCache = false
                }
                if sha256Hex(data).lowercased() != sha.lowercased() {
                    log("crash model: SHA-256 mismatch — discarding cache, using rule engine")
                    try? FileManager.default.removeItem(at: cache)
                    return nil
                }
            }
            let model = try CrashModel.fromEncrypted(blob: data, key: key)
            log("crash model: loaded (\(model.treeCount()) trees)")
            return model
        } catch {
            log("crash model: load failed (\(error)) — using rule engine")
            return nil
        }
    }

    /// The model URL + integrity digest returned by a successful ``unlock``.
    public struct Unlocked {
        public let url: String
        public let sha256: String?
    }

    /// Calls a licensing endpoint (the crash-model unlock Worker, #183) to obtain
    /// the AES decryption key for a valid [licenseKey], sets ``decryptionKey``, and
    /// returns the model URL + sha to pass into ``load``. The key is held in memory
    /// only. Returns `nil` on any failure (offline, invalid/expired/revoked
    /// license) so the caller falls back to the rule engine.
    public static func unlock(
        unlockUrl: String,
        licenseKey: String,
        integrityToken: String? = nil,
        log: (String) -> Void = { _ in }
    ) -> Unlocked? {
        guard let endpoint = URL(string: unlockUrl) else { return nil }
        var body: [String: Any] = ["licenseKey": licenseKey]
        if let token = integrityToken { body["integrityToken"] = token }
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = payload
        req.timeoutInterval = 30

        guard let (data, status) = syncDataTask(req), status == 200 else {
            log("crash model: unlock failed — using rule engine")
            return nil
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let keyB64 = json["key"] as? String,
            let modelUrl = json["url"] as? String,
            let keyBytes = Data(base64Encoded: keyB64)
        else {
            log("crash model: unlock response missing key/url — using rule engine")
            return nil
        }
        if keyBytes.count != 32 {
            log("crash model: unlock key not 32 bytes — using rule engine")
            return nil
        }
        decryptionKey = keyBytes
        log("crash model: unlocked (\(json["scope"] as? String ?? "?"))")
        return Unlocked(url: modelUrl, sha256: json["sha256"] as? String)
    }

    // MARK: - Private

    /// Caches the encrypted blob, reporting rather than swallowing a failure
    /// (#314) — a silent miss here costs a full re-download on every load.
    private static func writeCache(_ data: Data, to cache: URL, log: (String) -> Void) {
        do {
            try data.write(to: cache)
        } catch {
            log("crash model: could not cache blob (\(error)) — will re-download next load")
        }
    }

    private static func download(_ url: String) -> Data? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u)
        req.timeoutInterval = 30
        guard let (data, status) = syncDataTask(req), status == 200 else { return nil }
        return data
    }

    /// Runs a URLSession data task synchronously (loader runs on a background
    /// queue, matching the Android thread model).
    private static func syncDataTask(_ req: URLRequest) -> (Data, Int)? {
        let sem = DispatchSemaphore(value: 0)
        var result: (Data, Int)?
        URLSession.shared.dataTask(with: req) { data, response, _ in
            if let data = data, let http = response as? HTTPURLResponse {
                result = (data, http.statusCode)
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 35)
        return result
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
