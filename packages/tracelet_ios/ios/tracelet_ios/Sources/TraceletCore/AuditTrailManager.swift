import CommonCrypto
import Foundation
import UIKit

/// Manages a tamper-proof SHA-256 hash chain over location records.
///
/// Each location is hashed with its predecessor's hash, forming a
/// blockchain-like chain of custody. Breaking any link invalidates
/// all subsequent records, making tampering detectable.
///
/// Thread-safe: all chain-state mutations are serialized through
/// the TraceletDatabase queue.
public final class AuditTrailManager {
    private let database: TraceletDatabase
    private let configManager: ConfigManager

    /// Current chain index — auto-incremented per record.
    private var chainIndex: Int
    /// Hash of the most recent record in the chain.
    private var latestHash: String

    private let defaults = UserDefaults.standard
    private let prefsKey = "com.tracelet.audit"

    public init(database: TraceletDatabase, configManager: ConfigManager) {
        self.database = database
        self.configManager = configManager

        // Restore persisted chain state
        let prefs = defaults.dictionary(forKey: prefsKey) ?? [:]
        self.chainIndex = prefs["chain_index"] as? Int ?? -1
        self.latestHash = prefs["latest_hash"] as? String ?? ""

        // If no chain exists yet, compute genesis hash
        if latestHash.isEmpty {
            latestHash = computeGenesisHash()
        }
    }

    // MARK: - Public API

    /// Appends a location to the audit chain.
    ///
    /// - Parameter locationMap: The enriched location map (with nested coords,
    ///   activity, battery sub-dicts).
    /// - Returns: A dictionary with `audit_hash`, `audit_previous_hash`,
    ///   `audit_chain_index` to merge into the location map, or `nil` if
    ///   auditing is disabled.
    public func appendToChain(_ locationMap: [String: Any]) -> [String: Any]? {
        guard configManager.getAuditEnabled() else { return nil }

        let previousHash = latestHash
        chainIndex += 1
        let currentIndex = chainIndex

        let canonical = buildCanonicalString(
            previousHash: previousHash,
            chainIndex: currentIndex,
            location: locationMap
        )
        let hash = sha256(canonical)

        // Persist to audit_trail table
        let uuid = locationMap["uuid"] as? String ?? ""
        database.insertAuditRecord(
            uuid: uuid,
            hash: hash,
            previousHash: previousHash,
            chainIndex: currentIndex
        )

        // Update chain state
        latestHash = hash
        persistChainState()

        return [
            "audit_hash": hash,
            "audit_previous_hash": previousHash,
            "audit_chain_index": currentIndex,
        ]
    }

    /// Verifies the entire audit chain from genesis to the latest record.
    ///
    /// Re-computes every hash and checks that each record's `previous_hash`
    /// matches the prior record's `hash`.
    ///
    /// - Returns: A verification result map compatible with
    ///   `AuditVerification.fromMap()`.
    public func verifyChain() -> [String: Any] {
        let records = database.getAuditTrail()

        if records.isEmpty {
            return [
                "is_valid": true,
                "total_records": 0,
                "verified_records": 0,
            ]
        }

        let genesis = computeGenesisHash()
        var expectedPreviousHash = genesis

        for (i, record) in records.enumerated() {
            let storedHash = record["hash"] as? String ?? ""
            let storedPrevious = record["previous_hash"] as? String ?? ""
            let storedIndex = record["chain_index"] as? Int ?? -1
            let uuid = record["uuid"] as? String ?? ""

            // 1. Check chain linkage
            if storedPrevious != expectedPreviousHash {
                return [
                    "is_valid": false,
                    "total_records": records.count,
                    "verified_records": i,
                    "broken_at_index": storedIndex,
                    "broken_at_uuid": uuid,
                    "error": "Chain linkage broken at index \(storedIndex): expected previous_hash \(expectedPreviousHash) but found \(storedPrevious)",
                ]
            }

            // 2. Fetch the location data for this record
            guard let locationFlat = database.getLocationForAudit(uuid: uuid) else {
                return [
                    "is_valid": false,
                    "total_records": records.count,
                    "verified_records": i,
                    "broken_at_index": storedIndex,
                    "broken_at_uuid": uuid,
                    "error": "Location data missing for uuid \(uuid) at chain index \(storedIndex)",
                ]
            }

            // 3. Re-compute hash
            let canonical = buildCanonicalString(
                previousHash: storedPrevious,
                chainIndex: storedIndex,
                location: locationFlat
            )
            let recomputed = sha256(canonical)

            if recomputed != storedHash {
                return [
                    "is_valid": false,
                    "total_records": records.count,
                    "verified_records": i,
                    "broken_at_index": storedIndex,
                    "broken_at_uuid": uuid,
                    "error": "Hash mismatch at index \(storedIndex): expected \(recomputed) but found \(storedHash)",
                ]
            }

            expectedPreviousHash = storedHash
        }

        return [
            "is_valid": true,
            "total_records": records.count,
            "verified_records": records.count,
        ]
    }

