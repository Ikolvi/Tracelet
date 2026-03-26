package com.ikolvi.tracelet.sdk.util

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build

/**
 * Utility for reading device battery state.
 *
 * Caches results with a 30-second TTL to avoid expensive sticky broadcast
 * queries and [BatteryManager] IPC on every location update.
 */
object BatteryUtils {

    private const val CACHE_TTL_MS = 30_000L

    @Volatile private var cachedLevel: Double = -1.0
    @Volatile private var cachedCharging: Boolean = false
    @Volatile private var lastQueryTime: Long = 0L

    /** Invalidate the cache — call when battery state changes. */
    fun invalidateCache() {
        lastQueryTime = 0L
    }

    /** Returns current battery level as a fraction (0.0 – 1.0). */
    fun getBatteryLevel(context: Context): Double {
        refreshIfStale(context)
        return cachedLevel
    }

    /** Returns whether the device is currently charging. */
    fun isCharging(context: Context): Boolean {
        refreshIfStale(context)
        return cachedCharging
    }

    /** Returns battery info as a map. */
    fun getBatteryInfo(context: Context): Map<String, Any?> {
        refreshIfStale(context)
        return mapOf(
            "level" to cachedLevel,
            "is_charging" to cachedCharging,
        )
    }

    private fun refreshIfStale(context: Context) {
        val now = System.currentTimeMillis()
        if (now - lastQueryTime < CACHE_TTL_MS) return

        // Query battery level via BatteryManager (no IPC broadcast)
        val bm = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
        var level = -1.0
        if (bm != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val lvl = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
            if (lvl >= 0) level = lvl / 100.0
        }
        if (level < 0) {
            // Fallback: sticky broadcast
            val intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            if (intent != null) {
                val raw = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
                if (raw >= 0 && scale > 0) level = raw.toDouble() / scale
            }
        }

        // Query charging status via sticky broadcast (once per TTL)
        val intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        var charging = false
        if (intent != null) {
            val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
            charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                    status == BatteryManager.BATTERY_STATUS_FULL
        }

        cachedLevel = level
        cachedCharging = charging
        lastQueryTime = now
    }
}
