package com.tracelet.tracelet_android.util

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import android.util.Log
import com.tracelet.tracelet_android.ConfigManager

/**
 * Debug sound effects manager using SoundPool for low-latency playback.
 *
 * Sounds are only played when [ConfigManager.isDebug] returns true.
 * Sound files should be placed in res/raw/ as .ogg files.
 *
 * Built-in sound names:
 * - location_recorded
 * - motion_change_true (moving)
 * - motion_change_false (stationary)
 * - geofence_enter
 * - geofence_exit
 * - geofence_dwell
 * - http_success
 * - http_failure
 */
class SoundManager(
    private val context: Context,
    private val config: ConfigManager,
) {
    companion object {
        private const val TAG = "SoundManager"
    }

    private var soundPool: SoundPool? = null
    private val soundIds = mutableMapOf<String, Int>()
    private var isLoaded = false

    /** Initialize SoundPool and load sounds. */
    fun start() {
        if (soundPool != null) return

        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        soundPool = SoundPool.Builder()
            .setMaxStreams(3)
            .setAudioAttributes(attributes)
            .build()
            .also { pool ->
                pool.setOnLoadCompleteListener { _, _, status ->
                    if (status == 0) isLoaded = true
                }
                loadSoundsFromResources(pool)
            }
    }

    /** Stop SoundPool and release resources. */
    fun stop() {
        soundPool?.release()
        soundPool = null
        soundIds.clear()
        isLoaded = false
    }

    /** Play a sound by name if debug mode is enabled. */
    fun playSound(name: String): Boolean {
        if (!config.isDebug() && name != "") return false
        val pool = soundPool ?: return false
        val soundId = soundIds[name]
        if (soundId == null) {
            Log.w(TAG, "Sound not found: $name")
            return false
        }
        pool.play(soundId, 1.0f, 1.0f, 1, 0, 1.0f)
        return true
    }

    /** Play location recorded sound. */
    fun playLocationRecorded() = playDebugSound("location_recorded")

    /** Play motion change sound. */
    fun playMotionChange(isMoving: Boolean) =
        playDebugSound(if (isMoving) "motion_change_true" else "motion_change_false")

    /** Play geofence sound. */
    fun playGeofence(action: String) = when (action) {
        "ENTER" -> playDebugSound("geofence_enter")
        "EXIT" -> playDebugSound("geofence_exit")
        "DWELL" -> playDebugSound("geofence_dwell")
        else -> false
    }

    /** Play HTTP result sound. */
    fun playHttpResult(success: Boolean) =
        playDebugSound(if (success) "http_success" else "http_failure")

    // =========================================================================
    // Private
    // =========================================================================

    private fun playDebugSound(name: String): Boolean {
        if (!config.isDebug()) return false
        return playSound(name)
    }

    private fun loadSoundsFromResources(pool: SoundPool) {
        val soundNames = listOf(
            "location_recorded",
            "motion_change_true",
            "motion_change_false",
            "geofence_enter",
            "geofence_exit",
            "geofence_dwell",
            "http_success",
            "http_failure",
        )

        for (name in soundNames) {
            val resId = context.resources.getIdentifier(name, "raw", context.packageName)
            if (resId != 0) {
                soundIds[name] = pool.load(context, resId, 1)
            }
        }
    }
}
