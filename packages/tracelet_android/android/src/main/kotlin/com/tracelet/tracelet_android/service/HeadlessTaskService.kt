package com.tracelet.tracelet_android.service

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.loader.FlutterLoader
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation
import java.util.concurrent.LinkedBlockingQueue
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
class HeadlessTaskService(private val context: Context) {

    companion object {
        private const val TAG = "HeadlessTaskService"
        private const val PREFS_NAME = "com.tracelet.headless"
        private const val KEY_REGISTRATION_CALLBACK = "registration_callback_id"
        private const val KEY_DISPATCH_CALLBACK = "dispatch_callback_id"
        private const val CHANNEL_NAME = "com.tracelet/headless"
    }

    private var flutterEngine: FlutterEngine? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val isEngineReady = AtomicBoolean(false)
    private val pendingEvents = LinkedBlockingQueue<Map<String, Any?>>()
    private var headlessMethodChannel: MethodChannel? = null

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
    fun isRegistered(): Boolean {
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
    fun dispatchEvent(eventName: String, eventData: Map<String, Any?>) {
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

    // =========================================================================
    // Private
    // =========================================================================

    private fun ensureEngine() {
        if (flutterEngine != null) return

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val registrationCallbackId = prefs.getLong(KEY_REGISTRATION_CALLBACK, -1)
        val dispatchCallbackId = prefs.getLong(KEY_DISPATCH_CALLBACK, -1)

        if (registrationCallbackId == -1L || dispatchCallbackId == -1L) {
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
