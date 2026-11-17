package com.ikolvi.tracelet.sdk.wrapper

import android.content.Context
import android.location.LocationListener
import android.location.LocationManager
import android.os.Looper
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.kotlin.mock
import org.mockito.kotlin.any
import org.mockito.kotlin.argumentCaptor
import org.mockito.kotlin.eq
import org.mockito.kotlin.never
import org.mockito.kotlin.verify
import org.mockito.kotlin.whenever
import org.robolectric.RobolectricTestRunner
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

@RunWith(RobolectricTestRunner::class)
class TraceletServicesTest {

    private val context: Context = mock()

    @Before
    fun setUp() {
        TraceletServices.setProvider(null)
    }

    @After
    fun tearDown() {
        TraceletServices.setProvider(null)
    }

    @Test
    fun testDefaultProviderSelection() {
        // In a Robolectric environment without GMS on the classpath, 
        // it should fall back to AospServicesProvider.
        val provider = TraceletServices.getProvider(context)
        assertNotNull(provider)
        
        if (TraceletServices.isGmsAvailable(context)) {
            // If GMS happens to be on the classpath in the test environment
            assertIs<PlayServicesProvider>(provider)
        } else {
            assertIs<AospServicesProvider>(provider)
        }
    }

    @Test
    fun testSetCustomProvider() {
        val customProvider = object : TraceletServicesProvider {
            override fun getLocationClient(context: Context): TraceletLocationClient = mock()
            override fun getGeofencingClient(context: Context): TraceletGeofencingClient = mock()
            override fun getActivityRecognitionClient(context: Context): TraceletActivityRecognitionClient = mock()
            override fun getEventExtractor(): TraceletEventExtractor = mock()
        }

        TraceletServices.setProvider(customProvider)
        val provider = TraceletServices.getProvider(context)
        
        assertIs<TraceletServicesProvider>(provider)
        // Verify it's exactly our custom provider
        assert(provider === customProvider)
    }

    @Test
    fun testAospProviderReturnsAospClients() {
        val provider = AospServicesProvider()
        val locationClient = provider.getLocationClient(context)
        val geofencingClient = provider.getGeofencingClient(context)
        val activityClient = provider.getActivityRecognitionClient(context)
        val extractor = provider.getEventExtractor()

        assertIs<AospLocationClient>(locationClient)
        assertIs<AospGeofencingClient>(geofencingClient)
        assertIs<AospActivityRecognitionClient>(activityClient)
        assertIs<AospEventExtractor>(extractor)
    }

    @Test
    fun aospRetainsGpsWhenTheCoarseRequestHasNoEnabledProvider() {
        val manager = mock<LocationManager>()
        whenever(context.getSystemService(Context.LOCATION_SERVICE)).thenReturn(manager)
        whenever(manager.isProviderEnabled(LocationManager.GPS_PROVIDER)).thenReturn(true)
        val client = AospLocationClient(context)
        val callback = mock<TraceletLocationCallback>()
        val looper = Looper.getMainLooper()
        val high = TraceletLocationRequest(TraceletLocationPriority.PRIORITY_HIGH_ACCURACY, 1000)
        client.requestLocationUpdates(high, callback, looper)
        val listener = argumentCaptor<LocationListener>()
        verify(manager).requestLocationUpdates(
            eq(LocationManager.GPS_PROVIDER), any<Long>(), any<Float>(), listener.capture(), any<Looper>(),
        )

        var failed = false
        client.requestLocationUpdatesWithResult(
            high.copy(priority = TraceletLocationPriority.PRIORITY_LOW_POWER), callback, looper,
        ) { failed = it.isFailure }

        assertTrue(failed)
        verify(manager, never()).removeUpdates(any<LocationListener>())
        client.removeLocationUpdates(callback)
        verify(manager).removeUpdates(listener.firstValue)
    }
}
