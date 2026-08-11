package com.ikolvi.tracelet.flutter
import com.ikolvi.tracelet.sdk.util.TraceletLog

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.util.Log
import com.ikolvi.tracelet.flutter.service.HeadlessTaskService
import com.ikolvi.tracelet.flutter.sync.HeadlessSyncInterceptor
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.TraceletBootstrap
import com.ikolvi.tracelet.sdk.TraceletSdk

/**
 * Zero-work [ContentProvider] used purely as a process-start hook.
 *
 * Android instantiates every declared ContentProvider and calls [onCreate] on
 * EVERY process creation — including a process spawned by `BootReceiver` after a
 * reboot — and before any `BroadcastReceiver.onReceive()`. We use that to wire
 * the headless Dart bridge so background HTTP sync (auth-token refresh + custom
 * sync body) works even when no UI Flutter engine is present.
 *
 * Without this, on a cold boot `TraceletAndroidPlugin.onAttachedToEngine` never
 * runs, so [TraceletSdk.dartSyncInterceptor] and
 * [TraceletBootstrap.headlessDispatcherFactory] stay null and sync silently
 * fails (stale token / wrong payload) until the user opens the app.
 *
 * Both seams are installed only when currently null, so an opened app still
 * overrides them with the richer main-engine path in onAttachedToEngine.
 */
class TraceletStartupProvider : ContentProvider() {

    override fun onCreate(): Boolean {
        val ctx = context?.applicationContext ?: return false
        try {
            if (TraceletBootstrap.headlessDispatcherFactory == null) {
                TraceletBootstrap.headlessDispatcherFactory = { c ->
                    HeadlessTaskService(c, ConfigManager.getInstance(c))
                }
            }
            // Wire the headless EVENT bridge too. Without this, a cold boot
            // (BootReceiver → LocationService, no Flutter engine) leaves
            // eventSenderFactory null, so LocationService.startBootTracking falls
            // back to a no-op ListenerEventSender and background location / motion
            // / geofence events (incl. geofenceModeHighAccuracy enter/exit) are
            // silently dropped instead of reaching the registered headless task.
            // Mirrors TraceletAndroidPlugin.onAttachedToEngine; overridden by the
            // richer main-engine path when the app is later opened.
            if (TraceletBootstrap.eventSenderFactory == null) {
                TraceletBootstrap.eventSenderFactory = { c ->
                    val dispatcher = EventDispatcher()
                    val h = HeadlessTaskService(c, ConfigManager.getInstance(c))
                    dispatcher.headlessFallback = { name, data ->
                        dispatchToHeadless(h, name, data)
                    }
                    dispatcher
                }
            }
            val sdk = TraceletSdk.getInstance(ctx)
            if (sdk.dartSyncInterceptor == null) {
                sdk.dartSyncInterceptor = HeadlessSyncInterceptor(ctx)
            }
        } catch (t: Throwable) {
            // Never break host-app startup over background-sync wiring.
            TraceletLog.warning("Headless sync bridge wiring failed at process start: ${t.message}")
        }
        return true
    }

    // Not a real content provider — no data is exposed.
    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor? = null

    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0

    private companion object {
        const val TAG = "TraceletStartup"
    }
}
