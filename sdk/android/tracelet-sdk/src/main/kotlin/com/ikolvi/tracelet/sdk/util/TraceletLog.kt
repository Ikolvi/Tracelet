package com.ikolvi.tracelet.sdk.util

import android.util.Log

/**
 * Process-wide entry point for Tracelet logging.
 *
 * Routes every log line through the configured [TraceletLogger] (which respects
 * the configured log level and persists to the Rust SQLite log store) once the
 * SDK has [attach]ed one. Before the SDK is initialized — e.g. inside a
 * [android.content.BroadcastReceiver] or [androidx.work.Worker] that fires on a
 * cold process — it falls back to raw logcat so nothing is silently dropped.
 *
 * Use this instead of [android.util.Log] everywhere in the SDK. The only place
 * that legitimately calls [android.util.Log] directly is [TraceletLogger] itself
 * (the sink) and this fallback.
 */
object TraceletLog {
    private const val TAG = "Tracelet"

    @Volatile
    private var delegate: TraceletLogger? = null

    /** Wire the real logger once the SDK is initialized. */
    fun attach(logger: TraceletLogger) {
        delegate = logger
    }

    /** Drop the logger reference (e.g. on reset/teardown). */
    fun detach() {
        delegate = null
    }

    fun error(message: String, throwable: Throwable? = null, tag: String = TAG) {
        val d = delegate
        if (d != null) {
            d.error(fmt(message, throwable), tag)
        } else if (throwable != null) {
            Log.e(tag, message, throwable)
        } else {
            Log.e(tag, message)
        }
    }

    fun warning(message: String, throwable: Throwable? = null, tag: String = TAG) {
        val d = delegate
        if (d != null) {
            d.warning(fmt(message, throwable), tag)
        } else if (throwable != null) {
            Log.w(tag, message, throwable)
        } else {
            Log.w(tag, message)
        }
    }

    fun info(message: String, throwable: Throwable? = null, tag: String = TAG) {
        val d = delegate
        if (d != null) {
            d.info(fmt(message, throwable), tag)
        } else if (throwable != null) {
            Log.i(tag, message, throwable)
        } else {
            Log.i(tag, message)
        }
    }

    fun debug(message: String, throwable: Throwable? = null, tag: String = TAG) {
        val d = delegate
        if (d != null) {
            d.debug(fmt(message, throwable), tag)
        } else if (throwable != null) {
            Log.d(tag, message, throwable)
        } else {
            Log.d(tag, message)
        }
    }

    fun verbose(message: String, throwable: Throwable? = null, tag: String = TAG) {
        val d = delegate
        if (d != null) {
            d.verbose(fmt(message, throwable), tag)
        } else if (throwable != null) {
            Log.v(tag, message, throwable)
        } else {
            Log.v(tag, message)
        }
    }

    /**
     * Records an always-on **lifecycle** event — see [TraceletLogger.lifecycle]
     * for what belongs here and why it bypasses `logLevel` (#318).
     *
     * Before the SDK has [attach]ed a logger this falls back to logcat, exactly
     * like the level-based methods. That gap is why [TraceletLogger.lifecycle]
     * buffers: entries recorded through the real logger while its database is
     * still opening are flushed once it is available, so a bootstrap that never
     * finished still leaves a trail.
     */
    fun lifecycle(message: String, tag: String = TAG) {
        val d = delegate
        if (d != null) {
            d.lifecycle(message, tag)
        } else {
            Log.i(tag, message)
        }
    }

    private fun fmt(message: String, throwable: Throwable?): String =
        if (throwable != null) "$message: ${throwable.message}" else message
}
