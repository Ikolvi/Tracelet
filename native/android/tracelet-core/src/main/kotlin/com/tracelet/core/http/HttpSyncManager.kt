package com.tracelet.core.http

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.tracelet.core.ConfigManager
import com.tracelet.core.TraceletEventSender
import com.tracelet.core.db.TraceletDatabase
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.min
import kotlin.math.pow
import kotlin.random.Random

/**
 * HTTP synchronization engine using OkHttp.
 *
 * Features:
 * - Manual sync via sync()
 * - Auto-sync after each location insert (if enabled)
 * - Batch sync support
 * - Retry with exponential backoff + jitter
 * - Connectivity monitoring (deferred sync on reconnect)
 * - Fires onHttp events for each request
 */
class HttpSyncManager(
    private val context: Context,
    private val config: ConfigManager,
    private val events: TraceletEventSender,
    private val db: TraceletDatabase,
) {
    companion object {
        private const val TAG = "HttpSyncManager"
        private val JSON_MEDIA = "application/json; charset=utf-8".toMediaType()
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    /** In-memory counter of inserts since last sync — avoids SELECT COUNT(*) per insert (A-M7). */
    @Volatile
    private var insertsSinceLastSync = 0

    private var httpClient: OkHttpClient? = null
    @Volatile private var isSyncing = false
    @Volatile private var isConnected = true
    private var connectivityCallback: ConnectivityManager.NetworkCallback? = null
    @Volatile private var pendingSyncOnConnect = false

    /** Initialize the HTTP client. */
    fun start() {
        val timeout = config.getHttpTimeout().toLong()
        httpClient = OkHttpClient.Builder()
            .connectTimeout(timeout, TimeUnit.MILLISECONDS)
            .readTimeout(timeout, TimeUnit.MILLISECONDS)
            .writeTimeout(timeout, TimeUnit.MILLISECONDS)
            .build()
        registerConnectivityCallback()
    }

    /** Stop and clean up. */
    fun stop() {
        unregisterConnectivityCallback()
        httpClient?.dispatcher?.cancelAll()
        httpClient = null
    }

    /** Trigger auto-sync if conditions are met. Called after each location insert. */
    fun onLocationInserted() {
        if (!config.getAutoSync()) return
        val url = config.getHttpUrl() ?: return

        // Skip auto-sync on cellular if configured
        if (config.getDisableAutoSyncOnCellular() && isCellular()) return

        val threshold = config.getAutoSyncThreshold()
        if (threshold > 0) {
            // Use in-memory counter instead of SELECT COUNT(*) on every insert (A-M7).
            insertsSinceLastSync++
            if (insertsSinceLastSync < threshold) return
        }

        insertsSinceLastSync = 0
        syncAsync()
    }

    /**
     * Manual sync. Returns synced locations.
     * [callback] receives the list of synced location maps.
     */
    fun sync(callback: (List<Map<String, Any?>>) -> Unit) {
        executor.execute {
            val result = performSync()
            mainHandler.post { callback(result) }
        }
    }

    /** Async sync (no callback). */
    fun syncAsync() {
        executor.execute { performSync() }
    }

    // =========================================================================
    // Sync Logic
    // =========================================================================

    private fun performSync(): List<Map<String, Any?>> {
        if (isSyncing) return emptyList()
        val url = config.getHttpUrl() ?: return emptyList()
        val client = httpClient ?: return emptyList()

        isSyncing = true
        val allSynced = mutableListOf<Map<String, Any?>>()

        try {
            while (true) {
                val batchSize = if (config.getBatchSync()) config.getMaxBatchSize() else 1
                val orderAsc = config.getLocationsOrderDirection() == 0
                val locations = db.getUnsyncedLocations(batchSize, orderAsc)
                if (locations.isEmpty()) break

                if (!isConnected) {
                    pendingSyncOnConnect = true
                    break
                }

                val success = sendBatch(client, url, locations)
                if (success) {
                    val uuids = locations.mapNotNull { it["uuid"] as? String }
                    db.markSynced(uuids)
                    allSynced.addAll(locations)
                } else {
                    break // Stop syncing on failure
                }
            }
        } finally {
            isSyncing = false
        }

        return allSynced
    }

    private fun sendBatch(client: OkHttpClient, url: String, locations: List<Map<String, Any?>>): Boolean {
        val rootProp = config.getHttpRootProperty()
        val extras = config.getHttpExtras()
        val params = config.getHttpParams()
        val headers = config.getHttpHeaders()
        val method = if (config.getHttpMethod() == 0) "POST" else "PUT"

        // Retry parameters from config
        val maxRetries = config.getMaxRetries()
        val baseRetryMs = config.getRetryBackoffBase().toLong()
        val maxRetryMs = config.getRetryBackoffCap().toLong()

        // Build JSON body
        val useDelta = config.getEnableDeltaCompression() && config.getBatchSync() && locations.size > 1
        val body: String
        if (config.getBatchSync() && locations.size > 1) {
            val payload = if (useDelta) {
                DeltaEncoder.encode(locations, config.getDeltaCoordinatePrecision())
            } else {
                locations
            }
            val jsonArray = JSONArray()
            for (loc in payload) {
                jsonArray.put(JSONObject(loc))
            }
            val wrapper = JSONObject()
            wrapper.put(rootProp, jsonArray)
            for ((k, v) in params) wrapper.put(k, v)
            body = wrapper.toString()
        } else {
            // Single location per request
            val loc = locations.first()
            val wrapper = JSONObject()
            wrapper.put(rootProp, JSONObject(loc))
            for ((k, v) in params) wrapper.put(k, v)
            body = wrapper.toString()
        }

        var retryCount = 0
        while (retryCount <= maxRetries) {
            try {
                val requestBody = body.toRequestBody(JSON_MEDIA)
                val requestBuilder = Request.Builder().url(url)

                // Add headers
                for ((key, value) in headers) {
                    requestBuilder.addHeader(key, value)
                }

                when (method) {
                    "POST" -> requestBuilder.post(requestBody)
                    "PUT" -> requestBuilder.put(requestBody)
                }

                val response = client.newCall(requestBuilder.build()).execute()
                val responseBody = response.body?.string() ?: ""
                val statusCode = response.code

                val httpEvent = mapOf(
                    "success" to response.isSuccessful,
                    "status" to statusCode,
                    "responseText" to responseBody,
                    "isRetry" to (retryCount > 0),
                    "retryCount" to retryCount,
                )
                events.sendHttp(httpEvent)

                response.close()

                if (response.isSuccessful) {
                    return true
                }

                // Transient errors: 429 (rate-limit), 408 (timeout), 5xx
                if (isTransientError(statusCode)) {
                    Log.w(TAG, "HTTP sync transient failure: $statusCode, retry ${retryCount + 1}")
                } else {
                    // Permanent failure (other 4xx) — don't retry
                    Log.w(TAG, "HTTP sync permanent failure: $statusCode")
                    return false
                }

            } catch (e: IOException) {
                Log.w(TAG, "HTTP sync IO error: ${e.message}, retry ${retryCount + 1}")
                val httpEvent = mapOf(
                    "success" to false,
                    "status" to 0,
                    "responseText" to (e.message ?: "IO Error"),
                    "isRetry" to (retryCount > 0),
                    "retryCount" to retryCount,
                )
                events.sendHttp(httpEvent)
            }

            retryCount++
            if (retryCount <= maxRetries) {
                val backoff = min(
                    maxRetryMs,
                    baseRetryMs * 2.0.pow(retryCount - 1).toLong()
                )
                val jitter = (backoff * 0.25 * (Random.nextDouble() * 2 - 1)).toLong()
                Thread.sleep(backoff + jitter)
            }
        }

        Log.e(TAG, "HTTP sync failed after $maxRetries retries")
        return false
    }

    /** Returns true for transient HTTP errors that should be retried. */
    private fun isTransientError(statusCode: Int): Boolean {
        return statusCode == 0 || statusCode == 408 || statusCode == 429 ||
               (statusCode in 500..599)
    }

    // =========================================================================
    // Connectivity Monitoring
    // =========================================================================

    private fun registerConnectivityCallback() {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return

        connectivityCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                isConnected = true
                events.sendConnectivityChange(mapOf("connected" to true))
                if (pendingSyncOnConnect) {
                    pendingSyncOnConnect = false
                    syncAsync()
                }
            }

            override fun onLost(network: Network) {
                isConnected = false
                events.sendConnectivityChange(mapOf("connected" to false))
            }
        }

        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        cm.registerNetworkCallback(request, connectivityCallback!!)
    }

    private fun unregisterConnectivityCallback() {
        connectivityCallback?.let {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            try {
                cm?.unregisterNetworkCallback(it)
            } catch (e: Exception) {
                // Already unregistered
            }
        }
        connectivityCallback = null
    }

    /** Returns true if current network transport is cellular. */
    private fun isCellular(): Boolean {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return false
        val network = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(network) ?: return false
        return caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) &&
               !caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
    }
}
