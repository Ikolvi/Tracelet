package com.tracelet.reactnative

import android.content.Intent
import android.os.Bundle
import com.facebook.react.HeadlessJsTaskService
import com.facebook.react.bridge.Arguments
import com.facebook.react.jstasks.HeadlessJsTaskConfig
import com.tracelet.core.HeadlessDispatcher

/**
 * Android headless JS task service for background event processing.
 *
 * When the app is terminated, native TraceletCore engines continue running
 * (via foreground service or WorkManager). This service bridges those
 * background events to JavaScript by starting React Native's JS engine
 * in a headless (no UI) context.
 *
 * Usage in JS:
 * ```
 * import { AppRegistry } from 'react-native';
 *
 * AppRegistry.registerHeadlessTask(
 *   'TraceletHeadlessTask',
 *   () => async (event) => {
 *     console.log('Headless event:', event);
 *   }
 * );
 * ```
 */
class TraceletHeadlessService : HeadlessJsTaskService() {

    override fun getTaskConfig(intent: Intent): HeadlessJsTaskConfig? {
        val extras = intent.extras ?: return null
        return HeadlessJsTaskConfig(
            TASK_NAME,
            Arguments.fromBundle(extras),
            TASK_TIMEOUT_MS,
            true // allowedInForeground
        )
    }

    companion object {
        const val TASK_NAME = "TraceletHeadlessTask"
        const val TASK_TIMEOUT_MS = 30000L

        /**
         * Dispatch a background event to the headless JS task.
         */
        fun dispatch(
            context: android.content.Context,
            eventName: String,
            eventData: Map<String, Any?>
        ) {
            val intent = Intent(context, TraceletHeadlessService::class.java)
            val bundle = Bundle().apply {
                putString("name", eventName)
                putBundle("event", eventData.toBundle())
            }
            intent.putExtras(bundle)
            context.startService(intent)
        }

        private fun Map<String, Any?>.toBundle(): Bundle {
            val bundle = Bundle()
            for ((key, value) in this) {
                when (value) {
                    null -> bundle.putString(key, null)
                    is Boolean -> bundle.putBoolean(key, value)
                    is Int -> bundle.putInt(key, value)
                    is Long -> bundle.putLong(key, value)
                    is Double -> bundle.putDouble(key, value)
                    is String -> bundle.putString(key, value)
                    is Map<*, *> -> {
                        @Suppress("UNCHECKED_CAST")
                        bundle.putBundle(key, (value as Map<String, Any?>).toBundle())
                    }
                    else -> bundle.putString(key, value.toString())
                }
            }
            return bundle
        }
    }
}

/**
 * HeadlessDispatcher implementation for React Native.
 *
 * Bridges TraceletCore's [HeadlessDispatcher] to RN's [HeadlessJsTaskService].
 * Registered via [TraceletBootstrap.headlessDispatcherFactory] during module init.
 */
class ReactNativeHeadlessDispatcher(
    private val context: android.content.Context
) : HeadlessDispatcher {

    override fun isRegistered(): Boolean = true

    override fun dispatchEvent(eventName: String, data: Map<String, Any?>) {
        TraceletHeadlessService.dispatch(context, eventName, data)
    }
}
