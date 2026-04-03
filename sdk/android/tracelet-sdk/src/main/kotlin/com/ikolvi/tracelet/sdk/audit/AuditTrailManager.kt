package com.ikolvi.tracelet.sdk.audit

import android.content.Context
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.db.TraceletDatabase
import java.security.MessageDigest
import java.util.Locale

/**
 * **[Enterprise]** Tamper-proof location audit trail manager.
 *
 * Creates a SHA-256 hash chain over persisted location records. Each record's
 * hash is computed from the previous record's hash and a canonical representation
 * of the location data. The chain can be verified to prove that no records were
 * inserted, deleted, or modified.
 *
 * ## Hash Computation
 *
 * ```
 * genesis  = SHA256("tracelet:genesis:" + deviceId)
 * hash[i]  = SHA256(hash[i-1] + "|TRACELET_AUDIT|" + chainIndex + "|" +
 *            uuid + "|" + lat6 + "|" + lng6 + "|" + timestamp + "|" +
 *            accuracy2 + "|" + speed2 + "|" + heading2 + "|" + altitude2 + "|" +
 *            odometer2 + "|" + isMoving01)
 * ```
 *
 * All floating-point values are formatted to fixed decimal places to ensure
 * cross-platform (Android/iOS/server) hash consistency.
 */
