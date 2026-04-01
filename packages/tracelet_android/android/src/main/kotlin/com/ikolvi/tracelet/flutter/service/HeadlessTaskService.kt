package com.ikolvi.tracelet.flutter.service

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.HeadersRefreshable
import com.ikolvi.tracelet.sdk.HeadlessDispatcher
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.loader.FlutterLoader
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation
import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Headless Dart execution service for background events.
 *
 * When the app UI is killed but the service is running, this creates
 * a new FlutterEngine and dispatches HeadlessEvents to the registered
 * Dart callback.
 *
 * Flow:
 * 1. Dart calls registerHeadlessTask() → callback handles stored in SharedPreferences
 * 2. Background event occurs with no UI FlutterEngine
 * 3. HeadlessTaskService creates a new FlutterEngine
 * 4. Executes the Dart callback via DartExecutor
 * 5. Sends HeadlessEvent via MethodChannel
 * 6. Disposes engine when done
 */
class HeadlessTaskService(
    private val context: Context,
    private val configManager: ConfigManager? = null,
) : HeadlessDispatcher, HeadersRefreshable {

    companion object {
        private const val TAG = "HeadlessTaskService"
        private const val PREFS_NAME = "com.tracelet.headless"
        private const val KEY_REGISTRATION_CALLBACK = "registration_callback_id"
        private const val KEY_DISPATCH_CALLBACK = "dispatch_callback_id"
        private const val CHANNEL_NAME = "com.tracelet/headless"
        private const val METHODS_CHANNEL_NAME = "com.tracelet/methods"
    }

    private var flutterEngine: FlutterEngine? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val isEngineReady = AtomicBoolean(false)
    private val pendingEvents = LinkedBlockingQueue<Map<String, Any?>>()
    private var headlessMethodChannel: MethodChannel? = null

    /** Latch signaled when headless Dart callback calls setDynamicHeaders. */
    @Volatile
    private var headersRefreshLatch: CountDownLatch? = null

    /** Latch signaled when headless Dart callback returns custom sync body. */
    private val syncBodyLock = Object()
    private var syncBodyLatch: CountDownLatch? = null
    private var syncBodyResponse: String? = null

    /** Register the headless callback IDs (called from Dart side). */
    fun registerCallbacks(registrationCallbackId: Long, dispatchCallbackId: Long) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putLong(KEY_REGISTRATION_CALLBACK, registrationCallbackId)
            .putLong(KEY_DISPATCH_CALLBACK, dispatchCallbackId)
            .apply()
        Log.d(TAG, "Headless callbacks registered: reg=$registrationCallbackId, dispatch=$dispatchCallbackId")
    }

    /** Returns whether headless task is registered. */
    override fun isRegistered(): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.contains(KEY_REGISTRATION_CALLBACK) && prefs.contains(KEY_DISPATCH_CALLBACK)
    }

    /**
     * Dispatch a headless event. If no UI engine is available, creates
     * a new FlutterEngine to handle the event.
     *
     * Each event is wrapped to include the dispatch callback ID so the
     * Dart-side dispatcher ([_headlessCallbackDispatcher]) can look up
     * the user's callback via [PluginUtilities.getCallbackFromHandle].
     */
    override fun dispatchEvent(eventName: String, eventData: Map<String, Any?>) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val dispatchId = prefs.getLong(KEY_DISPATCH_CALLBACK, -1L)

        val event = mapOf(
            "name" to eventName,
            "event" to eventData,
            "dispatchId" to dispatchId,
        )

        if (isEngineReady.get() && headlessMethodChannel != null) {
            sendEvent(event)
            return
        }

        pendingEvents.add(event)
        ensureEngine()
    }

    /** Destroy the headless FlutterEngine. */
    fun destroy() {
        headlessMethodChannel = null
        isEngineReady.set(false)
        flutterEngine?.destroy()
        flutterEngine = null
        pendingEvents.clear()
    }

    /**
     * Request a headers refresh from the headless Dart callback.
     *
     * Dispatches a `headersRefresh` event to the Dart headless callback
     * registered via `registerHeadlessHeadersCallback`. The Dart callback
     * is expected to refresh the token and call `Tracelet.setDynamicHeaders()`,
     * which routes back to the native side and signals this method to return.
     *
     * @param timeoutMs Maximum time to wait for the Dart callback to respond.
     * @return `true` if headers were refreshed within the timeout.
     */
    override fun requestHeadersRefresh(timeoutMs: Long): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val dispatchId = prefs.getLong("headlessHeaders_dispatchId", -1L)
        val registrationId = prefs.getLong("headlessHeaders_registrationId", -1L)
        if (dispatchId == -1L || registrationId == -1L) {
            Log.w(TAG, "No headless headers callback registered")
            return false
        }

        // Guard: blocking the main thread would deadlock because the Dart
        // MethodChannel response also needs the main thread.
        if (Looper.myLooper() == Looper.getMainLooper()) {
            Log.e(TAG, "requestHeadersRefresh() must not be called on the main thread — would deadlock")
            return false
        }

        val latch = CountDownLatch(1)
        headersRefreshLatch = latch

        // Dispatch the headersRefresh event using the headers-specific dispatch ID
        val event = mapOf(
            "name" to "headersRefresh",
            "event" to emptyMap<String, Any?>(),
            "dispatchId" to dispatchId,
        )

        if (isEngineReady.get() && headlessMethodChannel != null) {
            sendEvent(event)
        } else {
            pendingEvents.add(event)
            ensureEngine()
        }

        return try {
            val result = latch.await(timeoutMs, TimeUnit.MILLISECONDS)
            if (result) {
                Log.d(TAG, "Headers refresh completed by headless callback")
            } else {
                Log.w(TAG, "Headers refresh timed out after ${timeoutMs}ms")
            }
            result
        } finally {
            headersRefreshLatch = null
        }
    }

    /**
     * Request a custom sync body from the headless Dart callback.
     *
     * Dispatches a `syncBodyBuild` event to the Dart headless callback
     * registered via `registerHeadlessSyncBodyBuilder`. The Dart callback
     * is expected to transform the locations and call
     * `Tracelet.setSyncBodyResponse()`, which routes back to the native
     * side and signals this method to return.
     *
     * @param locations The batch of locations to include in the body.
     * @param timeoutMs Maximum time to wait for the Dart callback to respond.
     * @return The custom JSON body string, or `null` if timed out or unavailable.
     */
    fun requestCustomSyncBody(
        locations: List<Map<String, Any?>>,
        timeoutMs: Long,
    ): String? {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val dispatchId = prefs.getLong("headlessSyncBody_dispatchId", -1L)
        val registrationId = prefs.getLong("headlessSyncBody_registrationId", -1L)
        if (dispatchId == -1L || registrationId == -1L) {
            Log.w(TAG, "No headless sync body callback registered")
            return null
        }

        if (Looper.myLooper() == Looper.getMainLooper()) {
            Log.e(TAG, "requestCustomSyncBody() must not be called on the main thread — would deadlock")
            return null
        }

        val latch = CountDownLatch(1)
        synchronized(syncBodyLock) {
            syncBodyLatch = latch
            syncBodyResponse = null
        }

        val event = mapOf(
            "name" to "syncBodyBuild",
            "event" to mapOf("locations" to locations),
            "dispatchId" to dispatchId,
        )

        if (isEngineReady.get() && headlessMethodChannel != null) {
            sendEvent(event)
        } else {
            pendingEvents.add(event)
            ensureEngine()
        }

        return try {
            val completed = latch.await(timeoutMs, TimeUnit.MILLISECONDS)
            if (completed) {
                Log.d(TAG, "Sync body build completed by headless callback")
                synchronized(syncBodyLock) { syncBodyResponse }
            } else {
                Log.w(TAG, "Sync body build timed out after ${timeoutMs}ms")
                null
            }
        } finally {
            synchronized(syncBodyLock) {
                syncBodyLatch = null
                syncBodyResponse = null
            }
        }
    }

    // =========================================================================
    // Private
    // =========================================================================

    private fun ensureEngine() {
        if (flutterEngine != null) return

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        // Try main headless callback first, fall back to headlessHeaders callback
        var registrationCallbackId = prefs.getLong(KEY_REGISTRATION_CALLBACK, -1)
        val dispatchCallbackId = prefs.getLong(KEY_DISPATCH_CALLBACK, -1)

        if (registrationCallbackId == -1L) {
            registrationCallbackId = prefs.getLong("headlessHeaders_registrationId", -1)
        }

        if (registrationCallbackId == -1L) {
            Log.w(TAG, "No headless callbacks registered")
            pendingEvents.clear()
            return
        }

        mainHandler.post {
            try {
                val loader = FlutterLoader()
                loader.startInitialization(context)
                loader.ensureInitializationComplete(context, null)

                flutterEngine = FlutterEngine(context).also { engine ->
                    headlessMethodChannel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME)

                    // Set up method channel to receive "ready" signal from Dart
                    headlessMethodChannel?.setMethodCallHandler { call, result ->
                        when (call.method) {
                            "initialized" -> {
                                isEngineReady.set(true)
                                drainPendingEvents()
                                result.success(true)
                            }
                            else -> result.notImplemented()
                        }
                    }

                    // Handle setDynamicHeaders from headless Dart callback.
                    // When the Dart headless callback calls Tracelet.setDynamicHeaders(),
                    // it goes through com.tracelet/methods. We handle it here so the
                    // headless engine can update headers and signal the refresh latch.
                    val methodsChannel = MethodChannel(engine.dartExecutor.binaryMessenger, METHODS_CHANNEL_NAME)
                    methodsChannel.setMethodCallHandler { call, result ->
                        when (call.method) {
                            "setDynamicHeaders" -> {
                                @Suppress("UNCHECKED_CAST")
                                val headers = (call.arguments as? Map<String, Any?>)
                                    ?.mapValues { it.value?.toString() ?: "" }
                                    ?: emptyMap()
                                configManager?.setDynamicHeaders(headers)
                                headersRefreshLatch?.countDown()
                                result.success(true)
                            }
                            "setSyncBodyResponse" -> {
                                synchronized(syncBodyLock) {
                                    syncBodyResponse = call.arguments as? String
                                }
                                syncBodyLatch?.countDown()
                                result.success(true)
                            }
                            else -> result.notImplemented()
                        }
                    }

                    // Execute the registration callback in Dart
                    val callbackInfo = FlutterCallbackInformation.lookupCallbackInformation(registrationCallbackId)
                    if (callbackInfo != null) {
                        engine.dartExecutor.executeDartCallback(
                            DartExecutor.DartCallback(context.assets, loader.findAppBundlePath(), callbackInfo)
                        )
                    } else {
                        Log.e(TAG, "Could not find callback info for ID: $registrationCallbackId")
                        destroy()
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to create headless FlutterEngine: ${e.message}")
                destroy()
            }
        }
    }

    private fun drainPendingEvents() {
        while (pendingEvents.isNotEmpty()) {
            val event = pendingEvents.poll() ?: break
            sendEvent(event)
        }
    }

    private fun sendEvent(event: Map<String, Any?>) {
        mainHandler.post {
            headlessMethodChannel?.invokeMethod("headlessEvent", event)
        }
    }
}
