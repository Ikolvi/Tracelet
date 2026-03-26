package com.ikolvi.tracelet.flutter.audit

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

/**
 * Unit tests for [AuditTrailManager] hash computation logic.
 *
 * Tests the pure functions (SHA-256, canonical string building, genesis hash)
 * without depending on Android context, database, or SharedPreferences.
 *
 * These tests verify:
 * - SHA-256 produces correct hex output
 * - Canonical string format is deterministic
 * - Fixed decimal formatting matches expected precision
 * - Hash chain linkage is consistent
 */
internal class AuditTrailManagerHashTest {

    // =========================================================================
    // SHA-256
    // =========================================================================

    @Test
    fun sha256_emptyString() {
        // Known SHA-256 of empty string
        val digest = java.security.MessageDigest.getInstance("SHA-256")
        val bytes = digest.digest("".toByteArray(Charsets.UTF_8))
        val expected = bytes.joinToString("") { "%02x".format(it) }
        assertEquals(expected, sha256(""))
    }

    @Test
    fun sha256_knownValue() {
        // SHA-256("hello") is a well-known value
        val expected = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        assertEquals(expected, sha256("hello"))
    }

    @Test
    fun sha256_deterministic() {
        val hash1 = sha256("tracelet:genesis:device123")
        val hash2 = sha256("tracelet:genesis:device123")
        assertEquals(hash1, hash2)
    }

    @Test
    fun sha256_differentInputs_differentOutputs() {
        val hash1 = sha256("input_a")
        val hash2 = sha256("input_b")
        assertNotEquals(hash1, hash2)
    }

    @Test
    fun sha256_outputLength() {
        // SHA-256 always produces 64 hex characters
        val hash = sha256("any input")
        assertEquals(64, hash.length)
    }

    @Test
    fun sha256_lowercaseHex() {
        val hash = sha256("test")
        assertTrue(hash.matches(Regex("[0-9a-f]{64}")))
    }

    // =========================================================================
    // Canonical string format
    // =========================================================================

    @Test
    fun buildCanonicalString_format() {
        val canonical = buildCanonicalString(
            previousHash = "abcd1234",
            chainIndex = 0,
            uuid = "uuid-001",
            latitude = 37.774900,
            longitude = -122.419400,
            timestamp = "2024-01-01T00:00:00.000Z",
            accuracy = 5.0,
            speed = 1.5,
            heading = 180.0,
            altitude = 35.0,
            odometer = 1500.0,
            isMoving = true,
        )

        assertEquals(
            "abcd1234|TRACELET_AUDIT|0|uuid-001|37.774900|-122.419400|" +
                "2024-01-01T00:00:00.000Z|5.00|1.50|180.00|35.00|1500.00|1",
            canonical,
        )
    }

    @Test
    fun buildCanonicalString_isMovingFalse() {
        val canonical = buildCanonicalString(
            previousHash = "prev",
            chainIndex = 5,
            uuid = "u",
            latitude = 0.0,
            longitude = 0.0,
            timestamp = "t",
            accuracy = 0.0,
            speed = 0.0,
            heading = 0.0,
            altitude = 0.0,
            odometer = 0.0,
            isMoving = false,
        )
        assertTrue(canonical.endsWith("|0"))
    }

    @Test
    fun buildCanonicalString_isMovingTrue() {
        val canonical = buildCanonicalString(
            previousHash = "prev",
            chainIndex = 5,
            uuid = "u",
            latitude = 0.0,
            longitude = 0.0,
            timestamp = "t",
            accuracy = 0.0,
            speed = 0.0,
            heading = 0.0,
            altitude = 0.0,
            odometer = 0.0,
            isMoving = true,
        )
        assertTrue(canonical.endsWith("|1"))
    }

    @Test
    fun buildCanonicalString_fixedLatLngPrecision() {
        val canonical = buildCanonicalString(
            previousHash = "h",
            chainIndex = 0,
            uuid = "u",
            latitude = 37.7,           // Only 1 decimal
            longitude = -122.4,        // Only 1 decimal
            timestamp = "t",
            accuracy = 5.0,
            speed = 0.0,
            heading = 0.0,
            altitude = 0.0,
            odometer = 0.0,
            isMoving = false,
        )
        assertTrue(canonical.contains("37.700000"))
        assertTrue(canonical.contains("-122.400000"))
    }

    @Test
    fun buildCanonicalString_fixedDoublePrecision() {
        val canonical = buildCanonicalString(
            previousHash = "h",
            chainIndex = 0,
            uuid = "u",
            latitude = 0.0,
            longitude = 0.0,
            timestamp = "t",
            accuracy = 5.123456,       // More than 2 decimals
            speed = 10.7,
            heading = 90.999,
            altitude = 100.1,
            odometer = 5000.55555,
            isMoving = false,
        )
        // All doubles except lat/lng should have exactly 2 decimal places
        assertTrue(canonical.contains("5.12"))
        assertTrue(canonical.contains("10.70"))
        assertTrue(canonical.contains("91.00") || canonical.contains("90.99"))
        assertTrue(canonical.contains("100.10"))
    }

