package com.ikolvi.tracelet.flutter

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.TlAuthorizationStatus
import com.ikolvi.tracelet.TlNotificationUpdate
import com.ikolvi.tracelet.flutter.service.HeadlessTaskService
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.TraceletSdk
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
class TraceletHostApiImplTest {

    @Before
    fun resetSdkSingletons() {
        TraceletSdk::class.java.getDeclaredField("instance").apply {
            isAccessible = true
            set(null, null)
        }
        ConfigManager.resetInstance()
    }

    @Test
    fun testRegisterHeadlessHeadersCallback_delegatesToService() {
        val context = mock(Context::class.java)
        val headlessService = mock(HeadlessTaskService::class.java)
        val hostApi = TraceletHostApiImpl(context, headlessService)

        hostApi.registerHeadlessHeadersCallback(listOf(100L, 200L)) {}

        org.mockito.Mockito.verify(headlessService).registerCallbacks(
            HeadlessTaskService.CallbackType.HEADERS,
            100L,
            200L
        )
    }

    @Test
    fun testRegisterHeadlessSyncBodyBuilder_delegatesToService() {
        val context = mock(Context::class.java)
        val headlessService = mock(HeadlessTaskService::class.java)
        val hostApi = TraceletHostApiImpl(context, headlessService)

        hostApi.registerHeadlessSyncBodyBuilder(listOf(300L, 400L)) {}

        org.mockito.Mockito.verify(headlessService).registerCallbacks(
            HeadlessTaskService.CallbackType.SYNC_BODY,
            300L,
            400L
        )
    }

    @Test
    fun testTlConfigMapping_containsAllProperties() {
        val context = mock(Context::class.java)
        val headlessService = mock(HeadlessTaskService::class.java)
        val hostApi = TraceletHostApiImpl(context, headlessService)

        val method = TraceletHostApiImpl::class.java.getDeclaredMethod(
            "tlConfigToSdkMap",
            com.ikolvi.tracelet.TlConfig::class.java
        )
        method.isAccessible = true

        val mockConfig = mock(com.ikolvi.tracelet.TlConfig::class.java, org.mockito.Mockito.RETURNS_DEEP_STUBS)
        
        // Just mock the 'raw' values so we don't need actual enum instances.
        //
        // `!!` on every enum leaf and on the two nested sub-configs (#328): #321
        // made each of them nullable in the generated Pigeon classes, because
        // "not supplied" now has to be expressible on the wire for a partial
        // setConfig() to leave the persisted value alone. RETURNS_DEEP_STUBS
        // still hands back a stub for each one (Mockito 5 mocks final classes,
        // so an enum is fine), so the assertion is only telling Kotlin what the
        // deep stub already guarantees — it is not asserting anything about the
        // production nullability, which is the whole point of #321.
        org.mockito.Mockito.`when`(mockConfig.http.method!!.raw).thenReturn(0)
        org.mockito.Mockito.`when`(mockConfig.http.locationsOrderDirection!!.raw).thenReturn(0)
        org.mockito.Mockito.`when`(mockConfig.motion.motionDetectionMode!!.raw).thenReturn(0)
        org.mockito.Mockito.`when`(mockConfig.motion.stationaryTrackingMode!!.raw).thenReturn(0)
        org.mockito.Mockito.`when`(mockConfig.motion.stationaryPeriodicAccuracy!!.raw).thenReturn(0)
        org.mockito.Mockito.`when`(mockConfig.geo.desiredAccuracy!!.raw).thenReturn(0)
        org.mockito.Mockito.`when`(mockConfig.geo.periodicDesiredAccuracy!!.raw).thenReturn(0)
        org.mockito.Mockito.`when`(mockConfig.geo.filter!!.policy!!.raw).thenReturn(0)
        org.mockito.Mockito.`when`(mockConfig.android.foregroundService!!.notificationPriority!!.raw).thenReturn(0)
        org.mockito.Mockito.`when`(mockConfig.android.foregroundService!!.notificationStartedAt).thenReturn(4_294_967_296L)
        org.mockito.Mockito.`when`(mockConfig.android.foregroundService!!.notificationShowTimer).thenReturn(false)
        org.mockito.Mockito.`when`(mockConfig.android.foregroundService!!.notificationOnlyAlertOnce).thenReturn(true)
        org.mockito.Mockito.`when`(mockConfig.logger.logLevel!!.raw).thenReturn(0)
        org.mockito.Mockito.`when`(mockConfig.persistence.persistMode!!.raw).thenReturn(0)
        org.mockito.Mockito.`when`(mockConfig.audit.hashAlgorithm!!.raw).thenReturn(0)

        @Suppress("UNCHECKED_CAST")
        val map = method.invoke(hostApi, mockConfig) as Map<String, Any?>

        val httpMap = map["http"] as Map<String, Any?>
        val motionMap = map["motion"] as Map<String, Any?>
        val androidMap = map["android"] as Map<String, Any?>
        val foregroundServiceMap = androidMap["foregroundService"] as Map<String, Any?>

        assertEquals(4_294_967_296L, foregroundServiceMap["notificationStartedAt"])
        assertEquals(false, foregroundServiceMap["notificationShowTimer"])
        assertEquals(true, foregroundServiceMap["notificationOnlyAlertOnce"])

        val httpFields = com.ikolvi.tracelet.TlHttpConfig::class.java.declaredFields.map { it.name }.filter { it != "\$stable" && it != "Companion" }
        for (field in httpFields) {
            assertTrue(
                httpMap.containsKey(field),
                "Missing field in HTTP mapping: $field"
            )
        }

        val motionFields = com.ikolvi.tracelet.TlMotionConfig::class.java.declaredFields.map { it.name }.filter { it != "\$stable" && it != "Companion" }
        for (field in motionFields) {
            assertTrue(
                motionMap.containsKey(field),
                "Missing field in Motion mapping: $field"
            )
        }
    }

    @Test
    fun testSetNotification_forwardsEveryFieldToSdk() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val sdk = TraceletSdk.getInstance(context)
        sdk.configManager.reset(null)
        sdk.configManager.setConfig(
            mapOf(
                "android" to mapOf(
                    "foregroundService" to mapOf("notificationShowTimer" to true),
                ),
            ),
        )
        val hostApi = TraceletHostApiImpl(context, mock(HeadlessTaskService::class.java))
        var result: Result<Unit>? = null

        hostApi.setNotification(
            TlNotificationUpdate(
                title = "Tracking",
                text = "Uploading",
                startedAt = 4_294_967_296L,
                showTimer = false,
            ),
        ) { result = it }

        assertTrue(result!!.isSuccess)
        assertEquals("Tracking", sdk.configManager.getFgNotificationTitle())
        assertEquals("Uploading", sdk.configManager.getFgNotificationText())
        assertEquals(4_294_967_296L, sdk.configManager.getFgNotificationStartedAt())
        assertFalse(sdk.configManager.getFgNotificationShowTimer())
    }
}