class AuditTrailManager(
    private val context: Context,
    private val database: TraceletDatabase,
    private val configManager: ConfigManager,
) {

    companion object {
        private const val PREFS_NAME = "com.tracelet.audit"
        private const val KEY_CHAIN_INDEX = "chain_index"
        private const val KEY_LATEST_HASH = "latest_hash"
        private const val SEPARATOR = "|TRACELET_AUDIT|"
        private val HEX_CHARS = "0123456789abcdef".toCharArray()
    }

    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** Thread-local MessageDigest — not thread-safe, so each thread gets its own. */
    private val digestLocal = ThreadLocal.withInitial {
        MessageDigest.getInstance("SHA-256")
    }

    /** Current chain index (next record will get this index). */
    private var chainIndex: Int
        get() = prefs.getInt(KEY_CHAIN_INDEX, 0)
        set(value) = prefs.edit().putInt(KEY_CHAIN_INDEX, value).apply()

    /** The latest hash in the chain. */
    private var latestHash: String
        get() = prefs.getString(KEY_LATEST_HASH, null) ?: computeGenesisHash()
        set(value) = prefs.edit().putString(KEY_LATEST_HASH, value).apply()

    /** Whether audit trail is enabled in the current config. */
    fun isEnabled(): Boolean = configManager.getAuditEnabled()

    // =========================================================================
    // Hash computation
    // =========================================================================

    /**
     * Computes the genesis hash for this device.
     *
     * Uses `android.os.Build.FINGERPRINT` as a device-specific seed, ensuring
     * the genesis hash is unique per device but reproducible for verification.
     */
    fun computeGenesisHash(): String {
        val deviceId = android.os.Build.FINGERPRINT
        return sha256("tracelet:genesis:$deviceId")
    }

    /**
     * Computes the canonical string for a location record.
     *
     * Fixed decimal formatting ensures identical hashes across platforms:
     * - Coordinates: 6 decimal places (~11cm precision)
     * - Speed/heading/altitude/accuracy/odometer: 2 decimal places
     */
    fun buildCanonicalString(
        previousHash: String,
        chainIndex: Int,
        uuid: String,
        latitude: Double,
        longitude: Double,
        timestamp: String,
        accuracy: Double,
        speed: Double,
        heading: Double,
        altitude: Double,
        odometer: Double,
        isMoving: Boolean,
    ): String {
        return buildString {
            append(previousHash)
            append(SEPARATOR)
            append(chainIndex)
            append('|')
            append(uuid)
            append('|')
            append(String.format(Locale.US, "%.6f", latitude))
            append('|')
            append(String.format(Locale.US, "%.6f", longitude))
            append('|')
            append(timestamp)
            append('|')
            append(String.format(Locale.US, "%.2f", accuracy))
            append('|')
            append(String.format(Locale.US, "%.2f", speed))
            append('|')
            append(String.format(Locale.US, "%.2f", heading))
            append('|')
            append(String.format(Locale.US, "%.2f", altitude))
            append('|')
            append(String.format(Locale.US, "%.2f", odometer))
            append('|')
            append(if (isMoving) "1" else "0")
        }
    }

    /**
     * Computes SHA-256 hex digest.
     */
    fun sha256(input: String): String {
        val bytes = digestLocal.get()!!.digest(input.toByteArray(Charsets.UTF_8))
        // Pre-built hex lookup avoids 32 per-byte String.format calls (A-M3).
        val sb = StringBuilder(bytes.size * 2)
        for (b in bytes) {
            val i = b.toInt() and 0xFF
            sb.append(HEX_CHARS[i ushr 4])
            sb.append(HEX_CHARS[i and 0x0F])
        }
        return sb.toString()
    }

    // =========================================================================
    // Chain operations
    // =========================================================================

    /**
     * Appends a location to the audit chain.
     *
     * Computes the hash from the location's canonical fields and the previous
     * hash, stores it in the `audit_trail` table, and updates the chain state.
     *
     * @param locationMap The enriched location map (same format as DB insert).
     * @return A map with `audit_hash`, `audit_previous_hash`, `audit_chain_index`
     *         to be merged into the location record, or `null` if audit is disabled.
     */
    fun appendToChain(locationMap: Map<String, Any?>): Map<String, Any?>? {
        if (!isEnabled()) return null

        val previousHash = latestHash
        val index = chainIndex

        // Extract canonical fields from the enriched location map
        val uuid = locationMap["uuid"] as? String ?: return null
        val latitude = (locationMap["latitude"] as? Number)?.toDouble() ?: 0.0
        val longitude = (locationMap["longitude"] as? Number)?.toDouble() ?: 0.0
        val timestamp = locationMap["timestamp"]?.toString() ?: ""
        val accuracy = (locationMap["accuracy"] as? Number)?.toDouble() ?: 0.0
        val speed = (locationMap["speed"] as? Number)?.toDouble() ?: 0.0
        val heading = (locationMap["heading"] as? Number)?.toDouble() ?: 0.0
        val altitude = (locationMap["altitude"] as? Number)?.toDouble() ?: 0.0
        val odometer = (locationMap["odometer"] as? Number)?.toDouble() ?: 0.0
        val isMoving = (locationMap["is_moving"] ?: locationMap["isMoving"]) == true

        val canonical = buildCanonicalString(
            previousHash, index, uuid,
            latitude, longitude, timestamp,
            accuracy, speed, heading, altitude,
            odometer, isMoving,
        )
        val hash = sha256(canonical)

        // Store in audit_trail table
        database.insertAuditRecord(uuid, hash, previousHash, index)

        // Update chain state
        latestHash = hash
        chainIndex = index + 1

        return mapOf(
            "audit_hash" to hash,
            "audit_previous_hash" to previousHash,
            "audit_chain_index" to index,
        )
    }

    /**
     * Verifies the entire audit trail chain.
     *
     * Walks all records in chain-index order, re-computes each hash, and
     * compares to the stored hash. Returns a verification result map.
     */
    fun verifyChain(): Map<String, Any?> {
        val records = database.getAuditTrailWithLocations()
        if (records.isEmpty()) {
            return mapOf(
                "isValid" to true,
                "totalRecords" to 0,
                "verifiedRecords" to 0,
            )
        }

        var expectedPreviousHash = computeGenesisHash()
        var verified = 0

        for (record in records) {
            val storedHash = record["hash"] as? String ?: ""
            val storedPreviousHash = record["previous_hash"] as? String ?: ""
            val recordChainIndex = (record["chain_index"] as? Number)?.toInt() ?: -1

            // Verify chain linkage
            if (storedPreviousHash != expectedPreviousHash) {
                return mapOf(
                    "isValid" to false,
                    "totalRecords" to records.size,
                    "verifiedRecords" to verified,
                    "brokenAtIndex" to recordChainIndex,
                    "brokenAtUuid" to (record["uuid"] as? String),
                    "error" to "missing link: expected previousHash=$expectedPreviousHash, got=$storedPreviousHash",
                )
            }

            // Check location data exists (fetched via JOIN)
            val hasLocation = record["has_location"] == true
            if (!hasLocation) {
                return mapOf(
                    "isValid" to false,
                    "totalRecords" to records.size,
                    "verifiedRecords" to verified,
                    "brokenAtIndex" to recordChainIndex,
                    "brokenAtUuid" to (record["uuid"] as? String),
                    "error" to "missing location record",
                )
            }

            val canonical = buildCanonicalString(
                storedPreviousHash,
                recordChainIndex,
                record["uuid"] as? String ?: "",
                (record["latitude"] as? Number)?.toDouble() ?: 0.0,
                (record["longitude"] as? Number)?.toDouble() ?: 0.0,
                record["timestamp"]?.toString() ?: "",
                (record["accuracy"] as? Number)?.toDouble() ?: 0.0,
                (record["speed"] as? Number)?.toDouble() ?: 0.0,
                (record["heading"] as? Number)?.toDouble() ?: 0.0,
                (record["altitude"] as? Number)?.toDouble() ?: 0.0,
                (record["odometer"] as? Number)?.toDouble() ?: 0.0,
                record["is_moving"] == true || record["isMoving"] == true,
            )
            val computedHash = sha256(canonical)

            if (computedHash != storedHash) {
                return mapOf(
                    "isValid" to false,
                    "totalRecords" to records.size,
                    "verifiedRecords" to verified,
                    "brokenAtIndex" to recordChainIndex,
                    "brokenAtUuid" to (record["uuid"] as? String),
                    "error" to "hash mismatch: expected=$computedHash, stored=$storedHash",
                )
            }

            expectedPreviousHash = storedHash
            verified++
        }

        return mapOf(
            "isValid" to true,
            "totalRecords" to records.size,
            "verifiedRecords" to verified,
        )
    }

    /**
     * Gets the audit proof for a specific location record.
     *
     * @return A map with `uuid`, `hash`, `previous_hash`, `chain_index`, `timestamp`,
     *         or `null` if not found.
     */
    fun getProof(uuid: String): Map<String, Any?>? {
        return database.getAuditRecord(uuid)
    }

    /**
     * Resets the audit chain state (e.g. after [Tracelet.reset()]).
     */
    fun reset() {
        prefs.edit().clear().apply()
    }
}
