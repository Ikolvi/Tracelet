package com.ikolvi.tracelet.sdk

/**
 * Optional interface that a [HeadlessDispatcher] can implement to support
 * synchronous token/headers refresh during HTTP sync (401 handling).
 */
interface HeadersRefreshable {
    /**
     * Requests a headers refresh from the headless runtime.
     * Blocks the calling thread for up to [timeoutMs] milliseconds.
     *
     * @return true if headers were refreshed successfully, false on timeout or failure
     */
    fun requestHeadersRefresh(timeoutMs: Long): Boolean
}
