package com.ikolvi.tracelet.flutter.db

import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.sdk.db.TraceletDatabase
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * Tests for [TraceletDatabase] migration from v3 → v4.
 *
 * Simulates an existing v3 database (without the `vertices` column),
 * inserts data, then opens the database at v4 to verify:
 * - Existing circular geofences survive the migration unchanged.
 * - The `vertices` column is added via `ALTER TABLE`.
 * - Polygon geofences can be inserted after migration.
 *
 * Uses Robolectric for in-memory SQLite context.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
internal class TraceletDatabaseMigrationTest {

    @Before
    fun setUp() {
        resetSingleton()
    }

    @After
    fun tearDown() {
        resetSingleton()
    }

    private fun resetSingleton() {
        val field = TraceletDatabase::class.java.getDeclaredField("instance")
        field.isAccessible = true
        (field.get(null) as? TraceletDatabase)?.close()
        field.set(null, null)
    }

    /**
     * Creates a v3 schema database manually (without the vertices column),
     * inserts a circular geofence, then opens via [TraceletDatabase] (v4)
     * to trigger onUpgrade. Verifies the geofence survives and vertices
     * column is available.
     */
    @Test
    fun migration_v3ToV4_preservesExistingGeofences() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()

        // Step 1: Create a v3 database manually
        val dbPath = context.getDatabasePath("tracelet.db").path
        context.getDatabasePath("tracelet.db").parentFile?.mkdirs()
        val rawDb = SQLiteDatabase.openOrCreateDatabase(dbPath, null)

        // Create the geofences table WITHOUT vertices column (v3 schema)
        rawDb.execSQL("""
            CREATE TABLE geofences (
                identifier TEXT PRIMARY KEY,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                radius REAL NOT NULL,
                notify_on_entry INTEGER DEFAULT 1,
                notify_on_exit INTEGER DEFAULT 1,
                notify_on_dwell INTEGER DEFAULT 0,
                loitering_delay INTEGER DEFAULT 0,
                gf_extras TEXT
            )
        """.trimIndent())

        // Also create the other tables that a v3 DB would have
        rawDb.execSQL("""
            CREATE TABLE locations (
                uuid TEXT PRIMARY KEY,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                altitude REAL DEFAULT 0,
                speed REAL DEFAULT 0,
                heading REAL DEFAULT 0,
                accuracy REAL DEFAULT 0,
                speed_accuracy REAL DEFAULT -1,
                heading_accuracy REAL DEFAULT -1,
                altitude_accuracy REAL DEFAULT -1,
                timestamp INTEGER NOT NULL,
                is_moving INTEGER DEFAULT 0,
                odometer REAL DEFAULT 0,
                activity_type TEXT,
                activity_confidence INTEGER DEFAULT -1,
                battery_level REAL DEFAULT -1,
                battery_charging INTEGER DEFAULT 0,
                event TEXT,
                extras TEXT,
                synced INTEGER DEFAULT 0,
                created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
            )
        """.trimIndent())
        rawDb.execSQL("CREATE TABLE logs (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL, level TEXT NOT NULL, message TEXT NOT NULL, tag TEXT DEFAULT 'tracelet')")
        rawDb.execSQL("""
            CREATE TABLE audit_trail (
                uuid TEXT PRIMARY KEY,
                hash TEXT NOT NULL,
                previous_hash TEXT NOT NULL,
                chain_index INTEGER NOT NULL UNIQUE,
                created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
            )
        """.trimIndent())
        rawDb.execSQL("""
            CREATE TABLE privacy_zones (
                identifier TEXT PRIMARY KEY,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                radius REAL NOT NULL,
                action INTEGER NOT NULL DEFAULT 0,
                degraded_accuracy REAL DEFAULT 1000.0
            )
        """.trimIndent())

        // Insert a circular geofence using v3 schema
        val values = ContentValues().apply {
            put("identifier", "existing-circle")
            put("latitude", 48.8566)
            put("longitude", 2.3522)
            put("radius", 500.0)
            put("notify_on_entry", 1)
            put("notify_on_exit", 1)
            put("notify_on_dwell", 0)
            put("loitering_delay", 0)
        }
        rawDb.insert("geofences", null, values)

        // Set the version to 3
        rawDb.version = 3
        rawDb.close()

        // Step 2: Open via TraceletDatabase (v4) — triggers onUpgrade
        val db = TraceletDatabase.getInstance(context)

        // Step 3: Verify the DB is now at the latest version
        assertEquals(5, db.readableDatabase.version)

        // Step 4: Verify the existing geofence survived migration
        val existing = db.getGeofence("existing-circle")
        assertNotNull(existing, "Existing geofence should survive v3→v4 migration")
        assertEquals("existing-circle", existing["identifier"])
        assertEquals(48.8566, existing["latitude"])
        assertEquals(2.3522, existing["longitude"])
        assertEquals(500.0, existing["radius"])
        assertTrue(!existing.containsKey("vertices"), "Pre-migration circular geofence should not have vertices")

