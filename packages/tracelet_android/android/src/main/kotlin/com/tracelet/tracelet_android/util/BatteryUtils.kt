package com.tracelet.tracelet_android.util

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build

/**
 * Utility for reading device battery state.
 */
object BatteryUtils {

    /** Returns current battery level as a fraction (0.0 – 1.0). */
    fun getBatteryLevel(context: Context): Double {
        val bm = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
        if (bm != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val level = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
            if (level >= 0) return level / 100.0
        }
        // Fallback: sticky broadcast
        val intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        if (intent != null) {
            val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
            if (level >= 0 && scale > 0) return level.toDouble() / scale
        }
        return -1.0
    }

    /** Returns whether the device is currently charging. */
    fun isCharging(context: Context): Boolean {
        val intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        if (intent != null) {
            val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
            return status == BatteryManager.BATTERY_STATUS_CHARGING ||
                    status == BatteryManager.BATTERY_STATUS_FULL
        }
        return false
    }

    /** Returns battery info as a map. */
    fun getBatteryInfo(context: Context): Map<String, Any?> {
        return mapOf(
            "level" to getBatteryLevel(context),
            "isCharging" to isCharging(context),
        )
    }
}
