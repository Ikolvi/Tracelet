package com.ikolvi.tracelet.sdk

import android.Manifest
import android.content.Context
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.sdk.model.SpeedMotionState
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * A fresh `start()` commits a pace from `motion.isMoving`, and the previous
 * session's persisted speed-motion state must not overrule it.
 *
 * [SpeedMotionManager.start] restores that state and treats anything but
 * STATIONARY as moving. `start()` adopted the restored value unconditionally, so
 * a session left MOVING — by a real wake-up, or simply by the MOVING default on
 * a machine that had never transitioned — came back as `isMoving=true` from a
 * `start()` the app had explicitly asked to begin stationary. Nothing surfaced
 * the override: the caller saw the state it did not ask for and no reason for
 * it, and the SMART coordinator had already been synced (#344) against the
 * committed pace it was about to disagree with.
 *
 * Only a *resume* inherits the pace now; a relaunched process has no other
 * record of what it was killed in, which is what the restore is for.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class StartCommittedPaceTest {

    private lateinit var context: Context
    private lateinit var sdk: TraceletSdk

    @Before
    fun setUp() {
        org.robolectric.shadows.ShadowLog.stream = System.out
        context = ApplicationProvider.getApplicationContext()

        // start()/stop() touch WorkManager (PeriodicLocationWorker.cancel) — stand
        // up the in-memory test scheduler so those calls don't throw.
        androidx.work.testing.WorkManagerTestInitHelper.initializeTestWorkManager(
            context,
            androidx.work.Configuration.Builder()
                .setExecutor(androidx.work.testing.SynchronousExecutor())
                .build(),
        )

        shadowOf(context as android.app.Application).grantPermissions(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
            Manifest.permission.ACCESS_BACKGROUND_LOCATION,
            Manifest.permission.ACTIVITY_RECOGNITION,
        )

        sdk = TraceletSdk.getInstance(context)
        sdk.setEventSender(ListenerEventSender())
        sdk.initialize()
    }

    @After
    fun tearDown() {
        try { sdk.stop() } catch (_: Exception) {}
        idle()
        ConfigManager.resetInstance()
    }

    private fun idle() = shadowOf(Looper.getMainLooper()).idle()

    /** ready() with a committed pace of [isMoving], in [mode] (1=SPEED, 2=SMART). */
    private fun ready(mode: Int, isMoving: Boolean) {
        var done = false
        sdk.ready(
            mapOf(
                "motionDetectionMode" to mode,
                "foregroundService" to false,
                "stopOnStationary" to false,
                "isMoving" to isMoving,
            ),
        ) { done = true }
        idle()
        assertTrue(done, "ready() callback should fire")

        // The SMART coordinator is process-scoped: it outlives stop() and the SDK
        // is a singleton, so its accelerometer flag survives from whichever test
        // ran before this one. A leftover accel=true makes any speed input read as
        // "still moving" and wakes the session for reasons this test is not about.
        // Park both inputs explicitly — the same thing a previous session settling
        // to stationary does in the field.
        sdk.changePace(false)
        idle()
    }

    /** What a previous session that ended moving leaves behind. */
    private fun leaveSpeedMachineMoving() {
        sdk.stateManager.speedMotionState = SpeedMotionState.MOVING
    }

    @Test
    fun `SMART start does not inherit a restored moving pace`() {
        ready(mode = 2, isMoving = false)
        leaveSpeedMachineMoving()

        sdk.start()
        idle()

        assertFalse(
            sdk.stateManager.isMoving,
            "motion.isMoving:false was committed by start(); a stale MOVING must not override it",
        )
        assertEquals(
            SpeedMotionState.STATIONARY,
            sdk.stateManager.speedMotionState,
            "the machine itself must be brought in line, not just the flag — a " +
                "MOVING machine falls to SLOWING on the first low-speed fix and " +
                "writes isMoving back to true",
        )
    }

    @Test
    fun `SPEED start does not inherit a restored moving pace`() {
        ready(mode = 1, isMoving = false)
        leaveSpeedMachineMoving()

        sdk.start()
        idle()

        assertFalse(sdk.stateManager.isMoving)
        assertEquals(SpeedMotionState.STATIONARY, sdk.stateManager.speedMotionState)
    }

    @Test
    fun `a resume still inherits the restored moving pace`() {
        ready(mode = 2, isMoving = false)
        leaveSpeedMachineMoving()
        // A resume does not re-read motion.isMoving; the persisted machine is the
        // only record of the pace the killed process was in.
        sdk.stateManager.isMoving = false

        sdk.start(isResume = true)
        idle()

        assertTrue(
            sdk.stateManager.isMoving,
            "a relaunched process must come back up in the pace it was killed in",
        )
    }

    /**
     * The regression these tests missed.
     *
     * `a resume still inherits the restored moving pace` asserts
     * `stateManager.isMoving`, and SLOWING counts as moving — so a machine that
     * has *already begun standing down* satisfies it. The seed a few lines after
     * the pace is adopted fed `lastEffectiveSpeed`, which is 0.0 in a process
     * that has handled no fix (a killed-state relaunch, exactly this case), and
     * that fabricated zero pushed MOVING -> SLOWING immediately. The session then
     * reached STATIONARY when the countdown expired and switched the continuous
     * stream off, which is what a user reports as tracking stopping after the app
     * is backgrounded or killed.
     *
     * Asserting the machine's own state rather than the boolean is what catches
     * it: MOVING and SLOWING are different, and only one of them is healthy.
     */
    @Test
    fun `a resumed session is not stood down by the startup seed`() {
        ready(mode = 2, isMoving = false)
        leaveSpeedMachineMoving()
        sdk.stateManager.isMoving = false

        sdk.start(isResume = true)
        idle()

        assertEquals(
            SpeedMotionState.MOVING,
            sdk.stateManager.speedMotionState,
            "a resume came up MOVING and no fix has been handled yet, so nothing has " +
                "reported a speed — seeding 0.0 starts the countdown to STATIONARY and " +
                "takes the continuous stream down with it",
        )
    }

    @Test
    fun `a moving committed pace is unaffected`() {
        ready(mode = 2, isMoving = true)
        sdk.stateManager.speedMotionState = SpeedMotionState.STATIONARY

        sdk.start()
        idle()

        assertTrue(
            sdk.stateManager.isMoving,
            "motion.isMoving:true forces MOVING — the restore path is skipped entirely",
        )
    }
}
