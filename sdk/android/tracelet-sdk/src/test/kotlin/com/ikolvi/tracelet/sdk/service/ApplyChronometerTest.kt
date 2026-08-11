package com.ikolvi.tracelet.sdk.service

import android.app.Notification
import android.content.Context
import androidx.core.app.NotificationCompat
import androidx.test.core.app.ApplicationProvider
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [30])
class ApplyChronometerTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()

    private fun builder() = NotificationCompat.Builder(context, "test")
        .setSmallIcon(android.R.drawable.ic_menu_mylocation)

    @Test
    fun `timer disabled leaves builder untouched`() {
        val notification = builder().also {
            applyChronometer(it, showTimer = false, startedAt = 1000L, now = 2000L)
        }.build()

        assertFalse(notification.extras.containsKey(Notification.EXTRA_SHOW_CHRONOMETER))
    }

    @Test
    fun `missing startedAt leaves builder untouched`() {
        val notification = builder().also {
            applyChronometer(it, showTimer = true, startedAt = null, now = 2000L)
        }.build()

        assertFalse(notification.extras.containsKey(Notification.EXTRA_SHOW_CHRONOMETER))
    }

    @Test
    fun `past startedAt enables count-up from persisted instant`() {
        val notification = builder().also {
            applyChronometer(it, showTimer = true, startedAt = 1000L, now = 2000L)
        }.build()

        assertEquals(1000L, notification.`when`)
        assertTrue(notification.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER))
        assertTrue(notification.extras.getBoolean(Notification.EXTRA_SHOW_WHEN))
    }

    @Test
    fun `future startedAt is clamped to render-time now`() {
        val notification = builder().also {
            applyChronometer(it, showTimer = true, startedAt = 3000L, now = 2000L)
        }.build()

        assertEquals(2000L, notification.`when`)
        assertTrue(notification.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER))
    }

    @Test
    fun `alert-once defaults off at the builder`() {
        val notification = builder().also {
            applyOnlyAlertOnce(it, onlyAlertOnce = false)
        }.build()

        assertEquals(0, notification.flags and Notification.FLAG_ONLY_ALERT_ONCE)
    }

    @Test
    fun `alert-once true reaches the builder`() {
        val notification = builder().also {
            applyOnlyAlertOnce(it, onlyAlertOnce = true)
        }.build()

        assertEquals(
            Notification.FLAG_ONLY_ALERT_ONCE,
            notification.flags and Notification.FLAG_ONLY_ALERT_ONCE,
        )
    }
}