        // Step 5: Verify polygon geofences can now be inserted
        val polygon = mapOf<String, Any?>(
            "identifier" to "new-polygon",
            "latitude" to 37.77,
            "longitude" to -122.42,
            "radius" to 0.0,
            "vertices" to listOf(
                listOf(37.78, -122.42),
                listOf(37.77, -122.41),
                listOf(37.76, -122.43),
            ),
        )
        assertTrue(db.insertGeofence(polygon))

        val result = db.getGeofence("new-polygon")
        assertNotNull(result)
        @Suppress("UNCHECKED_CAST")
        val v = result["vertices"] as? List<List<Double>>
        assertNotNull(v, "Polygon vertices should persist after migration")
        assertEquals(3, v.size)

        db.close()
    }

    /**
     * Verifies that the vertices column exists after a fresh v4 install
     * (no migration needed — column is in CREATE TABLE).
     */
    @Test
    fun freshInstall_v4_hasVerticesColumn() {
        val db = TraceletDatabase.getInstance(ApplicationProvider.getApplicationContext())

        // Fresh install: insert polygon geofence directly
        val polygon = mapOf<String, Any?>(
            "identifier" to "fresh-polygon",
            "latitude" to 51.5074,
            "longitude" to -0.1278,
            "radius" to 0.0,
            "vertices" to listOf(
                listOf(51.51, -0.12),
                listOf(51.50, -0.13),
                listOf(51.49, -0.11),
            ),
        )
        assertTrue(db.insertGeofence(polygon))

        val result = db.getGeofence("fresh-polygon")
        assertNotNull(result)
        @Suppress("UNCHECKED_CAST")
        val v = result["vertices"] as? List<List<Double>>
        assertNotNull(v)
        assertEquals(3, v.size)
        assertEquals(51.51, v[0][0], 0.001)
        assertEquals(-0.12, v[0][1], 0.001)

        db.close()
    }

    /**
     * Verifies that a v1 database (no audit_trail, no privacy_zones, no vertices)
     * migrates correctly through all versions to v4.
     */
    @Test
    fun migration_v1ToV4_fullMigrationChain() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val dbPath = context.getDatabasePath("tracelet.db").path
        context.getDatabasePath("tracelet.db").parentFile?.mkdirs()
        val rawDb = SQLiteDatabase.openOrCreateDatabase(dbPath, null)

        // Create only the original v1 tables (locations, geofences, logs)
        rawDb.execSQL("""
            CREATE TABLE locations (
                uuid TEXT PRIMARY KEY,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                altitude REAL DEFAULT 0,
                speed REAL DEFAULT 0,
                heading REAL DEFAULT 0,
                accuracy REAL DEFAULT 0,
                speed_accuracy REAL DEFAULT -1,
                heading_accuracy REAL DEFAULT -1,
                altitude_accuracy REAL DEFAULT -1,
                timestamp INTEGER NOT NULL,
                is_moving INTEGER DEFAULT 0,
                odometer REAL DEFAULT 0,
                activity_type TEXT,
                activity_confidence INTEGER DEFAULT -1,
                battery_level REAL DEFAULT -1,
                battery_charging INTEGER DEFAULT 0,
                event TEXT,
                extras TEXT,
                synced INTEGER DEFAULT 0,
                created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
            )
        """.trimIndent())
        rawDb.execSQL("""
            CREATE TABLE geofences (
                identifier TEXT PRIMARY KEY,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                radius REAL NOT NULL,
                notify_on_entry INTEGER DEFAULT 1,
                notify_on_exit INTEGER DEFAULT 1,
                notify_on_dwell INTEGER DEFAULT 0,
                loitering_delay INTEGER DEFAULT 0,
                gf_extras TEXT
            )
        """.trimIndent())
        rawDb.execSQL("CREATE TABLE logs (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL, level TEXT NOT NULL, message TEXT NOT NULL, tag TEXT DEFAULT 'tracelet')")

        // Insert a v1 geofence
        val values = ContentValues().apply {
            put("identifier", "v1-fence")
            put("latitude", 35.6762)
            put("longitude", 139.6503)
            put("radius", 300.0)
        }
        rawDb.insert("geofences", null, values)

        rawDb.version = 1
        rawDb.close()

        // Open via TraceletDatabase — migrates v1 → v2 → v3 → v4 → v5
        val db = TraceletDatabase.getInstance(context)

        assertEquals(5, db.readableDatabase.version)

        // Original geofence should survive
        val existing = db.getGeofence("v1-fence")
        assertNotNull(existing, "v1 geofence should survive full migration chain")
        assertEquals(35.6762, existing["latitude"])

        // Polygon geofences should work
        assertTrue(db.insertGeofence(mapOf<String, Any?>(
            "identifier" to "post-migration-poly",
            "latitude" to 35.0,
            "longitude" to 139.0,
            "radius" to 0.0,
            "vertices" to listOf(
                listOf(35.01, 139.01),
                listOf(35.02, 139.02),
                listOf(35.03, 139.03),
            ),
        )))

        val poly = db.getGeofence("post-migration-poly")
        assertNotNull(poly)
        @Suppress("UNCHECKED_CAST")
        val v = poly["vertices"] as? List<List<Double>>
        assertNotNull(v)
        assertEquals(3, v.size)

        db.close()
    }
}
