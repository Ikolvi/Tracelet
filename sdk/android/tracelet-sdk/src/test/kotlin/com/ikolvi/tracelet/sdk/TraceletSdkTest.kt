package com.ikolvi.tracelet.sdk

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.sdk.db.TraceletDatabase
import com.ikolvi.tracelet.sdk.geofence.GeofenceManager
import com.ikolvi.tracelet.sdk.http.HttpSyncManager
import com.ikolvi.tracelet.sdk.location.LocationEngine
import com.ikolvi.tracelet.sdk.motion.MotionDetector
import com.ikolvi.tracelet.sdk.schedule.ScheduleManager
import com.ikolvi.tracelet.sdk.util.SoundManager
import com.ikolvi.tracelet.sdk.util.TraceletLogger
import com.ikolvi.tracelet.sdk.util.TraceletPermissionManager
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.lang.reflect.Field
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

/**
 * Unit tests for [TraceletSdk] — the framework-agnostic Android SDK entry point.
 *
 * Tests cover:
 * - Singleton guarantees
 * - Event sender injection contract
 * - Lifecycle guards (start/stop/startGeofences/startPeriodic before ready)
 * - Carbon report calculation
 * - Permission delegation
 * - Heartbeat scheduling
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
internal class TraceletSdkTest {

    private lateinit var context: Context

    @Before
    fun setUp() {
        resetSingleton()
        ConfigManager.resetInstance()
        context = ApplicationProvider.getApplicationContext()
    }

    @After
    fun tearDown() {
        resetSingleton()
        ConfigManager.resetInstance()
    }

    private fun resetSingleton() {
        try {
            val field: Field = TraceletSdk::class.java.getDeclaredField("instance")
            field.isAccessible = true
            field.set(null, null)
        } catch (_: Exception) { }
    }

    // =========================================================================
    // Singleton
    // =========================================================================

    @Test
    fun getInstance_returnsSameInstance() {
        val a = TraceletSdk.getInstance(context)
        val b = TraceletSdk.getInstance(context)
        assertSame(a, b)
    }

    @Test
    fun getInstance_usesApplicationContext() {
        // Even if we pass a non-application context, it should use applicationContext
        val sdk = TraceletSdk.getInstance(context)
        assertNotNull(sdk)
    }

    // =========================================================================
    // Event sender injection
    // =========================================================================

    @Test(expected = IllegalStateException::class)
    fun initialize_throwsWithoutEventSender() {
        val sdk = TraceletSdk.getInstance(context)
        sdk.initialize()
    }

    @Test
    fun initialize_doesNotThrowStateException_withEventSender() {
        val sdk = TraceletSdk.getInstance(context)
        sdk.setEventSender(NoOpEventSender())
        try {
            sdk.initialize()
        } catch (_: java.security.KeyStoreException) {
            // Expected: EncryptedSharedPreferences needs Android Keystore.
            // The point is that no IllegalStateException was thrown (event sender was set).
        }
    }

    @Test
    fun getEventSender_returnsInjectedSender() {
        val sdk = TraceletSdk.getInstance(context)
        val sender = NoOpEventSender()
        sdk.setEventSender(sender)
        assertSame(sender, sdk.getEventSender())
    }

    // =========================================================================
    // Lifecycle guards — must return error before ready()
    // =========================================================================

    @Test
    fun start_returnsNotReady_beforeReady() {
        val sdk = initSdk()
        assertEquals("NOT_READY", sdk.start())
    }

    @Test
    fun startGeofences_returnsNotReady_beforeReady() {
        val sdk = initSdk()
        assertEquals("NOT_READY", sdk.startGeofences())
    }

    @Test
    fun startPeriodic_returnsNotReady_beforeReady() {
        val sdk = initSdk()
        assertEquals("NOT_READY", sdk.startPeriodic())
    }

    @Test
    fun isReady_isFalseBeforeReady() {
        val sdk = initSdk()
        assertFalse(sdk.isReady)
    }

    // =========================================================================
    // Ready
    // =========================================================================

    @Test
    fun ready_setsIsReadyTrue() {
        val sdk = initSdk()
        var callbackState: Map<String, Any?>? = null

        sdk.ready(emptyMap()) { state -> callbackState = state }

        assertTrue(sdk.isReady)
        assertNotNull(callbackState)
    }

    @Test
    fun ready_callbackContainsStateKeys() {
        val sdk = initSdk()
        var callbackState: Map<String, Any?>? = null

        sdk.ready(emptyMap()) { state -> callbackState = state }

        assertNotNull(callbackState)
        // State map should contain standard keys
        assertTrue(callbackState!!.containsKey("enabled"))
        assertTrue(callbackState!!.containsKey("isMoving"))
        assertTrue(callbackState!!.containsKey("trackingMode"))
    }

    // =========================================================================
    // Start — permission denied
    // =========================================================================

    @Test
    fun start_returnsPermissionDenied_whenNoPermission() {
        val sdk = readySdk()
        val result = sdk.start()
        assertEquals("PERMISSION_DENIED", result)
    }

    // =========================================================================
    // getState
    // =========================================================================

    @Test
    fun getState_returnsMapWithEnabledFalse_initially() {
        val sdk = readySdk()
        val state = sdk.getState()
        assertEquals(false, state["enabled"])
    }

    // =========================================================================
    // setConfig
    // =========================================================================

    @Test
    fun setConfig_returnsUpdatedState() {
        val sdk = readySdk()
        val state = sdk.setConfig(mapOf("debug" to true))
        assertNotNull(state)
        assertTrue(state.containsKey("enabled"))
    }

    // =========================================================================
    // Reset
    // =========================================================================

    @Test
    fun reset_setsIsReadyFalse() {
        val sdk = readySdk()
        assertTrue(sdk.isReady)

        sdk.reset(null)
        assertFalse(sdk.isReady)
    }

    // =========================================================================
    // Carbon report — pure computation
    // =========================================================================

    @Test
    fun getCarbonReport_emptyDatabase_returnsZeroes() {
        val sdk = readySdk()
        val report = sdk.getCarbonReport(null)

        assertEquals(0.0, report["totalCarbonGrams"])
        assertEquals(0, report["totalTrips"])
        assertTrue((report["carbonByMode"] as Map<*, *>).isEmpty())
        assertTrue((report["distanceByMode"] as Map<*, *>).isEmpty())
    }

    // =========================================================================
    // Permissions
    // =========================================================================

    @Test
    fun getPermissionStatus_returnsNotGranted() {
        val sdk = readySdk()
        val status = sdk.getPermissionStatus()
        // Without permissions granted, status should not be ALWAYS
        assertTrue(status != 3) // STATUS_ALWAYS = 3
    }

    @Test
    fun requestPermission_withNoActivity_callsBackImmediately() {
        val sdk = readySdk()
        sdk.activity = null
        var callbackStatus: Int? = null

        sdk.requestPermission { status -> callbackStatus = status }

        assertNotNull(callbackStatus)
    }

    // =========================================================================
    // Activity
    // =========================================================================

    @Test
    fun activity_defaultsToNull() {
        val sdk = initSdk()
        assertNull(sdk.activity)
    }

    // =========================================================================
    // Heartbeat
    // =========================================================================

    @Test
    fun stopHeartbeat_doesNotCrash_whenNotStarted() {
        val sdk = initSdk()
        sdk.stopHeartbeat() // Should not throw
    }

    // =========================================================================
    // handlePermissionResult — unknown request code
    // =========================================================================

    @Test
    fun handlePermissionResult_returnsFalse_forUnknownRequestCode() {
        val sdk = readySdk()
        val handled = sdk.handlePermissionResult(
            999, emptyArray(), intArrayOf()
        )
        assertFalse(handled)
    }

    // =========================================================================
    // canScheduleExactAlarms
    // =========================================================================

    @Test
    fun canScheduleExactAlarms_returnsBoolean() {
        val sdk = readySdk()
        // Just verify it doesn't crash and returns a boolean
        val result = sdk.canScheduleExactAlarms()
        assertNotNull(result)
    }

    // =========================================================================
    // Haversine (tested indirectly via carbon report)
    // =========================================================================

    @Test
    fun carbonReport_withTimeRange_returnsZeroForEmptyRange() {
        val sdk = readySdk()
        val report = sdk.getCarbonReport(
            mapOf("from" to 0L, "to" to 1000L)
        )
        assertEquals(0.0, report["totalCarbonGrams"])
    }

    // =========================================================================
    // Helper — create initialized SDK via reflection (bypasses KeyStore)
    // =========================================================================

    /**
     * Manually wire subsystems using real instances where possible and mocks
     * where Android Keystore would fail. This avoids calling [TraceletSdk.initialize]
     * which depends on [DatabaseEncryptionManager] (requires Android Keystore).
     */
    private fun initSdk(): TraceletSdk {
        val sdk = TraceletSdk.getInstance(context)
        sdk.setEventSender(NoOpEventSender())

        // Wire subsystems via reflection since initialize() needs KeyStore
        val configManager = ConfigManager.getInstance(context)
        val stateManager = StateManager(context)
        val database = TraceletDatabase.getInstance(context)

        setField(sdk, "configManager", configManager)
        setField(sdk, "stateManager", stateManager)
        setField(sdk, "database", database)
        setField(sdk, "logger", TraceletLogger(context, configManager, database))
        setField(sdk, "soundManager", SoundManager(context, configManager))
        setField(sdk, "permissionManager", TraceletPermissionManager(context))

        // Mock subsystems that need Play Services or complex Android services
        setField(sdk, "locationEngine", mock(LocationEngine::class.java))
        setField(sdk, "motionDetector", mock(MotionDetector::class.java))
        setField(sdk, "geofenceManager", mock(GeofenceManager::class.java))
        setField(sdk, "httpSyncManager", mock(HttpSyncManager::class.java))
        setField(sdk, "scheduleManager", mock(ScheduleManager::class.java))
        setField(sdk, "auditTrailManager", mock(com.ikolvi.tracelet.sdk.audit.AuditTrailManager::class.java))
        setField(sdk, "privacyZoneManager", mock(com.ikolvi.tracelet.sdk.privacy.PrivacyZoneManager::class.java))
        setField(sdk, "encryptionManager", mock(com.ikolvi.tracelet.sdk.db.DatabaseEncryptionManager::class.java))
        setField(sdk, "deviceAttestor", mock(com.ikolvi.tracelet.sdk.attestation.DeviceAttestor::class.java))

        return sdk
    }

    private fun readySdk(): TraceletSdk {
        val sdk = initSdk()
        sdk.ready(emptyMap()) { /* no-op */ }
        return sdk
    }

    private fun setField(obj: Any, name: String, value: Any?) {
        val field = obj::class.java.getDeclaredField(name)
        field.isAccessible = true
        field.set(obj, value)
    }

    // =========================================================================
    // No-op event sender for testing
    // =========================================================================

    private class NoOpEventSender : TraceletEventSender {
        override fun sendLocation(data: Map<String, Any?>) {}
        override fun sendMotionChange(data: Map<String, Any?>) {}
        override fun sendActivityChange(data: Map<String, Any?>) {}
        override fun sendGeofencesChange(data: Map<String, Any?>) {}
        override fun sendGeofence(data: Map<String, Any?>) {}
        override fun sendHeartbeat(data: Map<String, Any?>) {}
        override fun sendHttp(data: Map<String, Any?>) {}
        override fun sendProviderChange(data: Map<String, Any?>) {}
        override fun sendConnectivityChange(data: Map<String, Any?>) {}
        override fun sendEnabledChange(enabled: Boolean) {}
        override fun sendPowerSaveChange(isPowerSaveMode: Boolean) {}
        override fun sendNotificationAction(action: String) {}
        override fun sendAuthorization(data: Map<String, Any?>) {}
        override fun sendRemoteConfigEvent(data: Map<String, Any?>) {}
        override fun sendSchedule(data: Map<String, Any?>) {}
        override fun sendWatchPosition(data: Map<String, Any?>) {}
        override fun sendTrip(data: Map<String, Any?>) {}
        override fun sendBudgetAdjustment(data: Map<String, Any?>) {}
        override fun hasListener(eventName: String): Boolean = false
    }
}
