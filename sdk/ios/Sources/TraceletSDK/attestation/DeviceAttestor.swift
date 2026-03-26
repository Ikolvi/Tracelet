import Foundation
import DeviceCheck
import CryptoKit

/// Device attestation using Apple's App Attest API (iOS 14+).
///
/// Generates hardware-backed attestation tokens that prove the device
/// is genuine and the app binary has not been tampered with.
/// Tokens are cached and periodically refreshed.
public final class DeviceAttestor {

    private var cachedToken: [String: Any]?
    private var cachedTimestamp: Date?
    private var refreshTimer: Timer?
    private let cacheDuration: TimeInterval = 300 // 5 minutes

    /// Request an attestation token.
    ///
    /// Returns a cached token if still fresh, otherwise generates a new one.
    ///
    /// - Parameter completion: Called with the token dictionary, or nil if unavailable.
    func requestToken(completion: @escaping ([String: Any]?) -> Void) {
        // Return cached token if still fresh
        if let cached = cachedToken,
           let ts = cachedTimestamp,
           Date().timeIntervalSince(ts) < cacheDuration {
            completion(cached)
            return
        }

        guard #available(iOS 14.0, *) else {
            completion(nil)
            return
        }

        let service = DCAppAttestService.shared
        guard service.isSupported else {
            NSLog("[DeviceAttestor] App Attest not supported on this device")
            completion(nil)
            return
        }

        service.generateKey { [weak self] keyId, error in
            guard let keyId = keyId else {
                NSLog("[DeviceAttestor] Key generation failed: \(error?.localizedDescription ?? "unknown")")
                completion(nil)
                return
            }

            let challenge = self?.generateChallenge() ?? Data()
            let hash = Data(SHA256.hash(data: challenge))

            service.attestKey(keyId, clientDataHash: hash) { [weak self] attestation, error in
                guard let attestation = attestation else {
                    NSLog("[DeviceAttestor] Attestation failed: \(error?.localizedDescription ?? "unknown")")
                    completion(nil)
                    return
                }

                let result: [String: Any] = [
                    "token": attestation.base64EncodedString(),
                    "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                    "provider": "app_attest",
                    "verified": NSNull(),
                ]
                self?.cachedToken = result
                self?.cachedTimestamp = Date()
                completion(result)
            }
        }
    }

    /// Start periodic token refresh.
    ///
    /// - Parameter intervalSeconds: Refresh interval in seconds (minimum 60).
    func startRefresh(intervalSeconds: Int) {
        stopRefresh()
        let interval = max(60, intervalSeconds)
        DispatchQueue.main.async { [weak self] in
            self?.refreshTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(interval), repeats: true) { [weak self] _ in
                self?.requestToken { _ in /* cache update */ }
            }
        }
    }

    /// Stop periodic token refresh.
    func stopRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// Returns the last cached attestation token, or nil.
    func getCachedToken() -> [String: Any]? {
        return cachedToken
    }

    /// Generate a challenge for the attestation request.
    private func generateChallenge() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }
}
