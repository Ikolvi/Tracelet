package com.ikolvi.tracelet.flutter

import com.ikolvi.tracelet.sdk.TraceletSdk

/**
 * Applies [headers] where native sync reads them and returns whether they were
 * applied.
 *
 * `TraceletSdk.setDynamicHeaders()` returns early until `ready()` has run. A
 * process the service started in the background (sticky restart, boot, task
 * removal) runs `bootstrapForBackground()` and never `ready()`, so the
 * headless headers callback's refreshed token was dropped there while the
 * host still replied `true`, and every upload in that process went out
 * without it.
 *
 * The SDK's guard protects its `lateinit` subsystems; headers touch neither.
 * They need the two stores sync reads: ConfigManager, whose merged headers are
 * copied into the Rust config on every resync, and the live Rust engine state
 * that `NativeSyncProvider` uploads and retries with. Both exist as soon as
 * the Rust core is up, which a background bootstrap waits for. Before that
 * nothing is listening, so nothing is applied and the caller is told so.
 */
internal fun applyDynamicHeaders(sdk: TraceletSdk, headers: Map<String, String>): Boolean {
    if (sdk.isReady) {
        sdk.setDynamicHeaders(headers)
        return true
    }
    val state = sdk.rustEngineState ?: return false
    sdk.configManager.setDynamicHeaders(headers)
    state.setDynamicHeaders(HashMap(headers))
    return true
}
