package com.tracelet.tracelet_android.db

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.util.UUID
import java.util.concurrent.Executors

/**
 * SQLite persistence layer for Tracelet.
 *
 * Uses raw SQLiteOpenHelper (no Room annotations needed in plugin library).
 * All write operations are serialized on a single background thread.
 *
 * Tables: locations, geofences, logs
 */
class TraceletDatabase private constructor(context: Context) :
    SQLiteOpenHelper(context, DB_NAME, null, DB_VERSION) {

    companion object {
        private const val DB_NAME = "tracelet.db"
        private const val DB_VERSION = 1

        // Location table
        const val TABLE_LOCATIONS = "locations"
        const val COL_UUID = "uuid"
        const val COL_LATITUDE = "latitude"
        const val COL_LONGITUDE = "longitude"
        const val COL_ALTITUDE = "altitude"
        const val COL_SPEED = "speed"
        const val COL_HEADING = "heading"
        const val COL_ACCURACY = "accuracy"
        const val COL_SPEED_ACCURACY = "speed_accuracy"
        const val COL_HEADING_ACCURACY = "heading_accuracy"
        const val COL_ALTITUDE_ACCURACY = "altitude_accuracy"
        const val COL_TIMESTAMP = "timestamp"
        const val COL_IS_MOVING = "is_moving"
        const val COL_ODOMETER = "odometer"
        const val COL_ACTIVITY_TYPE = "activity_type"
        const val COL_ACTIVITY_CONFIDENCE = "activity_confidence"
        const val COL_BATTERY_LEVEL = "battery_level"
        const val COL_BATTERY_CHARGING = "battery_charging"
        const val COL_EVENT = "event"
        const val COL_EXTRAS = "extras"
        const val COL_SYNCED = "synced"
        const val COL_CREATED_AT = "created_at"

        // Geofence table
        const val TABLE_GEOFENCES = "geofences"
        const val COL_IDENTIFIER = "identifier"
        const val COL_RADIUS = "radius"
        // latitude, longitude reused
        const val COL_NOTIFY_ON_ENTRY = "notify_on_entry"
        const val COL_NOTIFY_ON_EXIT = "notify_on_exit"
        const val COL_NOTIFY_ON_DWELL = "notify_on_dwell"
        const val COL_LOITERING_DELAY = "loitering_delay"
        const val COL_GF_EXTRAS = "gf_extras"

        // Log table
        const val TABLE_LOGS = "logs"
        const val COL_LOG_ID = "id"
        const val COL_LOG_TIMESTAMP = "timestamp"
        const val COL_LOG_LEVEL = "level"
        const val COL_LOG_MESSAGE = "message"
        const val COL_LOG_TAG = "tag"

        @Volatile
        private var instance: TraceletDatabase? = null

        fun getInstance(context: Context): TraceletDatabase {
            return instance ?: synchronized(this) {
                instance ?: TraceletDatabase(context.applicationContext).also { instance = it }
            }
        }
    }

    private val writeExecutor = Executors.newSingleThreadExecutor()

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("""
            CREATE TABLE $TABLE_LOCATIONS (
                $COL_UUID TEXT PRIMARY KEY,
                $COL_LATITUDE REAL NOT NULL,
                $COL_LONGITUDE REAL NOT NULL,
                $COL_ALTITUDE REAL DEFAULT 0,
                $COL_SPEED REAL DEFAULT 0,
                $COL_HEADING REAL DEFAULT 0,
                $COL_ACCURACY REAL DEFAULT 0,
                $COL_SPEED_ACCURACY REAL DEFAULT -1,
                $COL_HEADING_ACCURACY REAL DEFAULT -1,
                $COL_ALTITUDE_ACCURACY REAL DEFAULT -1,
                $COL_TIMESTAMP INTEGER NOT NULL,
                $COL_IS_MOVING INTEGER DEFAULT 0,
                $COL_ODOMETER REAL DEFAULT 0,
                $COL_ACTIVITY_TYPE TEXT,
                $COL_ACTIVITY_CONFIDENCE INTEGER DEFAULT -1,
                $COL_BATTERY_LEVEL REAL DEFAULT -1,
                $COL_BATTERY_CHARGING INTEGER DEFAULT 0,
                $COL_EVENT TEXT,
                $COL_EXTRAS TEXT,
                $COL_SYNCED INTEGER DEFAULT 0,
                $COL_CREATED_AT INTEGER DEFAULT (strftime('%s','now') * 1000)
            )
        """.trimIndent())

        db.execSQL("""
            CREATE INDEX idx_locations_synced ON $TABLE_LOCATIONS ($COL_SYNCED)
        """.trimIndent())

        db.execSQL("""
            CREATE INDEX idx_locations_timestamp ON $TABLE_LOCATIONS ($COL_TIMESTAMP)
        """.trimIndent())

        db.execSQL("""
            CREATE TABLE $TABLE_GEOFENCES (
                $COL_IDENTIFIER TEXT PRIMARY KEY,
                $COL_LATITUDE REAL NOT NULL,
                $COL_LONGITUDE REAL NOT NULL,
                $COL_RADIUS REAL NOT NULL,
                $COL_NOTIFY_ON_ENTRY INTEGER DEFAULT 1,
                $COL_NOTIFY_ON_EXIT INTEGER DEFAULT 1,
                $COL_NOTIFY_ON_DWELL INTEGER DEFAULT 0,
                $COL_LOITERING_DELAY INTEGER DEFAULT 0,
                $COL_GF_EXTRAS TEXT
            )
        """.trimIndent())

        db.execSQL("""
            CREATE TABLE $TABLE_LOGS (
                $COL_LOG_ID INTEGER PRIMARY KEY AUTOINCREMENT,
                $COL_LOG_TIMESTAMP INTEGER NOT NULL,
                $COL_LOG_LEVEL TEXT NOT NULL,
                $COL_LOG_MESSAGE TEXT NOT NULL,
                $COL_LOG_TAG TEXT DEFAULT 'tracelet'
            )
        """.trimIndent())

        db.execSQL("""
            CREATE INDEX idx_logs_timestamp ON $TABLE_LOGS ($COL_LOG_TIMESTAMP)
        """.trimIndent())
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // Migration strategy: add new columns without dropping data
        // For v1→v2 migrations, add ALTER TABLE statements here
    }

    // =========================================================================
    // Location CRUD
    // =========================================================================

    /** Inserts a location and returns its UUID. */
    fun insertLocation(location: Map<String, Any?>): String {
        val uuid = location["uuid"] as? String ?: UUID.randomUUID().toString()
        val values = ContentValues().apply {
            put(COL_UUID, uuid)
            put(COL_LATITUDE, (location["latitude"] as? Number)?.toDouble() ?: 0.0)
            put(COL_LONGITUDE, (location["longitude"] as? Number)?.toDouble() ?: 0.0)
            put(COL_ALTITUDE, (location["altitude"] as? Number)?.toDouble() ?: 0.0)
            put(COL_SPEED, (location["speed"] as? Number)?.toDouble() ?: 0.0)
            put(COL_HEADING, (location["heading"] as? Number)?.toDouble() ?: 0.0)
            put(COL_ACCURACY, (location["accuracy"] as? Number)?.toDouble() ?: 0.0)
            put(COL_SPEED_ACCURACY, (location["speedAccuracy"] as? Number)?.toDouble() ?: -1.0)
            put(COL_HEADING_ACCURACY, (location["headingAccuracy"] as? Number)?.toDouble() ?: -1.0)
            put(COL_ALTITUDE_ACCURACY, (location["altitudeAccuracy"] as? Number)?.toDouble() ?: -1.0)
            put(COL_TIMESTAMP, (location["timestamp"] as? Number)?.toLong() ?: System.currentTimeMillis())
            put(COL_IS_MOVING, if (location["isMoving"] == true) 1 else 0)
            put(COL_ODOMETER, (location["odometer"] as? Number)?.toDouble() ?: 0.0)
            put(COL_ACTIVITY_TYPE, location["activityType"] as? String)
            put(COL_ACTIVITY_CONFIDENCE, (location["activityConfidence"] as? Number)?.toInt() ?: -1)
            put(COL_BATTERY_LEVEL, (location["batteryLevel"] as? Number)?.toDouble() ?: -1.0)
            put(COL_BATTERY_CHARGING, if (location["batteryCharging"] == true) 1 else 0)
            put(COL_EVENT, location["event"] as? String)
            put(COL_EXTRAS, location["extras"]?.toString())
            put(COL_SYNCED, 0)
            put(COL_CREATED_AT, System.currentTimeMillis())
        }
        writableDatabase.insertWithOnConflict(TABLE_LOCATIONS, null, values, SQLiteDatabase.CONFLICT_REPLACE)
        return uuid
    }

    /** Inserts a location asynchronously on the write thread. Calls [callback] with UUID. */
    fun insertLocationAsync(location: Map<String, Any?>, callback: ((String) -> Unit)? = null) {
        writeExecutor.execute {
            val uuid = insertLocation(location)
            callback?.invoke(uuid)
        }
    }

    /** Retrieves locations with optional pagination and ordering. */
    fun getLocations(limit: Int = -1, offset: Int = 0, orderAsc: Boolean = true): List<Map<String, Any?>> {
        val order = if (orderAsc) "ASC" else "DESC"
        val limitClause = if (limit > 0) "LIMIT $limit OFFSET $offset" else ""
        val cursor = readableDatabase.rawQuery(
            "SELECT * FROM $TABLE_LOCATIONS ORDER BY $COL_TIMESTAMP $order $limitClause",
            null
        )
        return cursorToLocationList(cursor)
    }

    /** Gets unsent locations for HTTP sync. */
    fun getUnsyncedLocations(batchSize: Int, orderAsc: Boolean = true): List<Map<String, Any?>> {
        val order = if (orderAsc) "ASC" else "DESC"
        val cursor = readableDatabase.rawQuery(
            "SELECT * FROM $TABLE_LOCATIONS WHERE $COL_SYNCED = 0 ORDER BY $COL_TIMESTAMP $order LIMIT ?",
            arrayOf(batchSize.toString())
        )
        return cursorToLocationList(cursor)
    }

    /** Returns total count of stored locations. */
    fun getLocationCount(): Int {
        val cursor = readableDatabase.rawQuery("SELECT COUNT(*) FROM $TABLE_LOCATIONS", null)
        cursor.use {
            return if (it.moveToFirst()) it.getInt(0) else 0
        }
    }

    /** Marks locations as synced by UUIDs. */
    fun markSynced(uuids: List<String>) {
        if (uuids.isEmpty()) return
        val db = writableDatabase
        db.beginTransaction()
        try {
            val stmt = db.compileStatement(
                "UPDATE $TABLE_LOCATIONS SET $COL_SYNCED = 1 WHERE $COL_UUID = ?"
            )
            for (uuid in uuids) {
                stmt.bindString(1, uuid)
                stmt.executeUpdateDelete()
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    /** Deletes all locations. */
    fun deleteAllLocations(): Boolean {
        writableDatabase.delete(TABLE_LOCATIONS, null, null)
        return true
    }

    /** Deletes a location by UUID. */
    fun deleteLocation(uuid: String): Boolean {
        return writableDatabase.delete(TABLE_LOCATIONS, "$COL_UUID = ?", arrayOf(uuid)) > 0
    }

    // =========================================================================
    // Geofence CRUD
    // =========================================================================

    /** Inserts or replaces a geofence. */
    fun insertGeofence(geofence: Map<String, Any?>): Boolean {
        val values = ContentValues().apply {
            put(COL_IDENTIFIER, geofence["identifier"] as? String ?: return false)
            put(COL_LATITUDE, (geofence["latitude"] as? Number)?.toDouble() ?: return false)
            put(COL_LONGITUDE, (geofence["longitude"] as? Number)?.toDouble() ?: return false)
            put(COL_RADIUS, (geofence["radius"] as? Number)?.toDouble() ?: 200.0)
            put(COL_NOTIFY_ON_ENTRY, if (geofence["notifyOnEntry"] != false) 1 else 0)
            put(COL_NOTIFY_ON_EXIT, if (geofence["notifyOnExit"] != false) 1 else 0)
            put(COL_NOTIFY_ON_DWELL, if (geofence["notifyOnDwell"] == true) 1 else 0)
            put(COL_LOITERING_DELAY, (geofence["loiteringDelay"] as? Number)?.toInt() ?: 0)
            put(COL_GF_EXTRAS, geofence["extras"]?.toString())
        }
        writableDatabase.insertWithOnConflict(TABLE_GEOFENCES, null, values, SQLiteDatabase.CONFLICT_REPLACE)
        return true
    }

    /** Retrieves all geofences. */
    fun getGeofences(): List<Map<String, Any?>> {
        val cursor = readableDatabase.rawQuery("SELECT * FROM $TABLE_GEOFENCES", null)
        return cursorToGeofenceList(cursor)
    }

    /** Retrieves a single geofence by identifier. */
    fun getGeofence(identifier: String): Map<String, Any?>? {
        val cursor = readableDatabase.rawQuery(
            "SELECT * FROM $TABLE_GEOFENCES WHERE $COL_IDENTIFIER = ?",
            arrayOf(identifier)
        )
        cursor.use {
            return if (it.moveToFirst()) cursorToGeofence(it) else null
        }
    }

    /** Checks if a geofence exists. */
    fun geofenceExists(identifier: String): Boolean {
        val cursor = readableDatabase.rawQuery(
            "SELECT 1 FROM $TABLE_GEOFENCES WHERE $COL_IDENTIFIER = ? LIMIT 1",
            arrayOf(identifier)
        )
        cursor.use { return it.moveToFirst() }
    }

    /** Deletes a geofence by identifier. */
    fun deleteGeofence(identifier: String): Boolean {
        return writableDatabase.delete(TABLE_GEOFENCES, "$COL_IDENTIFIER = ?", arrayOf(identifier)) > 0
    }

    /** Deletes all geofences. */
    fun deleteAllGeofences(): Boolean {
        writableDatabase.delete(TABLE_GEOFENCES, null, null)
        return true
    }

    // =========================================================================
    // Log CRUD
    // =========================================================================

    /** Inserts a log entry. */
    fun insertLog(level: String, message: String, tag: String = "tracelet") {
        writeExecutor.execute {
            val values = ContentValues().apply {
                put(COL_LOG_TIMESTAMP, System.currentTimeMillis())
                put(COL_LOG_LEVEL, level)
                put(COL_LOG_MESSAGE, message)
                put(COL_LOG_TAG, tag)
            }
            writableDatabase.insert(TABLE_LOGS, null, values)
        }
    }

    /** Gets log entries as a formatted string. */
    fun getLog(startTime: Long? = null, endTime: Long? = null, level: String? = null): String {
        val conditions = mutableListOf<String>()
        val args = mutableListOf<String>()

        startTime?.let {
            conditions.add("$COL_LOG_TIMESTAMP >= ?")
            args.add(it.toString())
        }
        endTime?.let {
            conditions.add("$COL_LOG_TIMESTAMP <= ?")
            args.add(it.toString())
        }
        level?.let {
            conditions.add("$COL_LOG_LEVEL = ?")
            args.add(it)
        }

        val where = if (conditions.isNotEmpty()) "WHERE ${conditions.joinToString(" AND ")}" else ""
        val cursor = readableDatabase.rawQuery(
            "SELECT * FROM $TABLE_LOGS $where ORDER BY $COL_LOG_TIMESTAMP ASC",
            args.toTypedArray()
        )

        val sb = StringBuilder()
        cursor.use {
            while (it.moveToNext()) {
                val ts = it.getLong(it.getColumnIndexOrThrow(COL_LOG_TIMESTAMP))
                val lvl = it.getString(it.getColumnIndexOrThrow(COL_LOG_LEVEL))
                val msg = it.getString(it.getColumnIndexOrThrow(COL_LOG_MESSAGE))
                val tg = it.getString(it.getColumnIndexOrThrow(COL_LOG_TAG))
                sb.appendLine("[$lvl] $ts [$tg] $msg")
            }
        }
        return sb.toString()
    }

    /** Deletes all log entries. */
    fun deleteAllLogs(): Boolean {
        writableDatabase.delete(TABLE_LOGS, null, null)
        return true
    }

    /** Removes log entries older than [maxDays]. */
    fun pruneLogs(maxDays: Int) {
        writeExecutor.execute {
            val cutoff = System.currentTimeMillis() - (maxDays * 24L * 60 * 60 * 1000)
            writableDatabase.delete(TABLE_LOGS, "$COL_LOG_TIMESTAMP < ?", arrayOf(cutoff.toString()))
        }
    }

    // =========================================================================
    // Cursor mapping helpers
    // =========================================================================

    private fun cursorToLocationList(cursor: Cursor): List<Map<String, Any?>> {
        val list = mutableListOf<Map<String, Any?>>()
        cursor.use {
            while (it.moveToNext()) {
                list.add(cursorToLocation(it))
            }
        }
        return list
    }

    private fun cursorToLocation(c: Cursor): Map<String, Any?> {
        return mapOf(
            "uuid" to c.getString(c.getColumnIndexOrThrow(COL_UUID)),
            "timestamp" to c.getLong(c.getColumnIndexOrThrow(COL_TIMESTAMP)),
            "isMoving" to (c.getInt(c.getColumnIndexOrThrow(COL_IS_MOVING)) == 1),
            "odometer" to c.getDouble(c.getColumnIndexOrThrow(COL_ODOMETER)),
            "event" to c.getString(c.getColumnIndexOrThrow(COL_EVENT)),
            "coords" to mapOf(
                "latitude" to c.getDouble(c.getColumnIndexOrThrow(COL_LATITUDE)),
                "longitude" to c.getDouble(c.getColumnIndexOrThrow(COL_LONGITUDE)),
                "altitude" to c.getDouble(c.getColumnIndexOrThrow(COL_ALTITUDE)),
                "speed" to c.getDouble(c.getColumnIndexOrThrow(COL_SPEED)),
                "heading" to c.getDouble(c.getColumnIndexOrThrow(COL_HEADING)),
                "accuracy" to c.getDouble(c.getColumnIndexOrThrow(COL_ACCURACY)),
                "speedAccuracy" to c.getDouble(c.getColumnIndexOrThrow(COL_SPEED_ACCURACY)),
                "headingAccuracy" to c.getDouble(c.getColumnIndexOrThrow(COL_HEADING_ACCURACY)),
                "altitudeAccuracy" to c.getDouble(c.getColumnIndexOrThrow(COL_ALTITUDE_ACCURACY)),
            ),
            "activity" to mapOf(
                "type" to (c.getString(c.getColumnIndexOrThrow(COL_ACTIVITY_TYPE)) ?: "unknown"),
                "confidence" to c.getInt(c.getColumnIndexOrThrow(COL_ACTIVITY_CONFIDENCE)),
            ),
            "battery" to mapOf(
                "level" to c.getDouble(c.getColumnIndexOrThrow(COL_BATTERY_LEVEL)),
                "isCharging" to (c.getInt(c.getColumnIndexOrThrow(COL_BATTERY_CHARGING)) == 1),
            ),
        )
    }

    private fun cursorToGeofenceList(cursor: Cursor): List<Map<String, Any?>> {
        val list = mutableListOf<Map<String, Any?>>()
        cursor.use {
            while (it.moveToNext()) {
                list.add(cursorToGeofence(it))
            }
        }
        return list
    }

    private fun cursorToGeofence(c: Cursor): Map<String, Any?> {
        return mapOf(
            "identifier" to c.getString(c.getColumnIndexOrThrow(COL_IDENTIFIER)),
            "latitude" to c.getDouble(c.getColumnIndexOrThrow(COL_LATITUDE)),
            "longitude" to c.getDouble(c.getColumnIndexOrThrow(COL_LONGITUDE)),
            "radius" to c.getDouble(c.getColumnIndexOrThrow(COL_RADIUS)),
            "notifyOnEntry" to (c.getInt(c.getColumnIndexOrThrow(COL_NOTIFY_ON_ENTRY)) == 1),
            "notifyOnExit" to (c.getInt(c.getColumnIndexOrThrow(COL_NOTIFY_ON_EXIT)) == 1),
            "notifyOnDwell" to (c.getInt(c.getColumnIndexOrThrow(COL_NOTIFY_ON_DWELL)) == 1),
            "loiteringDelay" to c.getInt(c.getColumnIndexOrThrow(COL_LOITERING_DELAY)),
            "extras" to c.getString(c.getColumnIndexOrThrow(COL_GF_EXTRAS)),
        )
    }
}
