package com.ikolvi.tracelet.sdk

import android.content.Context

/**
 * Static factory registry for creating framework-specific implementations
 * during background restarts (boot, task-removal, WorkManager).
 *
 * The host framework (Flutter plugin, React Native module) sets these
 * factories during initialization. Core engine code uses them when it
 * needs to bootstrap tracking without a live UI connection.
 */
object TraceletBootstrap {
    /**
     * Factory for creating a [TraceletEventSender] during headless/boot restart.
     * Set by the host framework adapter during plugin initialization.
     */
    @Volatile
    var eventSenderFactory: ((Context) -> TraceletEventSender)? = null

    /**
     * Factory for creating a [HeadlessDispatcher] during background execution.
     * Set by the host framework adapter during plugin initialization.
     */
    @Volatile
    var headlessDispatcherFactory: ((Context) -> HeadlessDispatcher)? = null
}
