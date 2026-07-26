package com.ikolvi.tracelet.sdk

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/**
 * Fetches configuration overrides from a remote HTTPS endpoint and applies them
 * on top of the local config, refreshing periodically in the background
 * (Enterprise `remoteConfigUrl`).
 *
 * The endpoint returns a JSON config map — either flat or in the nested
 * `{app:{}, geo:{}, http:{}, ...}` shape that [ConfigManager.setConfig] already
 * accepts. The last successful response is cached to SharedPreferences so a
 * restart resumes on the freshest known config instantly and offline, before
 * the network round-trip completes.
 *
 * Only HTTPS URLs are honored. All network work runs on a dedicated background
 * thread; failures are logged and never thrown to the caller — the SDK keeps
 * running on local/cached config.
 */
class RemoteConfigManager(
    context: Context,
    private val configManager: ConfigManager,
    private val log: (String) -> Unit = {},
) {

    companion object {
        private const val PREFS_NAME = "com.tracelet.remote_config"
        private const val KEY_CACHED = "cached_json"

        /** Floor for the periodic refresh cadence (15 min), matching platform norms. */
        private const val MIN_REFRESH_SECONDS = 900L
    }

    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val scheduler = Executors.newSingleThreadScheduledExecutor { r ->
        Thread(r, "tracelet-remote-config").apply { isDaemon = true }
    }

    @Volatile
    private var refreshFuture: ScheduledFuture<*>? = null

    /** Last successfully fetched remote config, or `null` if never fetched. */
    fun cachedConfig(): Map<String, Any?>? {
        val json = prefs.getString(KEY_CACHED, null) ?: return null
        return try {
            jsonToMap(JSONObject(json))
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Kicks off an immediate background fetch and schedules periodic refreshes
     * at `remoteConfigRefreshInterval` (minutes). [onConfig] is invoked on the
     * background thread with each freshly fetched config map so the caller can
     * apply it (e.g. via `TraceletSdk.setConfig`).
     *
     * A refresh interval of `0` (or negative) fetches once and never repeats.
     */
    fun start(url: String, onConfig: (Map<String, Any?>) -> Unit) {
        stop()
        scheduler.execute { fetchOnce(url, onConfig) }

        val minutes = configManager.getRemoteConfigRefreshInterval()
        if (minutes <= 0) return
        val seconds = (minutes.toLong() * 60L).coerceAtLeast(MIN_REFRESH_SECONDS)
        refreshFuture = scheduler.scheduleAtFixedRate(
            { fetchOnce(url, onConfig) },
            seconds,
            seconds,
            TimeUnit.SECONDS,
        )
    }

    /** Stops periodic refreshes. Safe to call when not running. */
    fun stop() {
        refreshFuture?.cancel(false)
        refreshFuture = null
    }

    private fun fetchOnce(url: String, onConfig: (Map<String, Any?>) -> Unit) {
        val remote = fetch(url) ?: return
        cache(remote)
        log("remote config: fetched ${remote.size} key(s) from $url")
        try {
            onConfig(remote)
        } catch (e: Exception) {
            log("remote config: apply failed (${e.message})")
        }
    }

    private fun fetch(url: String): Map<String, Any?>? {
        // Reject non-HTTPS URLs — config controls tracking behavior and must not
        // be delivered over a channel an attacker can tamper with.
        if (!url.startsWith("https://")) {
            log("remote config: URL rejected — only HTTPS is allowed")
            return null
        }
        val timeout = configManager.getRemoteConfigTimeout().coerceAtLeast(1000)
        val headers = configManager.getRemoteConfigHeaders()
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = timeout
            readTimeout = timeout
            requestMethod = "GET"
            setRequestProperty("accept", "application/json")
            headers.forEach { (k, v) -> setRequestProperty(k, v) }
        }
        return try {
            val code = conn.responseCode
            if (code != 200) {
                log("remote config: HTTP $code from $url")
                return null
            }
            val body = conn.inputStream.use { String(it.readBytes(), Charsets.UTF_8) }
            jsonToMap(JSONObject(body))
        } catch (e: Exception) {
            log("remote config: fetch failed (${e.message})")
            null
        } finally {
            conn.disconnect()
        }
    }

    private fun cache(config: Map<String, Any?>) {
        try {
            prefs.edit().putString(KEY_CACHED, JSONObject(config).toString()).apply()
        } catch (e: Exception) {
            log("remote config: cache write failed (${e.message})")
        }
    }

    private fun jsonToMap(json: JSONObject): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>()
        for (key in json.keys()) {
            map[key] = when (val value = json.get(key)) {
                JSONObject.NULL -> null
                is JSONObject -> jsonToMap(value)
                is JSONArray -> jsonArrayToList(value)
                else -> value
            }
        }
        return map
    }

    private fun jsonArrayToList(array: JSONArray): List<Any?> {
        val list = mutableListOf<Any?>()
        for (i in 0 until array.length()) {
            list.add(
                when (val value = array.get(i)) {
                    JSONObject.NULL -> null
                    is JSONObject -> jsonToMap(value)
                    is JSONArray -> jsonArrayToList(value)
                    else -> value
                }
            )
        }
        return list
    }
}