    /// Returns an audit proof for a specific location UUID.
    ///
    /// - Parameter uuid: The location UUID.
    /// - Returns: An audit proof map, or `nil` if the UUID has no audit record.
    public func getProof(uuid: String) -> [String: Any]? {
        return database.getAuditRecord(uuid: uuid)
    }

    /// Resets the audit chain — deletes all audit records and resets chain state.
    public func reset() {
        database.deleteAllAuditRecords()
        chainIndex = -1
        latestHash = computeGenesisHash()
        persistChainState()
    }

    // MARK: - Internal

    /// Builds the canonical string for hashing.
    ///
    /// Format: `previousHash|TRACELET_AUDIT|chainIndex|uuid|lat6|lng6|timestamp|
    ///          accuracy2|speed2|heading2|altitude2|odometer2|isMoving01`
    ///
    /// Fixed decimal places guarantee cross-platform consistency with the
    /// Android implementation.
    private func buildCanonicalString(
        previousHash: String,
        chainIndex: Int,
        location: [String: Any]
    ) -> String {
        // Support both flat and nested location maps
        let coords = location["coords"] as? [String: Any]
        let lat = coords?["latitude"] as? Double ?? location["latitude"] as? Double ?? 0.0
        let lng = coords?["longitude"] as? Double ?? location["longitude"] as? Double ?? 0.0
        let altitude = coords?["altitude"] as? Double ?? location["altitude"] as? Double ?? 0.0
        let speed = coords?["speed"] as? Double ?? location["speed"] as? Double ?? -1.0
        let heading = coords?["heading"] as? Double ?? location["heading"] as? Double ?? -1.0
        let accuracy = coords?["accuracy"] as? Double ?? location["accuracy"] as? Double ?? -1.0

        let uuid = location["uuid"] as? String ?? ""
        let timestamp = location["timestamp"] as? String ?? ""
        let odometer = location["odometer"] as? Double ?? 0.0

        let isMoving: Bool
        if let moving = location["is_moving"] as? Bool {
            isMoving = moving
        } else if let moving = location["is_moving"] as? Int {
            isMoving = moving == 1
        } else {
            isMoving = false
        }

        return [
            previousHash,
            "TRACELET_AUDIT",
            "\(chainIndex)",
            uuid,
            String(format: "%.6f", lat),
            String(format: "%.6f", lng),
            timestamp,
            String(format: "%.2f", accuracy),
            String(format: "%.2f", speed),
            String(format: "%.2f", heading),
            String(format: "%.2f", altitude),
            String(format: "%.2f", odometer),
            isMoving ? "1" : "0",
        ].joined(separator: "|")
    }

    /// SHA-256 hash of a string, returned as lowercase hex.
    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Compute genesis hash from a stable device identifier.
    ///
    /// Uses `identifierForVendor` which persists across app launches
    /// but changes on reinstall — which is correct behavior since a
    /// reinstall resets the chain anyway.
    private func computeGenesisHash() -> String {
        let vendorId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown-device"
        return sha256("tracelet:genesis:\(vendorId)")
    }

    /// Persist chain index and latest hash to UserDefaults.
    private func persistChainState() {
        defaults.set([
            "chain_index": chainIndex,
            "latest_hash": latestHash,
        ], forKey: prefsKey)
    }
}
