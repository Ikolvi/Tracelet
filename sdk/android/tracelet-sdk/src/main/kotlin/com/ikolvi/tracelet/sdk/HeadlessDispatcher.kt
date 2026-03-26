package com.ikolvi.tracelet.sdk

/**
 * Abstraction for dispatching events to a headless runtime (background Dart
 * isolate, React Native HeadlessJsTaskService, etc.).
 *
 * The host framework provides a concrete implementation via
 * [TraceletBootstrap.headlessDispatcherFactory].
 */
interface HeadlessDispatcher {
    /** Returns true if a headless callback has been registered. */
    fun isRegistered(): Boolean

    /** Dispatches an event to the headless runtime. */
    fun dispatchEvent(eventName: String, data: Map<String, Any?>)
}
