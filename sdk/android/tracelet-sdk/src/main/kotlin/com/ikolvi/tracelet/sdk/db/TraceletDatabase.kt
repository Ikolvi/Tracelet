package com.ikolvi.tracelet.sdk.db

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/**
 * SQLite persistence layer for Tracelet.
 *
 * Uses Android's standard SQLiteOpenHelper. On Android 8+ (minSdk 26),
 * the database file is automatically encrypted at rest by Android's
 * File-Based Encryption (FBE). For additional application-level encryption,
 * the [encryptDatabase] method uses SQLCipher to migrate the file.
 *
 * All write operations are serialized on a single background thread.
 *
 * Tables: locations, geofences, logs, audit_trail, privacy_zones
 */
class TraceletDatabase private constructor(context: Context, private val dbPassword: ByteArray = ByteArray(0)) :
    SQLiteOpenHelper(context, DB_NAME, null, DB_VERSION) {

    companion object {
        private const val TAG = "TraceletDatabase"
        private const val DB_NAME = "tracelet.db"
        private const val DB_VERSION = 5

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
        const val COL_VERTICES = "vertices"

        // Log table
        const val TABLE_LOGS = "logs"
        const val COL_LOG_ID = "id"
        const val COL_LOG_TIMESTAMP = "timestamp"
        const val COL_LOG_LEVEL = "level"
        const val COL_LOG_MESSAGE = "message"
        const val COL_LOG_TAG = "tag"

        // Audit trail table
        const val TABLE_AUDIT_TRAIL = "audit_trail"
        const val COL_AUDIT_HASH = "hash"
        const val COL_AUDIT_PREVIOUS_HASH = "previous_hash"
        const val COL_AUDIT_CHAIN_INDEX = "chain_index"
        const val COL_AUDIT_CREATED_AT = "created_at"

        // Privacy zones table
        const val TABLE_PRIVACY_ZONES = "privacy_zones"
        const val COL_PZ_ACTION = "action"
        const val COL_PZ_DEGRADED_ACCURACY = "degraded_accuracy"

        @Volatile
        private var instance: TraceletDatabase? = null

        fun getInstance(context: Context, password: ByteArray = ByteArray(0)): TraceletDatabase {
            return instance ?: synchronized(this) {
                instance ?: TraceletDatabase(context.applicationContext, password).also { instance = it }
            }
        }

        /**
         * Reinitialize the database with a new password.
         * Closes the existing instance and creates a new one with encryption.
         */
        fun reinitialize(context: Context, password: ByteArray): TraceletDatabase {
            synchronized(this) {
                instance?.close()
                instance = null
                return TraceletDatabase(context.applicationContext, password).also { instance = it }
            }
        }
    }

    private val appContext = context
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

        // Index on created_at for retention pruning queries (A-M8).
        db.execSQL("""
            CREATE INDEX idx_locations_created_at ON $TABLE_LOCATIONS ($COL_CREATED_AT)
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
                $COL_GF_EXTRAS TEXT,
                $COL_VERTICES TEXT
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

        // Audit trail table — stores hash chain for tamper-proof verification
        db.execSQL("""
            CREATE TABLE $TABLE_AUDIT_TRAIL (
                $COL_UUID TEXT PRIMARY KEY,
                $COL_AUDIT_HASH TEXT NOT NULL,
                $COL_AUDIT_PREVIOUS_HASH TEXT NOT NULL,
                $COL_AUDIT_CHAIN_INDEX INTEGER NOT NULL UNIQUE,
                $COL_AUDIT_CREATED_AT INTEGER DEFAULT (strftime('%s','now') * 1000)
            )
        """.trimIndent())

        db.execSQL("""
            CREATE INDEX idx_audit_chain_index ON $TABLE_AUDIT_TRAIL ($COL_AUDIT_CHAIN_INDEX)
        """.trimIndent())

        // Privacy zones table — geographic areas with tracking behaviour changes
        db.execSQL("""
            CREATE TABLE $TABLE_PRIVACY_ZONES (
                $COL_IDENTIFIER TEXT PRIMARY KEY,
                $COL_LATITUDE REAL NOT NULL,
                $COL_LONGITUDE REAL NOT NULL,
                $COL_RADIUS REAL NOT NULL,
                $COL_PZ_ACTION INTEGER NOT NULL DEFAULT 0,
                $COL_PZ_DEGRADED_ACCURACY REAL DEFAULT 1000.0
            )
        """.trimIndent())
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // v1 → v2: Add audit_trail table for tamper-proof hash chain
        if (oldVersion < 2) {
            db.execSQL("""
                CREATE TABLE IF NOT EXISTS $TABLE_AUDIT_TRAIL (
                    $COL_UUID TEXT PRIMARY KEY,
                    $COL_AUDIT_HASH TEXT NOT NULL,
                    $COL_AUDIT_PREVIOUS_HASH TEXT NOT NULL,
                    $COL_AUDIT_CHAIN_INDEX INTEGER NOT NULL UNIQUE,
                    $COL_AUDIT_CREATED_AT INTEGER DEFAULT (strftime('%s','now') * 1000)
                )
            """.trimIndent())
            db.execSQL("""
                CREATE INDEX IF NOT EXISTS idx_audit_chain_index ON $TABLE_AUDIT_TRAIL ($COL_AUDIT_CHAIN_INDEX)
            """.trimIndent())
        }
        // v2 → v3: Add privacy_zones table
        if (oldVersion < 3) {
            db.execSQL("""
                CREATE TABLE IF NOT EXISTS $TABLE_PRIVACY_ZONES (
                    $COL_IDENTIFIER TEXT PRIMARY KEY,
                    $COL_LATITUDE REAL NOT NULL,
                    $COL_LONGITUDE REAL NOT NULL,
                    $COL_RADIUS REAL NOT NULL,
                    $COL_PZ_ACTION INTEGER NOT NULL DEFAULT 0,
                    $COL_PZ_DEGRADED_ACCURACY REAL DEFAULT 1000.0
                )
            """.trimIndent())
        }
        // v3 → v4: Add vertices column to geofences table for polygon support
        if (oldVersion < 4) {
            db.execSQL("""
                ALTER TABLE $TABLE_GEOFENCES ADD COLUMN $COL_VERTICES TEXT
            """.trimIndent())
        }
        // v4 → v5: Add index on created_at for faster retention pruning (A-M8)
        if (oldVersion < 5) {
            db.execSQL("""
                CREATE INDEX IF NOT EXISTS idx_locations_created_at ON $TABLE_LOCATIONS ($COL_CREATED_AT)
            """.trimIndent())
        }
    }

    // =========================================================================
    // Location CRUD
    // =========================================================================

    /** Inserts a location and returns its UUID. Respects persistMode and retention limits. */
    fun insertLocation(location: Map<String, Any?>): String {
        val uuid = location["uuid"] as? String ?: UUID.randomUUID().toString()
        // Read from nested maps (coords, battery, activity) to avoid requiring
        // duplicate flat keys in the location map (A-H8).
        val coords = location["coords"] as? Map<*, *>
        val battery = location["battery"] as? Map<*, *>
        val activity = location["activity"] as? Map<*, *>
        val values = ContentValues().apply {
            put(COL_UUID, uuid)
            put(COL_LATITUDE, (coords?.get("latitude") as? Number)?.toDouble()
                ?: (location["latitude"] as? Number)?.toDouble() ?: 0.0)
            put(COL_LONGITUDE, (coords?.get("longitude") as? Number)?.toDouble()
                ?: (location["longitude"] as? Number)?.toDouble() ?: 0.0)
            put(COL_ALTITUDE, (coords?.get("altitude") as? Number)?.toDouble()
                ?: (location["altitude"] as? Number)?.toDouble() ?: 0.0)
            put(COL_SPEED, (coords?.get("speed") as? Number)?.toDouble()
                ?: (location["speed"] as? Number)?.toDouble() ?: 0.0)
            put(COL_HEADING, (coords?.get("heading") as? Number)?.toDouble()
                ?: (location["heading"] as? Number)?.toDouble() ?: 0.0)
            put(COL_ACCURACY, (coords?.get("accuracy") as? Number)?.toDouble()
                ?: (location["accuracy"] as? Number)?.toDouble() ?: 0.0)
            put(COL_SPEED_ACCURACY, (coords?.get("speedAccuracy") as? Number)?.toDouble()
                ?: (location["speedAccuracy"] as? Number)?.toDouble() ?: -1.0)
            put(COL_HEADING_ACCURACY, (coords?.get("headingAccuracy") as? Number)?.toDouble()
                ?: (location["headingAccuracy"] as? Number)?.toDouble() ?: -1.0)
            put(COL_ALTITUDE_ACCURACY, (coords?.get("altitudeAccuracy") as? Number)?.toDouble()
                ?: (location["altitudeAccuracy"] as? Number)?.toDouble() ?: -1.0)
            put(COL_TIMESTAMP, (location["timestamp"] as? Number)?.toLong() ?: System.currentTimeMillis())
            put(COL_IS_MOVING, if (location["isMoving"] == true) 1 else 0)
            put(COL_ODOMETER, (location["odometer"] as? Number)?.toDouble() ?: 0.0)
            put(COL_ACTIVITY_TYPE, (activity?.get("type") as? String)
                ?: (location["activityType"] as? String))
            put(COL_ACTIVITY_CONFIDENCE, (activity?.get("confidence") as? Number)?.toInt()
                ?: (location["activityConfidence"] as? Number)?.toInt() ?: -1)
            put(COL_BATTERY_LEVEL, (battery?.get("level") as? Number)?.toDouble()
                ?: (location["batteryLevel"] as? Number)?.toDouble() ?: -1.0)
            put(COL_BATTERY_CHARGING, if (battery?.get("is_charging") == true || battery?.get("isCharging") == true || location["batteryCharging"] == true) 1 else 0)
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

    /** Retrieves locations with optional time range, pagination and ordering. Includes audit fields. */
    fun getLocations(limit: Int = -1, offset: Int = 0, orderAsc: Boolean = true, startTime: Long? = null, endTime: Long? = null): List<Map<String, Any?>> {
        val order = if (orderAsc) "ASC" else "DESC"
        val conditions = mutableListOf<String>()
        val args = mutableListOf<String>()

        startTime?.let {
            conditions.add("l.$COL_TIMESTAMP >= ?")
            args.add(it.toString())
        }
        endTime?.let {
            conditions.add("l.$COL_TIMESTAMP <= ?")
            args.add(it.toString())
        }

        val where = if (conditions.isNotEmpty()) "WHERE ${conditions.joinToString(" AND ")}" else ""
        val limitClause = if (limit > 0) "LIMIT $limit OFFSET $offset" else ""
        val cursor = readableDatabase.rawQuery(
            "SELECT l.*, a.$COL_AUDIT_HASH, a.$COL_AUDIT_PREVIOUS_HASH, a.$COL_AUDIT_CHAIN_INDEX " +
            "FROM $TABLE_LOCATIONS l " +
            "LEFT JOIN $TABLE_AUDIT_TRAIL a ON l.$COL_UUID = a.$COL_UUID " +
            "$where ORDER BY l.$COL_TIMESTAMP $order $limitClause",
            args.toTypedArray()
        )
        return cursorToLocationList(cursor)
    }

    /** Gets unsent locations for HTTP sync. Includes audit fields. */
    fun getUnsyncedLocations(batchSize: Int, orderAsc: Boolean = true): List<Map<String, Any?>> {
        val order = if (orderAsc) "ASC" else "DESC"
        val cursor = readableDatabase.rawQuery(
            "SELECT l.*, a.$COL_AUDIT_HASH, a.$COL_AUDIT_PREVIOUS_HASH, a.$COL_AUDIT_CHAIN_INDEX " +
            "FROM $TABLE_LOCATIONS l " +
            "LEFT JOIN $TABLE_AUDIT_TRAIL a ON l.$COL_UUID = a.$COL_UUID " +
            "WHERE l.$COL_SYNCED = 0 ORDER BY l.$COL_TIMESTAMP $order LIMIT ?",
            arrayOf(batchSize.toString())
        )
        return cursorToLocationList(cursor)
    }

    /** Returns total count of stored locations. */
    fun getLocationCount(startTime: Long? = null, endTime: Long? = null): Int {
        val conditions = mutableListOf<String>()
        val args = mutableListOf<String>()

        startTime?.let {
            conditions.add("$COL_TIMESTAMP >= ?")
            args.add(it.toString())
        }
        endTime?.let {
            conditions.add("$COL_TIMESTAMP <= ?")
            args.add(it.toString())
        }

        val where = if (conditions.isNotEmpty()) "WHERE ${conditions.joinToString(" AND ")}" else ""
        val cursor = readableDatabase.rawQuery("SELECT COUNT(*) FROM $TABLE_LOCATIONS $where", args.toTypedArray())
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

    /** Prune locations older than [maxDays]. */
    fun pruneOldLocations(maxDays: Int) {
        if (maxDays <= 0) return
        writeExecutor.execute {
            val cutoff = System.currentTimeMillis() - (maxDays * 24L * 60 * 60 * 1000)
            writableDatabase.delete(TABLE_LOCATIONS, "$COL_CREATED_AT < ?", arrayOf(cutoff.toString()))
        }
    }

    /** Enforce max record count by deleting oldest records. */
    fun enforceMaxRecords(maxRecords: Int) {
        if (maxRecords <= 0) return
        writeExecutor.execute {
            val count = getLocationCount()
            if (count > maxRecords) {
                val excess = count - maxRecords
                writableDatabase.execSQL(
                    "DELETE FROM $TABLE_LOCATIONS WHERE $COL_UUID IN " +
                    "(SELECT $COL_UUID FROM $TABLE_LOCATIONS ORDER BY $COL_CREATED_AT ASC LIMIT $excess)"
                )
            }
        }
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

            // Serialize vertices as JSON: [[lat,lng],[lat,lng],...]
            val vertices = geofence["vertices"] as? List<*>
            if (vertices != null && vertices.isNotEmpty()) {
                val verticesJson = org.json.JSONArray()
                for (vertex in vertices) {
                    if (vertex is List<*> && vertex.size >= 2) {
                        val lat = (vertex[0] as? Number)?.toDouble()
                        val lng = (vertex[1] as? Number)?.toDouble()
                        if (lat != null && lng != null) {
                            val vertexArray = org.json.JSONArray()
                            vertexArray.put(lat)
                            vertexArray.put(lng)
                            verticesJson.put(vertexArray)
                        }
                    }
                }
                if (verticesJson.length() >= 3) {
                    put(COL_VERTICES, verticesJson.toString())
                } else {
                    put(COL_VERTICES, null as String?)
                }
            } else {
                put(COL_VERTICES, null as String?)
            }
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
            "SELECT * FROM $TABLE_LOGS $where ORDER BY $COL_LOG_TIMESTAMP ASC LIMIT 5000",
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
            if (!it.moveToFirst()) return list
            // Resolve column indices once for the entire result set (A-L1).
            val iUuid = it.getColumnIndexOrThrow(COL_UUID)
            val iTimestamp = it.getColumnIndexOrThrow(COL_TIMESTAMP)
            val iIsMoving = it.getColumnIndexOrThrow(COL_IS_MOVING)
            val iOdometer = it.getColumnIndexOrThrow(COL_ODOMETER)
            val iEvent = it.getColumnIndexOrThrow(COL_EVENT)
            val iLatitude = it.getColumnIndexOrThrow(COL_LATITUDE)
            val iLongitude = it.getColumnIndexOrThrow(COL_LONGITUDE)
            val iAltitude = it.getColumnIndexOrThrow(COL_ALTITUDE)
            val iSpeed = it.getColumnIndexOrThrow(COL_SPEED)
            val iHeading = it.getColumnIndexOrThrow(COL_HEADING)
            val iAccuracy = it.getColumnIndexOrThrow(COL_ACCURACY)
            val iSpeedAccuracy = it.getColumnIndexOrThrow(COL_SPEED_ACCURACY)
            val iHeadingAccuracy = it.getColumnIndexOrThrow(COL_HEADING_ACCURACY)
            val iAltitudeAccuracy = it.getColumnIndexOrThrow(COL_ALTITUDE_ACCURACY)
            val iActivityType = it.getColumnIndexOrThrow(COL_ACTIVITY_TYPE)
            val iActivityConfidence = it.getColumnIndexOrThrow(COL_ACTIVITY_CONFIDENCE)
            val iBatteryLevel = it.getColumnIndexOrThrow(COL_BATTERY_LEVEL)
            val iBatteryCharging = it.getColumnIndexOrThrow(COL_BATTERY_CHARGING)
            val iHash = it.getColumnIndex(COL_AUDIT_HASH)
            val iPrevHash = it.getColumnIndex(COL_AUDIT_PREVIOUS_HASH)
            val iChainIdx = it.getColumnIndex(COL_AUDIT_CHAIN_INDEX)
            do {
                list.add(cursorToLocation(it, iUuid, iTimestamp, iIsMoving, iOdometer, iEvent,
                    iLatitude, iLongitude, iAltitude, iSpeed, iHeading, iAccuracy,
                    iSpeedAccuracy, iHeadingAccuracy, iAltitudeAccuracy,
                    iActivityType, iActivityConfidence, iBatteryLevel, iBatteryCharging,
                    iHash, iPrevHash, iChainIdx))
            } while (it.moveToNext())
        }
        return list
    }

    private fun cursorToLocation(
        c: Cursor,
        iUuid: Int, iTimestamp: Int, iIsMoving: Int, iOdometer: Int, iEvent: Int,
        iLatitude: Int, iLongitude: Int, iAltitude: Int, iSpeed: Int, iHeading: Int, iAccuracy: Int,
        iSpeedAccuracy: Int, iHeadingAccuracy: Int, iAltitudeAccuracy: Int,
        iActivityType: Int, iActivityConfidence: Int, iBatteryLevel: Int, iBatteryCharging: Int,
        iHash: Int, iPrevHash: Int, iChainIdx: Int
    ): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>(
            "uuid" to c.getString(iUuid),
            "timestamp" to c.getLong(iTimestamp),
            "isMoving" to (c.getInt(iIsMoving) == 1),
            "odometer" to c.getDouble(iOdometer),
            "event" to c.getString(iEvent),
            "coords" to mapOf(
                "latitude" to c.getDouble(iLatitude),
                "longitude" to c.getDouble(iLongitude),
                "altitude" to c.getDouble(iAltitude),
                "speed" to c.getDouble(iSpeed),
                "heading" to c.getDouble(iHeading),
                "accuracy" to c.getDouble(iAccuracy),
                "speedAccuracy" to c.getDouble(iSpeedAccuracy),
                "headingAccuracy" to c.getDouble(iHeadingAccuracy),
                "altitudeAccuracy" to c.getDouble(iAltitudeAccuracy),
            ),
            "activity" to mapOf(
                "type" to (c.getString(iActivityType) ?: "unknown"),
                "confidence" to c.getInt(iActivityConfidence),
            ),
            "battery" to mapOf(
                "level" to c.getDouble(iBatteryLevel),
                "is_charging" to (c.getInt(iBatteryCharging) == 1),
            ),
        )
        // Include audit fields when available (LEFT JOIN with audit_trail)
        if (iHash >= 0 && !c.isNull(iHash)) {
            map["audit_hash"] = c.getString(iHash)
            if (iPrevHash >= 0) map["audit_previous_hash"] = c.getString(iPrevHash)
            if (iChainIdx >= 0) map["audit_chain_index"] = c.getInt(iChainIdx)
        }
        return map
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
        // Parse vertices from JSON
        val verticesJson = c.getString(c.getColumnIndexOrThrow(COL_VERTICES))
        var vertices: List<List<Double>>? = null
        if (!verticesJson.isNullOrEmpty()) {
            try {
                val jsonArray = org.json.JSONArray(verticesJson)
                val parsed = mutableListOf<List<Double>>()
                for (i in 0 until jsonArray.length()) {
                    val vertexArray = jsonArray.getJSONArray(i)
                    if (vertexArray.length() >= 2) {
                        parsed.add(listOf(
                            vertexArray.getDouble(0),
                            vertexArray.getDouble(1)
                        ))
                    }
                }
                if (parsed.size >= 3) vertices = parsed
            } catch (e: Exception) {
                Log.w("Tracelet", "Failed to parse geofence vertices JSON: ${e.message}")
            }
        }

        val map = mutableMapOf<String, Any?>(
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
        if (vertices != null) {
            map["vertices"] = vertices
        }
        return map
    }

    // =========================================================================
    // Audit Trail CRUD
    // =========================================================================

    /** Inserts an audit trail record linking a location UUID to its hash chain entry. */
    fun insertAuditRecord(uuid: String, hash: String, previousHash: String, chainIndex: Int) {
        val values = ContentValues().apply {
            put(COL_UUID, uuid)
            put(COL_AUDIT_HASH, hash)
            put(COL_AUDIT_PREVIOUS_HASH, previousHash)
            put(COL_AUDIT_CHAIN_INDEX, chainIndex)
            put(COL_AUDIT_CREATED_AT, System.currentTimeMillis())
        }
        writableDatabase.insertWithOnConflict(TABLE_AUDIT_TRAIL, null, values, SQLiteDatabase.CONFLICT_REPLACE)
    }

    /** Retrieves all audit records ordered by chain index. */
    fun getAuditTrail(): List<Map<String, Any?>> {
        val cursor = readableDatabase.rawQuery(
            "SELECT * FROM $TABLE_AUDIT_TRAIL ORDER BY $COL_AUDIT_CHAIN_INDEX ASC",
            null
        )
        val list = mutableListOf<Map<String, Any?>>()
        cursor.use {
            while (it.moveToNext()) {
                list.add(cursorToAuditRecord(it))
            }
        }
        return list
    }

    /** Gets a single audit record by location UUID. */
    fun getAuditRecord(uuid: String): Map<String, Any?>? {
        val cursor = readableDatabase.rawQuery(
            "SELECT a.*, l.$COL_TIMESTAMP FROM $TABLE_AUDIT_TRAIL a " +
            "LEFT JOIN $TABLE_LOCATIONS l ON a.$COL_UUID = l.$COL_UUID " +
            "WHERE a.$COL_UUID = ?",
            arrayOf(uuid)
        )
        cursor.use {
            if (!it.moveToFirst()) return null
            val record = cursorToAuditRecord(it).toMutableMap()
            // Include the location timestamp for the AuditProof model
            val tsIdx = it.getColumnIndex(COL_TIMESTAMP)
            if (tsIdx >= 0) {
                record["timestamp"] = it.getLong(tsIdx)
            }
            return record
        }
    }

    /**
     * Gets a location's flat fields for audit hash re-computation.
     * Returns a map with flat keys (latitude, longitude, etc.) or null.
     */
    fun getLocationForAudit(uuid: String): Map<String, Any?>? {
        val cursor = readableDatabase.rawQuery(
            "SELECT * FROM $TABLE_LOCATIONS WHERE $COL_UUID = ?",
            arrayOf(uuid)
        )
        cursor.use {
            if (!it.moveToFirst()) return null
            return mapOf(
                "uuid" to it.getString(it.getColumnIndexOrThrow(COL_UUID)),
                "latitude" to it.getDouble(it.getColumnIndexOrThrow(COL_LATITUDE)),
                "longitude" to it.getDouble(it.getColumnIndexOrThrow(COL_LONGITUDE)),
                "altitude" to it.getDouble(it.getColumnIndexOrThrow(COL_ALTITUDE)),
                "speed" to it.getDouble(it.getColumnIndexOrThrow(COL_SPEED)),
                "heading" to it.getDouble(it.getColumnIndexOrThrow(COL_HEADING)),
                "accuracy" to it.getDouble(it.getColumnIndexOrThrow(COL_ACCURACY)),
                "timestamp" to it.getLong(it.getColumnIndexOrThrow(COL_TIMESTAMP)),
                "isMoving" to (it.getInt(it.getColumnIndexOrThrow(COL_IS_MOVING)) == 1),
                "odometer" to it.getDouble(it.getColumnIndexOrThrow(COL_ODOMETER)),
            )
        }
    }

    /**
     * Gets all audit records joined with their locations in a single query.
     * Each map includes audit fields (uuid, hash, previous_hash, chain_index)
     * plus location fields (latitude, longitude, altitude, speed, heading,
     * accuracy, timestamp, isMoving, odometer). Missing locations yield nulls.
     */
    fun getAuditTrailWithLocations(): List<Map<String, Any?>> {
        val cursor = readableDatabase.rawQuery(
            "SELECT a.$COL_UUID, a.$COL_AUDIT_HASH, a.$COL_AUDIT_PREVIOUS_HASH, " +
            "a.$COL_AUDIT_CHAIN_INDEX, " +
            "l.$COL_LATITUDE, l.$COL_LONGITUDE, l.$COL_ALTITUDE, " +
            "l.$COL_SPEED, l.$COL_HEADING, l.$COL_ACCURACY, " +
            "l.$COL_TIMESTAMP, l.$COL_IS_MOVING, l.$COL_ODOMETER " +
            "FROM $TABLE_AUDIT_TRAIL a " +
            "LEFT JOIN $TABLE_LOCATIONS l ON a.$COL_UUID = l.$COL_UUID " +
            "ORDER BY a.$COL_AUDIT_CHAIN_INDEX ASC",
            null
        )
        val list = mutableListOf<Map<String, Any?>>()
        cursor.use {
            while (it.moveToNext()) {
                val uuidIdx = it.getColumnIndex(COL_UUID)
                val latIdx = it.getColumnIndex(COL_LATITUDE)
                val lngIdx = it.getColumnIndex(COL_LONGITUDE)
                val altIdx = it.getColumnIndex(COL_ALTITUDE)
                val spdIdx = it.getColumnIndex(COL_SPEED)
                val hdgIdx = it.getColumnIndex(COL_HEADING)
                val accIdx = it.getColumnIndex(COL_ACCURACY)
                val tsIdx = it.getColumnIndex(COL_TIMESTAMP)
                val movIdx = it.getColumnIndex(COL_IS_MOVING)
                val odoIdx = it.getColumnIndex(COL_ODOMETER)

                val hasLocation = latIdx >= 0 && !it.isNull(latIdx)

                list.add(mapOf(
                    "uuid" to it.getString(it.getColumnIndexOrThrow(COL_UUID)),
                    "hash" to it.getString(it.getColumnIndexOrThrow(COL_AUDIT_HASH)),
                    "previous_hash" to it.getString(it.getColumnIndexOrThrow(COL_AUDIT_PREVIOUS_HASH)),
                    "chain_index" to it.getInt(it.getColumnIndexOrThrow(COL_AUDIT_CHAIN_INDEX)),
                    "has_location" to hasLocation,
                    "latitude" to if (hasLocation && latIdx >= 0) it.getDouble(latIdx) else null,
                    "longitude" to if (hasLocation && lngIdx >= 0) it.getDouble(lngIdx) else null,
                    "altitude" to if (hasLocation && altIdx >= 0) it.getDouble(altIdx) else null,
                    "speed" to if (hasLocation && spdIdx >= 0) it.getDouble(spdIdx) else null,
                    "heading" to if (hasLocation && hdgIdx >= 0) it.getDouble(hdgIdx) else null,
                    "accuracy" to if (hasLocation && accIdx >= 0) it.getDouble(accIdx) else null,
                    "timestamp" to if (hasLocation && tsIdx >= 0) it.getLong(tsIdx) else null,
                    "isMoving" to if (hasLocation && movIdx >= 0) (it.getInt(movIdx) == 1) else null,
                    "odometer" to if (hasLocation && odoIdx >= 0) it.getDouble(odoIdx) else null,
                ))
            }
        }
        return list
    }

    /** Deletes all audit trail records. */
    fun deleteAllAuditRecords(): Boolean {
        writableDatabase.delete(TABLE_AUDIT_TRAIL, null, null)
        return true
    }

    private fun cursorToAuditRecord(c: Cursor): Map<String, Any?> {
        return mapOf(
            "uuid" to c.getString(c.getColumnIndexOrThrow(COL_UUID)),
            "hash" to c.getString(c.getColumnIndexOrThrow(COL_AUDIT_HASH)),
            "previous_hash" to c.getString(c.getColumnIndexOrThrow(COL_AUDIT_PREVIOUS_HASH)),
            "chain_index" to c.getInt(c.getColumnIndexOrThrow(COL_AUDIT_CHAIN_INDEX)),
        )
    }

    // =========================================================================
    // Privacy Zone CRUD
    // =========================================================================

    /** Inserts or replaces a privacy zone. */
    fun insertPrivacyZone(zone: Map<String, Any?>): Boolean {
        val values = ContentValues().apply {
            put(COL_IDENTIFIER, zone["identifier"] as? String ?: return false)
            put(COL_LATITUDE, (zone["latitude"] as? Number)?.toDouble() ?: return false)
            put(COL_LONGITUDE, (zone["longitude"] as? Number)?.toDouble() ?: return false)
            put(COL_RADIUS, (zone["radius"] as? Number)?.toDouble() ?: 200.0)
            put(COL_PZ_ACTION, (zone["action"] as? Number)?.toInt() ?: 0)
            put(COL_PZ_DEGRADED_ACCURACY, (zone["degradedAccuracyMeters"] as? Number)?.toDouble() ?: 1000.0)
        }
        writableDatabase.insertWithOnConflict(TABLE_PRIVACY_ZONES, null, values, SQLiteDatabase.CONFLICT_REPLACE)
        return true
    }

    /** Retrieves all privacy zones. */
    fun getPrivacyZones(): List<Map<String, Any?>> {
        val cursor = readableDatabase.rawQuery("SELECT * FROM $TABLE_PRIVACY_ZONES", null)
        val list = mutableListOf<Map<String, Any?>>()
        cursor.use {
            while (it.moveToNext()) {
                list.add(cursorToPrivacyZone(it))
            }
        }
        return list
    }

    /** Deletes a privacy zone by identifier. */
    fun deletePrivacyZone(identifier: String): Boolean {
        return writableDatabase.delete(TABLE_PRIVACY_ZONES, "$COL_IDENTIFIER = ?", arrayOf(identifier)) > 0
    }

    /** Deletes all privacy zones. */
    fun deleteAllPrivacyZones(): Boolean {
        writableDatabase.delete(TABLE_PRIVACY_ZONES, null, null)
        return true
    }

    private fun cursorToPrivacyZone(c: Cursor): Map<String, Any?> {
        return mapOf(
            "identifier" to c.getString(c.getColumnIndexOrThrow(COL_IDENTIFIER)),
            "latitude" to c.getDouble(c.getColumnIndexOrThrow(COL_LATITUDE)),
            "longitude" to c.getDouble(c.getColumnIndexOrThrow(COL_LONGITUDE)),
            "radius" to c.getDouble(c.getColumnIndexOrThrow(COL_RADIUS)),
            "action" to c.getInt(c.getColumnIndexOrThrow(COL_PZ_ACTION)),
            "degradedAccuracyMeters" to c.getDouble(c.getColumnIndexOrThrow(COL_PZ_DEGRADED_ACCURACY)),
        )
    }

    // =========================================================================
    // Database Encryption (Enterprise)
    // =========================================================================

    /**
     * Migrate an existing unencrypted database to encrypted.
     *
     * Uses SQLCipher's ATTACH + sqlcipher_export mechanism:
     * 1. Open existing unencrypted DB
     * 2. ATTACH a new encrypted DB with the given key
     * 3. Export all data via sqlcipher_export()
     * 4. Detach and replace the original file
     *
     * @param key The encryption key bytes
     * @param encryptionManager The manager to mark encryption complete
     * @return true on success
     */
    fun encryptDatabase(key: ByteArray, encryptionManager: DatabaseEncryptionManager): Boolean {
        return try {
            val dbPath = appContext.getDatabasePath(DB_NAME).absolutePath
            val encryptedPath = "$dbPath.encrypted"

            // Close the current database
            close()

            // Open the unencrypted database directly using SQLCipher
            val unencryptedDb = net.zetetic.database.sqlcipher.SQLiteDatabase.openDatabase(
                dbPath, "", null,
                net.zetetic.database.sqlcipher.SQLiteDatabase.OPEN_READWRITE, null, null
            )

            // Attach encrypted database and export
            val hexKey = key.joinToString("") { "%02x".format(it) }
            unencryptedDb.rawExecSQL("ATTACH DATABASE '$encryptedPath' AS encrypted KEY x'$hexKey'")
            unencryptedDb.rawExecSQL("SELECT sqlcipher_export('encrypted')")
            unencryptedDb.rawExecSQL("DETACH DATABASE encrypted")
            unencryptedDb.close()

            // Replace unencrypted with encrypted
            val originalFile = File(dbPath)
            val encryptedFile = File(encryptedPath)
            val walFile = File("$dbPath-wal")
            val shmFile = File("$dbPath-shm")

            // Delete WAL/SHM files from unencrypted DB
            walFile.delete()
            shmFile.delete()

            // Replace the database file
            if (encryptedFile.renameTo(originalFile)) {
                encryptionManager.markEncrypted()
                Log.i(TAG, "Database encrypted successfully")

                // Reinitialize (the DB is now SQLCipher-encrypted)
                synchronized(Companion) {
                    instance = null
                    TraceletDatabase(appContext, key).also { instance = it }
                }
                true
            } else {
                Log.e(TAG, "Failed to replace database file")
                // Reopen without encryption
                synchronized(Companion) {
                    instance = null
                    TraceletDatabase(appContext, ByteArray(0)).also { instance = it }
                }
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Database encryption failed", e)
            // Try to reopen the original database
            try {
                synchronized(Companion) {
                    instance = null
                    TraceletDatabase(appContext, ByteArray(0)).also { instance = it }
                }
            } catch (reopenEx: Exception) {
                Log.e(TAG, "Failed to reopen database after encryption failure", reopenEx)
            }
            false
        }
    }
}
