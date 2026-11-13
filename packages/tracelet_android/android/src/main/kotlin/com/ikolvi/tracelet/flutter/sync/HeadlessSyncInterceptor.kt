package com.ikolvi.tracelet.flutter.sync

import com.ikolvi.tracelet.flutter.service.HeadlessTaskService
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.sync.DartSyncInterceptor
import android.content.Context

/**
 * A [DartSyncInterceptor] that routes sync-time Dart callbacks — custom sync
 * body and header/token refresh — to a background [HeadlessTaskService]
 * FlutterEngine.
 *
 * This is the *headless-only* interceptor used when there is no UI Flutter
 * engine in the process. The important case is a **cold reboot**: `BootReceiver`
 * starts tracking, but `TraceletAndroidPlugin.onAttachedToEngine` (which
 * normally installs the richer main-engine interceptor) never runs, so
 * `TraceletSdk.dartSyncInterceptor` would otherwise be null and HTTP sync would
 * fail (it can neither refresh the expired auth token nor build the custom
 * body, and falls back to a stale-token default POST).
 *
 * It is installed at process start by [com.ikolvi.tracelet.flutter.TraceletStartupProvider]
 * and only while `dartSyncInterceptor` is otherwise null, so an opened app still
 * overrides it with the main-engine path.
 *
 * The headless Dart callbacks (`registerHeadlessHeadersCallback` /
 * `registerHeadlessSyncBodyBuilder`) persist their callback handles in
 * SharedPreferences, so they are available even in a fresh boot process.
 */
class HeadlessSyncInterceptor(context: Context) : DartSyncInterceptor {

    private val appContext: Context = context.applicationContext

    // One shared service for the whole process so a header refresh and the
    // subsequent body build within a single sync reuse the same background
    // engine and its response latches line up.
    private val headless: HeadlessTaskService by lazy {
        HeadlessTaskService(appContext, ConfigManager.getInstance(appContext))
    }

    /**
     * Returns the custom JSON body, [com.ikolvi.tracelet.sdk.sync.NO_SYNC_BODY_BUILDER_SENTINEL]
     * when no headless builder is registered (the caller falls through to the
     * default payload), or `null` when a registered builder failed.
     */
    override fun requestSyncBody(locations: List<Map<String, Any?>>): String? =
        headless.requestCustomSyncBody(
            locations,
            TIMEOUT_MS,
            // #214: telematics for the killed-state custom builder (empty unless
            // syncTelematics is enabled).
            com.ikolvi.tracelet.sdk.TraceletSdk.getInstance(appContext)
                .getTelematicsForCustomBuilder(),
        )

    override fun requestFreshHeaders(): Boolean =
        headless.requestHeadersRefresh(TIMEOUT_MS, HeadlessTaskService.HEADERS_REASON_FRESH_HEADERS)

    /**
     * Same headless callback layer as a header refresh (post-401), with a
     * reason that tells the callback the current headers were rejected.
     */
    override fun requestTokenRefresh(): Boolean =
        headless.requestHeadersRefresh(TIMEOUT_MS, HeadlessTaskService.HEADERS_REASON_TOKEN_REFRESH)

    private companion object {
        const val TIMEOUT_MS = 10_000L
    }
}
