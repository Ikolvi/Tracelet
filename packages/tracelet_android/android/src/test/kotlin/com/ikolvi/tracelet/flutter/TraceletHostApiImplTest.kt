package com.ikolvi.tracelet.flutter

import android.content.Context
import com.ikolvi.tracelet.TlAuthorizationStatus
import com.ikolvi.tracelet.flutter.service.HeadlessTaskService
import com.ikolvi.tracelet.sdk.TraceletSdk
import org.junit.Test
import org.mockito.Mockito.mock
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class TraceletHostApiImplTest {

    /**
     * #364: `requestStateFlush` doubles as the per-engine "my Dart side is
     * listening" handshake.
     *
     * The HostApi is registered per messenger, so a call arriving here came
     * from that engine's isolate — and `PigeonTracelet._ensureEventsRegistered()`
     * sends exactly one, immediately after `TraceletEventApi.setUp(...)`, on the
     * first access to any event stream. That is the whole basis for letting a
     * secondary engine into the event fan-out, so a refactor that drops the
     * callback (or moves the flush off this method) must fail here rather than
     * silently strand every overlay engine outside the fan-out.
     */
    @Test
    fun testRequestStateFlush_signalsTheDartEventSubscription() {
        val context = mock(Context::class.java)
        val headlessService = mock(HeadlessTaskService::class.java)
        var subscribed = 0

        val instanceField = TraceletSdk::class.java.getDeclaredField("instance")
        instanceField.isAccessible = true
        instanceField.set(null, mock(TraceletSdk::class.java))
        try {
            val hostApi = TraceletHostApiImpl(context, headlessService) { subscribed++ }
            hostApi.requestStateFlush()
        } finally {
            instanceField.set(null, null)
        }

        assertEquals(1, subscribed, "requestStateFlush must signal the subscription")
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
        org.mockito.Mockito.`when`(mockConfig.logger.logLevel!!.raw).thenReturn(0)
        org.mockito.Mockito.`when`(mockConfig.persistence.persistMode!!.raw).thenReturn(0)
        org.mockito.Mockito.`when`(mockConfig.audit.hashAlgorithm!!.raw).thenReturn(0)

        @Suppress("UNCHECKED_CAST")
        val map = method.invoke(hostApi, mockConfig) as Map<String, Any?>

        val httpMap = map["http"] as Map<String, Any?>
        val motionMap = map["motion"] as Map<String, Any?>

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
}
