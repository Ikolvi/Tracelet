package com.ikolvi.tracelet.flutter

import android.content.Context
import com.ikolvi.tracelet.FlutterError
import com.ikolvi.tracelet.TlCurrentPositionOptions
import com.ikolvi.tracelet.TlLocation
import com.ikolvi.tracelet.TlState
import com.ikolvi.tracelet.flutter.service.HeadlessTaskService
import com.ikolvi.tracelet.sdk.TraceletSdk
import org.junit.Test
import org.mockito.Mockito.mock
import org.mockito.kotlin.whenever
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Verifies the plugin-layer readiness guards: when the SDK is not yet
 * initialized via ready(), each guarded method must fail the Pigeon callback
 * with FlutterError("NOT_READY", "Call ready() before <method>()"), matching iOS.
 */
class TraceletHostApiImplReadinessTest {

    private fun newHostApiNotReady(): TraceletHostApiImpl {
        val context = mock(Context::class.java)
        // TraceletSdk.getInstance() constructs with context.applicationContext;
        // make the mock return itself so the (lazy-subsystem) construction works.
        whenever(context.applicationContext).thenReturn(context)
        // getInstance returns a process-global singleton; force not-ready so the
        // guards fire deterministically regardless of any prior test state.
        // isReady has a private setter, so write its backing field via reflection.
        // The host API reads it via its own getInstance(context) → same singleton.
        val sdk = TraceletSdk.getInstance(context)
        TraceletSdk::class.java.getDeclaredField("isReady").apply {
            isAccessible = true
            setBoolean(sdk, false)
        }
        return TraceletHostApiImpl(context, mock(HeadlessTaskService::class.java))
    }

    private fun <T> capture(block: TraceletHostApiImpl.((Result<T>) -> Unit) -> Unit): Throwable? {
        val api = newHostApiNotReady()
        var result: Result<T>? = null
        block(api) { result = it }
        assertTrue(result!!.isFailure, "expected a failure Result")
        return result!!.exceptionOrNull()
    }

    private fun assertNotReady(err: Throwable?, expectedMessage: String) {
        assertTrue(err is FlutterError, "expected FlutterError, got ${err?.javaClass}")
        err as FlutterError
        assertEquals("NOT_READY", err.code)
        assertEquals(expectedMessage, err.message)
    }

    @Test
    fun start_notReady() =
        assertNotReady(capture<TlState> { start(it) }, "Call ready() before start()")

    @Test
    fun startGeofences_notReady() =
        assertNotReady(capture<TlState> { startGeofences(it) }, "Call ready() before startGeofences()")

    @Test
    fun startPeriodic_notReady() =
        assertNotReady(capture<TlState> { startPeriodic(it) }, "Call ready() before startPeriodic()")

    @Test
    fun reset_notReady() =
        assertNotReady(capture<TlState> { reset(null, it) }, "Call ready() before reset()")

    @Test
    fun startSchedule_notReady() =
        assertNotReady(capture<TlState> { startSchedule(it) }, "Call ready() before startSchedule()")

    @Test
    fun stopSchedule_notReady() =
        assertNotReady(capture<TlState> { stopSchedule(it) }, "Call ready() before stopSchedule()")

    @Test
    fun changePace_notReady() =
        assertNotReady(capture<Boolean> { changePace(true, it) }, "Call ready() before changePace()")

    @Test
    fun updateLocationProviderOptions_notReady() =
        assertNotReady(
            capture<Boolean> { updateLocationProviderOptions(null, null, it) },
            "Call ready() before updateLocationProviderOptions()",
        )

    @Test
    fun getCurrentPosition_notReady() =
        assertNotReady(
            capture<TlLocation> { getCurrentPosition(mock(TlCurrentPositionOptions::class.java), it) },
            "Call ready() before getCurrentPosition()",
        )
}
