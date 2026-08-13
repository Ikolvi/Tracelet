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

    /**
     * An arbitrary sentinel `when`, chosen only to be distinct from every
     * value these tests supply as `startedAt`/`now`. It is an ordinary valid
     * `Long` — nothing about [applyChronometer] makes 4242 structurally
     * uncomputable, it just never arises from the inputs used below, so any
     * change away from it is attributable to the function under test.
     */
    private val sentinelWhen = 4242L

    /**
     * A builder pre-seeded with the *opposite* of everything
     * [applyChronometer] can write, so that each of its three setters is
     * individually detectable.
     *
     * Seeding matters. `NotificationCompat.Builder` defaults `showWhen` to true
     * and calls `setShowWhen` unconditionally at build time, so on a plain
     * builder `EXTRA_SHOW_WHEN` is true whether or not the production code
     * touched it — asserting true there pins nothing, and asserting it equals a
     * fresh control's value does not catch a regression that sets it true. From
     * `showWhen = false`, true means `setShowWhen(true)` was called and nothing
     * else. Likewise `when`: a plain builder stamps creation time into it, so
     * there is no stable value to compare; from [sentinelWhen], any change
     * means `setWhen` was called.
     */
    private fun seededBuilder() = builder()
        .setWhen(sentinelWhen)
        .setShowWhen(false)
        .setUsesChronometer(false)

    // These two pin the *final state* on this path: `when` still holds the
    // sentinel, showWhen is still false, chronometer is still false. A
    // regression that called setWhen/setShowWhen/setUsesChronometer with a
    // value *different* from the seed fails here. These are state
    // assertions, not call assertions, so they cannot see a regression that
    // called one of those setters with the value already seeded (e.g. a
    // stray setShowWhen(false)) — that would land on the identical final
    // state and pass undetected.
    //
    // (An earlier revision asserted on extras key *presence*, which could never
    // pass — NotificationCompatBuilder writes both extras unconditionally, so
    // they are always present and merely false. The production code was correct
    // throughout.)
    @Test
    fun `timer disabled — final notification state holds none of the chronometer fields`() {
        val notification = seededBuilder().also {
            applyChronometer(it, showTimer = false, startedAt = 1000L, now = 2000L)
        }.build()

        assertFalse(notification.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER))
        assertFalse(notification.extras.getBoolean(Notification.EXTRA_SHOW_WHEN))
        assertEquals(sentinelWhen, notification.`when`)
    }

    @Test
    fun `missing startedAt — final notification state holds none of the chronometer fields`() {
        val notification = seededBuilder().also {
            applyChronometer(it, showTimer = true, startedAt = null, now = 2000L)
        }.build()

        assertFalse(notification.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER))
        assertFalse(notification.extras.getBoolean(Notification.EXTRA_SHOW_WHEN))
        assertEquals(sentinelWhen, notification.`when`)
    }

    // The positive pair use the same seeded builder, so each assertion is a
    // change away from the seed rather than a coincidence with a default.
    @Test
    fun `past startedAt enables count-up from the supplied instant`() {
        val notification = seededBuilder().also {
            applyChronometer(it, showTimer = true, startedAt = 1000L, now = 2000L)
        }.build()

        assertEquals(1000L, notification.`when`)
        assertTrue(notification.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER))
        assertTrue(notification.extras.getBoolean(Notification.EXTRA_SHOW_WHEN))
    }

    @Test
    fun `future startedAt is clamped to the supplied now`() {
        val notification = seededBuilder().also {
            applyChronometer(it, showTimer = true, startedAt = 3000L, now = 2000L)
        }.build()

        assertEquals(2000L, notification.`when`)
        assertTrue(notification.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER))
        assertTrue(notification.extras.getBoolean(Notification.EXTRA_SHOW_WHEN))
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
