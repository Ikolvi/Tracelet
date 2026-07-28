package com.ikolvi.tracelet.sdk.receiver

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import com.ikolvi.tracelet.sdk.ListenerEventSender
import com.ikolvi.tracelet.sdk.TraceletBootstrap
import com.ikolvi.tracelet.sdk.TraceletSdk
import com.ikolvi.tracelet.sdk.impact.CrashConfirmStore
import com.ikolvi.tracelet.sdk.impact.PendingImpact
import com.ikolvi.tracelet.sdk.util.TraceletLog

/**
 * Process-death-safe crash/fall confirmation (#182).
 *
 * When the SDK emits a `potential_crash` / `potential_fall` candidate it both
 * persists it (see [CrashConfirmStore]) and schedules an exact wake-up alarm
 * for just after the candidate's confirmation deadline. In the normal case the
 * in-process poll loop confirms the candidate first and [cancel]s this alarm.
 * But a violent impact frequently triggers the OS to kill the app — taking the
 * poll loop (and the in-memory Rust detector) with it. This statically-declared
 * receiver fires from a fresh process, re-reads the persisted candidate and
 * re-emits the confirmed `crash` / `fall` so the host's SOS/escalation flow
 * still runs.
 *
 * The alarm fires at `confirmDeadlineMs + GUARD_MS` so that, when the process
 * is alive, the in-process confirmation (at the exact deadline) reliably wins
 * the race and cancels the alarm before it ever fires — keeping this path a
 * pure safety net with zero duplicate events.
 */
class CrashConfirmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent?.action != ACTION_CRASH_CONFIRM) return
        val id = intent.getLongExtra(EXTRA_ID, -1L)
        if (id < 0) return

        // Atomically take ownership; if the in-process path already confirmed or
        // the user cancelled, the candidate is gone and we deliver nothing.
        val candidate = CrashConfirmStore(context).claim(id) ?: run {
            TraceletLog.debug("CrashConfirm alarm: candidate #$id already resolved — ignoring")
            return
        }

        TraceletLog.warning(
            "CrashConfirm alarm: process-death safety net confirming ${candidate.confirmedKind} #$id",
        )

        try {
            val sdk = TraceletSdk.getInstance(context)
            // Ensure an event sender is wired (the host framework provides one
            // that can deliver/queue headlessly), then re-initialize if needed.
            try {
                sdk.deliverConfirmedImpact(candidate)
            } catch (_: UninitializedPropertyAccessException) {
                val sender = TraceletBootstrap.eventSenderFactory?.invoke(context)
                    ?: ListenerEventSender()
                sdk.setEventSender(sender)
                // initialize() now wires subsystems on a background thread and
                // returns immediately; wait for it before re-delivering, otherwise
                // deliverConfirmedImpact touches unset lateinit state and throws again.
                sdk.initialize()
                if (sdk.awaitInit()) {
                    sdk.deliverConfirmedImpact(candidate)
                } else {
                    TraceletLog.warning("CrashConfirm: SDK init not ready — impact delivery skipped")
                }
            }
        } catch (e: Exception) {
            TraceletLog.error("CrashConfirm alarm: failed to deliver confirmed impact — ${e.message}")
        }
    }

    companion object {
        const val ACTION_CRASH_CONFIRM = "com.tracelet.ACTION_CRASH_CONFIRM"
        const val EXTRA_ID = "candidate_id"

        /**
         * Margin added after the candidate's confirmation deadline before the
         * safety-net alarm fires, giving the in-process confirmation time to win
         * the race and cancel this alarm when the app is still alive.
         */
        private const val GUARD_MS = 3_000L

        /**
         * Schedules the exact wake-up alarm that re-confirms [p] if the process
         * dies before the in-process poll loop can. Uses
         * `setExactAndAllowWhileIdle` so it fires even in Doze — a crash often
         * leaves the phone motionless, which is exactly when Doze kicks in.
         */
        fun schedule(context: Context, p: PendingImpact) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE)
                as? AlarmManager ?: return
            val triggerAtMs = p.confirmDeadlineMs + GUARD_MS
            val pi = pendingIntent(context, p.id)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                    !alarmManager.canScheduleExactAlarms()
                ) {
                    // No exact-alarm permission — still allow-while-idle, just inexact.
                    alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
                    TraceletLog.warning("CrashConfirm: SCHEDULE_EXACT_ALARM not granted — using inexact alarm")
                    return
                }
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
                TraceletLog.debug("CrashConfirm: scheduled safety-net alarm for #${p.id}")
            } catch (e: SecurityException) {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
                TraceletLog.warning("CrashConfirm: exact alarm denied — using inexact alarm", e)
            }
        }

        /** Cancels the safety-net alarm for [id] (in-process confirm or cancel). */
        fun cancel(context: Context, id: Long) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE)
                as? AlarmManager ?: return
            alarmManager.cancel(pendingIntent(context, id))
        }

        private fun pendingIntent(context: Context, id: Long): PendingIntent {
            val intent = Intent(ACTION_CRASH_CONFIRM)
                .setClass(context, CrashConfirmReceiver::class.java)
                .putExtra(EXTRA_ID, id)
            return PendingIntent.getBroadcast(
                context,
                id.toInt(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}
