package com.ikolvi.tracelet.sdk

import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import uniffi.tracelet_core.DatabaseManager
import java.io.File
import kotlin.test.assertEquals

/**
 * #280: end-to-end regression guard for the full write path through
 * [TraceletSdk.insertLocation]. A location tagged with a top-level
 * `locationSource` / `reducedAccuracy` (exactly what the live map builder and
 * `Tracelet.insertLocation(map)` provide) must survive persistence and come
 * back on [TraceletSdk.getLocations] — instead of the "unknown" / false
 * defaults. Complements the LocationMapper unit tests and the DB round-trip
 * test by covering the params -> route_context serialization step.
 */
@RunWith(RobolectricTestRunner::class)
class TraceletSdkLocationSourcePersistenceTest {

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
        tempFile = File.createTempFile("sdk_test_db", ".sqlite")
        db = DatabaseManager(tempFile.absolutePath)
        sdk = TraceletSdk.getInstance(ApplicationProvider.getApplicationContext())
        // Persistence gates on rustDatabase != null and getLocations() on
        // isReady; both are private, so inject them directly for the test
        // instead of running the full initialize() path.
        setPrivate("rustDatabase", db)
        setPrivate("isReady", true)
    }

    @After
    fun tearDown() {
        setPrivate("isReady", false)
        setPrivate("rustDatabase", null)
        db.close()
        tempFile.delete()
    }

    @Test
    fun insertLocation_topLevelLocationSource_survivesGetLocations() {
        sdk.insertLocation(
            mapOf(
                "uuid" to "issue-280",
                "timestamp" to "2026-06-08T10:00:00Z",
                "coords" to mapOf(
                    "latitude" to 37.7749,
                    "longitude" to -122.4194,
                    "accuracy" to 8.0,
                ),
                "locationSource" to "gps",
                "reducedAccuracy" to true,
            ),
        )

        val locations = sdk.getLocations(null)
        assertEquals(1, locations.size)
        assertEquals("gps", locations.first()["locationSource"])
        assertEquals(true, locations.first()["reducedAccuracy"])
    }

    @Test
    fun insertLocation_withoutLocationSource_readsBackDefaults() {
        sdk.insertLocation(
            mapOf(
                "uuid" to "issue-280-none",
                "timestamp" to "2026-06-08T11:30:00Z",
                "coords" to mapOf(
                    "latitude" to 37.0,
                    "longitude" to -122.0,
                    "accuracy" to 8.0,
                ),
            ),
        )

        val loc = sdk.getLocations(null).single()
        // Absent on the record -> LocationMapper leaves the keys unset and
        // Location.fromMap applies its "unknown" / false defaults.
        assertEquals(null, loc["locationSource"])
        assertEquals(null, loc["reducedAccuracy"])
    }
}
