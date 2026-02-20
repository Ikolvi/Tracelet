package com.tracelet.tracelet_android.schedule

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.util.Log
import com.tracelet.tracelet_android.ConfigManager
import com.tracelet.tracelet_android.EventDispatcher
import com.tracelet.tracelet_android.StateManager
import java.util.Calendar
import java.util.TimeZone

/**
 * Schedule-based tracking engine.
 *
 * Parses schedule strings like "1-7 09:00-17:00" (day-of-week range + time range)
 * and uses AlarmManager to start/stop tracking at the specified times.
 */
class ScheduleManager(
    private val context: Context,
    private val config: ConfigManager,
    private val state: StateManager,
    private val events: EventDispatcher,
) {
    companion object {
        private const val TAG = "ScheduleManager"
        private const val ACTION_SCHEDULE_START = "com.tracelet.SCHEDULE_START"
        private const val ACTION_SCHEDULE_STOP = "com.tracelet.SCHEDULE_STOP"
        private const val REQUEST_CODE_START = 9001
        private const val REQUEST_CODE_STOP = 9002
    }

    var onScheduleStart: (() -> Unit)? = null
    var onScheduleStop: (() -> Unit)? = null

    private var scheduleReceiver: BroadcastReceiver? = null

    /** Start the schedule engine. Reads schedule strings from config. */
    fun start() {
        val schedules = config.getSchedule()
        if (schedules.isEmpty()) return

        state.schedulerEnabled = true
        registerReceiver()
        scheduleNext(schedules)
    }

    /** Stop the schedule engine. */
    fun stop() {
        state.schedulerEnabled = false
        cancelAlarms()
        unregisterReceiver()
    }

    /** Parse schedule strings and determine if tracking should be active now. */
    fun isWithinSchedule(): Boolean {
        val schedules = config.getSchedule()
        if (schedules.isEmpty()) return false

        val now = Calendar.getInstance()
        for (schedule in schedules) {
            if (matchesSchedule(schedule, now)) return true
        }
        return false
    }

    // =========================================================================
    // Private
    // =========================================================================

    /**
     * Parses a schedule string: "dayStart-dayEnd HH:mm-HH:mm"
     * Day of week: 1=Monday, 7=Sunday (ISO 8601)
     */
    private fun matchesSchedule(schedule: String, now: Calendar): Boolean {
        val parts = schedule.trim().split(" ")
        if (parts.size != 2) return false

        val dayRange = parts[0].split("-")
        val timeRange = parts[1].split("-")
        if (dayRange.size != 2 || timeRange.size != 2) return false

        try {
            val dayStart = dayRange[0].toInt()
            val dayEnd = dayRange[1].toInt()

            val startParts = timeRange[0].split(":")
            val endParts = timeRange[1].split(":")
            val startHour = startParts[0].toInt()
            val startMinute = startParts[1].toInt()
            val endHour = endParts[0].toInt()
            val endMinute = endParts[1].toInt()

            // Convert Calendar day (1=Sunday) to ISO (1=Monday)
            var isoDayOfWeek = now.get(Calendar.DAY_OF_WEEK) - 1
            if (isoDayOfWeek == 0) isoDayOfWeek = 7

            if (isoDayOfWeek !in dayStart..dayEnd) return false

            val currentMinutes = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
            val startMinutes = startHour * 60 + startMinute
            val endMinutes = endHour * 60 + endMinute

            return currentMinutes in startMinutes until endMinutes
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse schedule: $schedule - ${e.message}")
            return false
        }
    }

    private fun scheduleNext(schedules: List<String>) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val now = Calendar.getInstance()

        // Find the next start and stop time from all schedule entries
        var nextStartMs = Long.MAX_VALUE
        var nextStopMs = Long.MAX_VALUE

        for (schedule in schedules) {
            val (startMs, stopMs) = calculateNextAlarms(schedule, now)
            if (startMs < nextStartMs) nextStartMs = startMs
            if (stopMs < nextStopMs) nextStopMs = stopMs
        }

        if (nextStartMs < Long.MAX_VALUE) {
            setAlarm(alarmManager, ACTION_SCHEDULE_START, REQUEST_CODE_START, nextStartMs)
        }
        if (nextStopMs < Long.MAX_VALUE) {
            setAlarm(alarmManager, ACTION_SCHEDULE_STOP, REQUEST_CODE_STOP, nextStopMs)
        }
    }

    private fun calculateNextAlarms(schedule: String, now: Calendar): Pair<Long, Long> {
        val parts = schedule.trim().split(" ")
        if (parts.size != 2) return Pair(Long.MAX_VALUE, Long.MAX_VALUE)

        try {
            val timeRange = parts[1].split("-")
            val startParts = timeRange[0].split(":")
            val endParts = timeRange[1].split(":")

            val start = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, startParts[0].toInt())
                set(Calendar.MINUTE, startParts[1].toInt())
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
                if (before(now)) add(Calendar.DAY_OF_MONTH, 1)
            }

            val stop = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, endParts[0].toInt())
                set(Calendar.MINUTE, endParts[1].toInt())
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
                if (before(now)) add(Calendar.DAY_OF_MONTH, 1)
            }

            return Pair(start.timeInMillis, stop.timeInMillis)
        } catch (e: Exception) {
            return Pair(Long.MAX_VALUE, Long.MAX_VALUE)
        }
    }

    private fun setAlarm(alarmManager: AlarmManager, action: String, requestCode: Int, triggerAtMs: Long) {
        val intent = Intent(action).setPackage(context.packageName)
        val pi = PendingIntent.getBroadcast(
            context, requestCode, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
            } else {
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
            }
        } catch (e: SecurityException) {
            // Fallback for devices restricting exact alarms
            alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
        }
    }

    private fun cancelAlarms() {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        for ((action, code) in listOf(
            ACTION_SCHEDULE_START to REQUEST_CODE_START,
            ACTION_SCHEDULE_STOP to REQUEST_CODE_STOP
        )) {
            val intent = Intent(action).setPackage(context.packageName)
            val pi = PendingIntent.getBroadcast(
                context, code, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarmManager.cancel(pi)
        }
    }

    private fun registerReceiver() {
        scheduleReceiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                when (intent?.action) {
                    ACTION_SCHEDULE_START -> {
                        Log.d(TAG, "Schedule start triggered")
                        onScheduleStart?.invoke()
                        events.sendSchedule(state.toMap())
                        // Re-schedule for next occurrence
                        scheduleNext(config.getSchedule())
                    }
                    ACTION_SCHEDULE_STOP -> {
                        Log.d(TAG, "Schedule stop triggered")
                        onScheduleStop?.invoke()
                        events.sendSchedule(state.toMap())
                        scheduleNext(config.getSchedule())
                    }
                }
            }
        }

        val filter = IntentFilter().apply {
            addAction(ACTION_SCHEDULE_START)
            addAction(ACTION_SCHEDULE_STOP)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(scheduleReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(scheduleReceiver, filter)
        }
    }

    private fun unregisterReceiver() {
        scheduleReceiver?.let {
            try { context.unregisterReceiver(it) } catch (_: Exception) {}
        }
        scheduleReceiver = null
    }
}
