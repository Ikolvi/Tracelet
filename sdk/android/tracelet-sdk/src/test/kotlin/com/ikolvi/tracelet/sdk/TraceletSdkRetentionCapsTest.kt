package com.ikolvi.tracelet.sdk

import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import uniffi.tracelet_core.DatabaseManager
import java.io.File
import java.time.Instant
import java.time.temporal.ChronoUnit
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * #361: end-to-end guard that `maxRecordsToPersist` and `maxDaysToPersist` are
 * enforced against `location_events`, not merely accepted and echoed back.
 *
 * Drives [TraceletSdk.insertLocation] — the single funnel every persisted
 * location goes through, and the exact API the reporter used — rather than the
 * Rust `DatabaseManager` methods directly, so it covers the config read and the
 * amortization window as well as the SQL. The `DatabaseManager` unit tests cover
 * the delete semantics themselves.
 */
@RunWith(RobolectricTestRunner::class)
class TraceletSdkRetentionCapsTest {

    private lateinit var sdk: TraceletSdk
    private lateinit var tempFile: File
    private lateinit var db: DatabaseManager

    private fun setPrivate(name: String, value: Any?) {
        val field = TraceletSdk::class.java.getDeclaredField(name)
        field.isAccessible = true
        field.set(sdk, value)
    }

    @Before
    fun setUp() {
        tempFile = File.createTempFile("retention_test_db", ".sqlite")
        db = DatabaseManager(tempFile.absolutePath)
        sdk = TraceletSdk.getInstance(ApplicationProvider.getApplicationContext())
        setPrivate("rustDatabase", db)
        setPrivate("isReady", true)
        // The insert counter is process-scoped and the SDK is a singleton, so a
        // previous test's inserts would otherwise shift which insert prunes.
        setPrivate("locationInsertsSeen", 0L)
        sdk.configManager.reset(null)
    }

    @After
    fun tearDown() {
        setPrivate("isReady", false)
        setPrivate("rustDatabase", null)
        sdk.configManager.reset(null)
        db.close()
        tempFile.delete()
    }

    /** Inserts a location whose fix time is [minutesAgo] minutes in the past. */
    private fun insert(uuid: String, minutesAgo: Long = 0) {
        sdk.insertLocation(
            mapOf(
                "uuid" to uuid,
                "timestamp" to Instant.now().minus(minutesAgo, ChronoUnit.MINUTES).toString(),
                "coords" to mapOf(
                    "latitude" to 37.7749,
                    "longitude" to -122.4194,
                    "accuracy" to 8.0,
                ),
            ),
        )
    }

    /**
     * The reporter's `maxRecordsToPersist: 3` case. Pruning is amortized over
     * [TraceletSdk] `PRUNE_EVERY_N_INSERTS` inserts, so the cap is applied on the
     * 1st insert and again on the 101st — the queue is bounded by
     * `cap + window`, and is cut back to the cap itself at each prune.
     */
    @Test
    fun insertLocation_enforcesMaxRecordsToPersist() {
        sdk.configManager.setConfig(mapOf("persistence" to mapOf("maxRecordsToPersist" to 3)))
        assertEquals(3, sdk.configManager.getMaxRecordsToPersist(), "config precondition")

        repeat(100) { insert("cap-$it") }
        // Before the window closes the queue is still growing — this is the
        // documented amortization, not the unbounded growth of the bug.
        assertEquals(100, db.getLocationsCount(), "queue grows within the prune window")

        insert("cap-100")
        assertEquals(3, db.getLocationsCount(), "the 101st insert applies the cap")

        // The survivors are the newest, so the queue keeps the freshest data.
        val kept = sdk.getLocations(null).mapNotNull { it["uuid"] as? String }
        assertTrue(kept.contains("cap-100"), "newest record must survive: $kept")
        assertTrue(kept.none { it == "cap-0" }, "oldest record must be evicted: $kept")
    }

    /**
     * `-1` is the documented "unlimited" sentinel and must not be read as a cap
     * of zero — the failure mode that would turn this fix into data loss.
     */
    @Test
    fun insertLocation_treatsNegativeCapsAsUnlimited() {
        sdk.configManager.setConfig(
            mapOf(
                "persistence" to mapOf(
                    "maxRecordsToPersist" to -1,
                    "maxDaysToPersist" to -1,
                ),
            ),
        )

        repeat(101) { insert("unlimited-$it", minutesAgo = 60L * 24 * 30) }

        assertEquals(101, db.getLocationsCount(), "-1 must retain everything")
    }

    /**
     * The reporter's `maxDaysToPersist` case: a fixture older than the window is
     * purged by age, and a fresh one is not.
     */
    @Test
    fun insertLocation_enforcesMaxDaysToPersist() {
        sdk.configManager.setConfig(mapOf("persistence" to mapOf("maxDaysToPersist" to 1)))
        assertEquals(1, sdk.configManager.getMaxDaysToPersist(), "config precondition")

        // Step past the first-insert prune so both fixtures land before the next
        // one, making the assertion below about the prune and not about arrival.
        setPrivate("locationInsertsSeen", 1L)

        // Two days old, and one from now.
        insert("aged", minutesAgo = 60L * 24 * 2)
        insert("fresh")
        assertEquals(2, db.getLocationsCount(), "both rows land before the next prune")

        // Reset the counter so the next insert is a pruning one, instead of
        // padding the test out to 101 inserts.
        setPrivate("locationInsertsSeen", 0L)
        insert("trigger")

        val kept = sdk.getLocations(null).mapNotNull { it["uuid"] as? String }
        assertEquals(setOf("fresh", "trigger"), kept.toSet(), "only the aged row should go")
    }

    /**
     * The first insert of the process prunes, so a queue inherited from a build
     * that never enforced the caps is cut down on the next fix rather than after
     * another full window of inserts. This is the upgrade path for anyone who has
     * been running with the bug.
     */
    @Test
    fun insertLocation_prunesAnInheritedBacklogOnTheFirstInsert() {
        sdk.configManager.setConfig(mapOf("persistence" to mapOf("maxDaysToPersist" to 1)))

        // Seeded straight through the DB so the SDK's insert counter stays at 0,
        // standing in for rows persisted by a version without enforcement.
        val stale = Instant.now().minus(30, ChronoUnit.DAYS).toString()
        repeat(10) {
            db.insertLocation(
                "backlog-$it", 37.0, -122.0, 8.0, 0.0, 0.0, 0.0, false, false,
                "unknown", -1, null, stale, "location", null, null,
            )
        }
        assertEquals(10, db.getLocationsCount(), "backlog precondition")

        insert("first-fix-after-upgrade")

        val kept = sdk.getLocations(null).mapNotNull { it["uuid"] as? String }
        assertEquals(listOf("first-fix-after-upgrade"), kept, "backlog should be cleared")
    }
}
