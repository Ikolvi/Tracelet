package com.ikolvi.tracelet.sdk.util

import android.content.Context
import android.util.Log
import com.ikolvi.tracelet.sdk.ConfigManager

/**
 * Logger that writes to Android logcat.
 *
 * Log levels: OFF(0), ERROR(1), WARNING(2), INFO(3), DEBUG(4), VERBOSE(5)
 */
class TraceletLogger(
    private val context: Context,
    private val config: ConfigManager,
) {
    var rustDatabase: uniffi.tracelet_core.DatabaseManager? = null

    /** Writes since the last prune. See [logInternal]. */
    private val writesSincePrune = java.util.concurrent.atomic.AtomicInteger(0)

    companion object {
        private const val TAG = "Tracelet"

        /**
         * Amortization window for log pruning.
         *
         * Retention is 500-2000 rows, so letting the table run this many rows
         * past the limit between prunes is harmless, and it removes a DELETE
         * from every single log write.
         */
        private const val PRUNE_INTERVAL_WRITES = 50

        // Log level constants matching Dart LogLevel enum
        const val LEVEL_OFF = 0
        const val LEVEL_ERROR = 1
        const val LEVEL_WARNING = 2
        const val LEVEL_INFO = 3
        const val LEVEL_DEBUG = 4
        const val LEVEL_VERBOSE = 5

        fun levelToString(level: Int): String = when (level) {
            LEVEL_ERROR -> "ERROR"
            LEVEL_WARNING -> "WARNING"
            LEVEL_INFO -> "INFO"
            LEVEL_DEBUG -> "DEBUG"
            LEVEL_VERBOSE -> "VERBOSE"
            else -> "OFF"
        }
    }

    /** Log an error message. */
    fun error(message: String, tag: String = TAG) {
        logInternal(LEVEL_ERROR, message, tag)
    }

    /** Log a warning message. */
    fun warning(message: String, tag: String = TAG) {
        logInternal(LEVEL_WARNING, message, tag)
    }

    /** Log an info message. */
    fun info(message: String, tag: String = TAG) {
        logInternal(LEVEL_INFO, message, tag)
    }

    /** Log a debug message. */
    fun debug(message: String, tag: String = TAG) {
        logInternal(LEVEL_DEBUG, message, tag)
    }

    /** Log a verbose message. */
    fun verbose(message: String, tag: String = TAG) {
        logInternal(LEVEL_VERBOSE, message, tag)
    }

    /** Log with explicit level (from Dart). */
    fun log(level: String, message: String): Boolean {
        // Compare without allocating a new uppercase string (A-L2).
        val levelInt = when {
            level.equals("ERROR", ignoreCase = true) -> LEVEL_ERROR
            level.equals("WARNING", ignoreCase = true) || level.equals("WARN", ignoreCase = true) -> LEVEL_WARNING
            level.equals("INFO", ignoreCase = true) -> LEVEL_INFO
            level.equals("DEBUG", ignoreCase = true) -> LEVEL_DEBUG
            level.equals("VERBOSE", ignoreCase = true) -> LEVEL_VERBOSE
            else -> LEVEL_INFO
        }
        logInternal(levelInt, message, TAG)
        return true
    }

    /** Get the log as a string (optionally filtered). */
    fun getLog(query: Map<String, Any?>?): String {
        return try {
            val limit = (query?.get("limit") as? Number)?.toInt() ?: 500
            val logs = rustDatabase?.getLogs(limit) ?: emptyList()
            logs.joinToString("\n") { "[${it.timestamp}] [${it.level}] ${it.message}" }
        } catch (e: Exception) {
            "Failed to retrieve logs: ${e.message}"
        }
    }

    /** Delete all log entries. */
    fun destroyLog(): Boolean {
        return try {
            rustDatabase?.clearLogs()
            true
        } catch (e: Exception) {
            false
        }
    }

    /** Email the log (returns intent data; actual email launch is done by caller). */
    fun getLogForEmail(): String {
        return getLog(mapOf("limit" to 2000))
    }

    /**
     * Prune old logs based on config.
     *
     * Two independent caps, both of which must hold:
     * - a row count derived from [LEVEL] (a chatty VERBOSE session keeps more
     *   lines than an ERROR-only one), and
     * - `logMaxDays`, the retention window (#304). This was documented and
     *   configurable but never implemented — only the row cap existed, so the
     *   configured number of days was accepted and discarded. A row cap alone
     *   cannot express "keep two weeks", because how many rows that is depends
     *   entirely on how chatty the session was.
     *
     * `logMaxDays <= 0` disables the age cap and leaves the row cap in force.
     */
    fun pruneOldLogs() {
        try {
            val limit = when (config.getLogLevel()) {
                LEVEL_ERROR, LEVEL_OFF -> 500
                LEVEL_WARNING, LEVEL_INFO -> 1000
                LEVEL_DEBUG, LEVEL_VERBOSE -> 2000
                else -> 1000
            }
            rustDatabase?.pruneLogs(limit)
            rustDatabase?.pruneLogsOlderThan(config.getLogMaxDays())
        } catch (e: Exception) {
            Log.e(TAG, "Failed to prune logs: ${e.message}")
        }
    }

    // =========================================================================
    // Private
    // =========================================================================

    private fun logInternal(level: Int, message: String, tag: String) {
        val configLevel = config.getLogLevel()
        if (configLevel == LEVEL_OFF || level > configLevel) return

        // Write to Android logcat
        when (level) {
            LEVEL_ERROR -> Log.e(tag, message)
            LEVEL_WARNING -> Log.w(tag, message)
            LEVEL_INFO -> Log.i(tag, message)
            LEVEL_DEBUG -> Log.d(tag, message)
            LEVEL_VERBOSE -> Log.v(tag, message)
        }

        // Persist to Rust Core Database
        try {
            val levelName = levelToString(level)
            rustDatabase?.insertLog(levelName, message, "plugin")
            // Prune to maintain dynamic limits.
            //
            // Previously this ran a DELETE on every single log write. The
            // retention limits are 500-2000 rows, so pruning per write is pure
            // overhead — amortize it instead. Matters more now that geofence
            // transitions are logged at INFO.
            if (writesSincePrune.incrementAndGet() >= PRUNE_INTERVAL_WRITES) {
                writesSincePrune.set(0)
                pruneOldLogs()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to persist log to Rust Database: ${e.message}")
        }
    }
}

