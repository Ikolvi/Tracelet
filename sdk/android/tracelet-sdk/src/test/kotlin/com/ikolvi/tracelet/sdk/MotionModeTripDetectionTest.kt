package com.ikolvi.tracelet.sdk

import android.Manifest
import android.app.Application
import android.content.Context
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.sdk.model.MotionDetectionMode
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * #442: a trip driven by `changePace()` must reach the native trip manager in
 * every motion mode. SMART left `handleMotionStateChange` before feeding it,
 * and SPEED transitions never called it, so neither produced a native trip:
 * no `trip_id` on rows (#402) and no stored summary (#401). Found on a device,
 * where the #401 card saw `onTrip` but an empty `context.trips`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class MotionModeTripDetectionTest {

    private lateinit var context: Context
    private lateinit var sdk: TraceletSdk
    private val motionEvents = mutableListOf<Map<String, Any?>>()

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        shadowOf(context as Application).grantPermissions(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
            Manifest.permission.ACCESS_BACKGROUND_LOCATION,
        )
        androidx.work.testing.WorkManagerTestInitHelper.initializeTestWorkManager(
            context,
            androidx.work.Configuration.Builder()
                .setExecutor(androidx.work.testing.SynchronousExecutor())
                .build(),
        )
        resetSdkSingleton()
        sdk = TraceletSdk.getInstance(context)
        sdk.setEventSender(object : TraceletEventSender by ListenerEventSender() {
            override fun sendMotionChange(data: Map<String, Any?>) {
                motionEvents += data
            }
        })
        sdk.initialize()
    }

    @After
    fun tearDown() {
        try { sdk.stop() } catch (_: Exception) {}
        shadowOf(Looper.getMainLooper()).idle()
        StateManager(context).reset()
        ConfigManager.resetInstance()
        resetSdkSingleton()
    }

    private fun resetSdkSingleton() {
        TraceletSdk::class.java.getDeclaredField("instance").apply {
            isAccessible = true
            set(null, null)
        }
    }

    private fun idle() = shadowOf(Looper.getMainLooper()).idle()

    private fun driveTripIn(mode: MotionDetectionMode) {
        sdk.ready(mapOf("motionDetectionMode" to mode.value, "isMoving" to false)) {}
        idle()
        sdk.start()
        idle()
        val before = sdk.rustDatabase!!.getTrips(1000).map { it.tripId }.toSet()

        sdk.changePace(true)
        idle()
        val startedId = motionEvents.lastOrNull { it["tripId"] != null }?.get("tripId") as? String
        assertNotNull(startedId, "$mode: the moving motion change carries a native trip id")
        assertEquals(startedId, sdk.tripManager.currentTripId)

        sdk.changePace(false)
        idle()

        val stored = sdk.rustDatabase!!.getTrips(1000).filter { it.tripId !in before }
        assertTrue(
            stored.any { it.tripId == startedId },
            "$mode: the trip's summary was stored under the id the events carried (#401)",
        )
    }

    @Test
    fun `smart mode records native trips`() = driveTripIn(MotionDetectionMode.SMART)

    @Test
    fun `speed mode records native trips`() = driveTripIn(MotionDetectionMode.SPEED)

    @Test
    fun `accelerometer mode still records native trips`() =
        driveTripIn(MotionDetectionMode.ACCELEROMETER)

    @Test
    fun `re-sending the current state starts no trip`() {
        sdk.ready(mapOf("isMoving" to false)) {}
        idle()
        sdk.start()
        idle()
        sdk.getEventSender().sendMotionChange(mapOf("is_moving" to false))
        sdk.getEventSender().sendMotionChange(mapOf("is_moving" to false))
        assertEquals(null, sdk.tripManager.currentTripId)
    }
}
