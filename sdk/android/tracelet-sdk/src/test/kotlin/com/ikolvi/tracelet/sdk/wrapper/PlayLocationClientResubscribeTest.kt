package com.ikolvi.tracelet.sdk.wrapper

import android.location.Location
import android.os.Build
import android.os.Looper
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.kotlin.any
import org.mockito.kotlin.argumentCaptor
import org.mockito.kotlin.mock
import org.mockito.kotlin.times
import org.mockito.kotlin.verify
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * #432: re-requesting with the same [TraceletLocationCallback] must replace the
 * fused subscription, not add a second one that `removeLocationUpdates` can no
 * longer reach.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P])
class PlayLocationClientResubscribeTest {

    private val fused = mock<FusedLocationProviderClient>()
    private val client = PlayLocationClient(fused)

    private fun request(intervalMs: Long) =
        TraceletLocationRequest(TraceletLocationPriority.PRIORITY_HIGH_ACCURACY, intervalMs)

    private class CountingCallback : TraceletLocationCallback {
        var fixes = 0
        override fun onLocationResult(locations: List<Location>) { fixes += locations.size }
        override fun onLocationAvailability(isLocationAvailable: Boolean) {}
    }

    private fun registeredPlayCallbacks(count: Int): List<LocationCallback> {
        val captor = argumentCaptor<LocationCallback>()
        verify(fused, times(count))
            .requestLocationUpdates(any<LocationRequest>(), captor.capture(), any<Looper>())
        return captor.allValues
    }

    @Test
    fun reRequestReusesTheSamePlayCallback() {
        val callback = CountingCallback()
        client.requestLocationUpdates(request(1000), callback, Looper.getMainLooper())
        client.requestLocationUpdates(request(5000), callback, Looper.getMainLooper())

        val registered = registeredPlayCallbacks(2)
        assertSame(
            "the fused client only replaces a request when it gets the same LocationCallback",
            registered[0], registered[1],
        )
    }

    @Test
    fun removeAfterReRequestRemovesTheOnlyRegistration() {
        val callback = CountingCallback()
        client.requestLocationUpdates(request(1000), callback, Looper.getMainLooper())
        client.requestLocationUpdates(request(5000), callback, Looper.getMainLooper())
        client.removeLocationUpdates(callback)

        val registered = registeredPlayCallbacks(2)
        val removed = argumentCaptor<LocationCallback>()
        verify(fused).removeLocationUpdates(removed.capture())
        assertSame(registered[1], removed.firstValue)
        assertSame(registered[0], removed.firstValue)
    }

    @Test
    fun deliveryAfterRemoveIsDroppedAndUnregistersTheWrapper() {
        val callback = CountingCallback()
        client.requestLocationUpdates(request(5000), callback, Looper.getMainLooper())
        val playCallback = registeredPlayCallbacks(1).single()
        client.removeLocationUpdates(callback)

        // removeLocationUpdates is asynchronous: a fix already in the pipeline
        // still arrives on the wrapper after it returns.
        playCallback.onLocationResult(LocationResult.create(listOf(Location("fused"))))

        assertEquals(0, callback.fixes)
        // Once by removeLocationUpdates, once more by the wrapper itself.
        verify(fused, times(2)).removeLocationUpdates(playCallback)
    }

    @Test
    fun currentWrapperStillDelivers() {
        val callback = CountingCallback()
        client.requestLocationUpdates(request(5000), callback, Looper.getMainLooper())
        val playCallback = registeredPlayCallbacks(1).single()

        playCallback.onLocationResult(LocationResult.create(listOf(Location("fused"))))

        assertEquals(1, callback.fixes)
    }
}