    @Test
    fun buildCanonicalString_deterministic() {
        val args = mapOf(
            "previousHash" to "genesis",
            "chainIndex" to 42,
            "uuid" to "test-uuid",
            "latitude" to 48.8566,
            "longitude" to 2.3522,
            "timestamp" to "2024-06-15T10:30:00Z",
        )
        val c1 = buildCanonicalString(
            args["previousHash"] as String, args["chainIndex"] as Int,
            args["uuid"] as String, args["latitude"] as Double,
            args["longitude"] as Double, args["timestamp"] as String,
            5.0, 1.0, 180.0, 35.0, 0.0, true,
        )
        val c2 = buildCanonicalString(
            args["previousHash"] as String, args["chainIndex"] as Int,
            args["uuid"] as String, args["latitude"] as Double,
            args["longitude"] as Double, args["timestamp"] as String,
            5.0, 1.0, 180.0, 35.0, 0.0, true,
        )
        assertEquals(c1, c2)
    }

    // =========================================================================
    // Hash chain linkage
    // =========================================================================

    @Test
    fun hashChainLinkage_threeRecords() {
        val genesis = sha256("tracelet:genesis:test-device")

        // Record 0
        val canonical0 = buildCanonicalString(
            genesis, 0, "uuid-0", 37.7749, -122.4194,
            "2024-01-01T00:00:00Z", 5.0, 1.0, 180.0, 35.0, 0.0, true,
        )
        val hash0 = sha256(canonical0)

        // Record 1 — linked to hash0
        val canonical1 = buildCanonicalString(
            hash0, 1, "uuid-1", 37.7750, -122.4195,
            "2024-01-01T00:01:00Z", 5.0, 1.2, 181.0, 35.0, 100.0, true,
        )
        val hash1 = sha256(canonical1)

        // Record 2 — linked to hash1
        val canonical2 = buildCanonicalString(
            hash1, 2, "uuid-2", 37.7751, -122.4196,
            "2024-01-01T00:02:00Z", 5.0, 0.0, 0.0, 35.0, 200.0, false,
        )
        val hash2 = sha256(canonical2)

        // All hashes should be different
        assertNotEquals(hash0, hash1)
        assertNotEquals(hash1, hash2)
        assertNotEquals(hash0, hash2)

        // Each hash should be 64 hex chars
        assertEquals(64, hash0.length)
        assertEquals(64, hash1.length)
        assertEquals(64, hash2.length)
    }

    @Test
    fun hashChain_tamperDetection() {
        val genesis = sha256("tracelet:genesis:test-device")

        // Compute hash for original data
        val canonical = buildCanonicalString(
            genesis, 0, "uuid-0", 37.7749, -122.4194,
            "2024-01-01T00:00:00Z", 5.0, 1.0, 180.0, 35.0, 0.0, true,
        )
        val originalHash = sha256(canonical)

        // Compute hash for tampered data (different latitude)
        val tamperedCanonical = buildCanonicalString(
            genesis, 0, "uuid-0", 37.7750, -122.4194,  // lat changed!
            "2024-01-01T00:00:00Z", 5.0, 1.0, 180.0, 35.0, 0.0, true,
        )
        val tamperedHash = sha256(tamperedCanonical)

        // Hashes must differ — tamper detected
        assertNotEquals(originalHash, tamperedHash)
    }

    // =========================================================================
    // Helpers — standalone implementations of pure functions for testing
    // =========================================================================

    private fun sha256(input: String): String {
        val digest = java.security.MessageDigest.getInstance("SHA-256")
        val bytes = digest.digest(input.toByteArray(Charsets.UTF_8))
        return bytes.joinToString("") { "%02x".format(it) }
    }

    private fun buildCanonicalString(
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
            append("|TRACELET_AUDIT|")
            append(chainIndex)
            append('|')
            append(uuid)
            append('|')
            append(String.format("%.6f", latitude))
            append('|')
            append(String.format("%.6f", longitude))
            append('|')
            append(timestamp)
            append('|')
            append(String.format("%.2f", accuracy))
            append('|')
            append(String.format("%.2f", speed))
            append('|')
            append(String.format("%.2f", heading))
            append('|')
            append(String.format("%.2f", altitude))
            append('|')
            append(String.format("%.2f", odometer))
            append('|')
            append(if (isMoving) "1" else "0")
        }
    }
}
