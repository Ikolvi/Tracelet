package com.tracelet.core.attestation

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/**
 * Device attestation using Google Play Integrity API.
 *
 * Generates signed attestation tokens that prove the device hardware/software
 * is genuine and untampered. Tokens are cached and refreshed periodically.
 */
class DeviceAttestor(private val context: Context) {

    companion object {
        private const val TAG = "DeviceAttestor"
    }

    private val integrityManager = IntegrityManagerFactory.create(context)
    private val scheduler = Executors.newSingleThreadScheduledExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var cachedToken: Map<String, Any?>? = null

    @Volatile
    private var cachedTimestamp: Long = 0

    private var refreshFuture: ScheduledFuture<*>? = null

    /**
     * Request a fresh attestation token.
     *
     * If a cached token is still valid (within refresh interval), returns
     * the cached version. Otherwise, requests a new token from Play Integrity.
     *
     * @param callback Called with the token map, or null if unavailable
     */
    fun requestToken(callback: (Map<String, Any?>?) -> Unit) {
        // Return cached token if still fresh (within 5 minutes)
        val cached = cachedToken
        if (cached != null && System.currentTimeMillis() - cachedTimestamp < 300_000) {
            callback(cached)
            return
        }

        val nonce = generateNonce()
        try {
            val request = IntegrityTokenRequest.builder()
                .setNonce(nonce)
                .build()

            integrityManager.requestIntegrityToken(request)
                .addOnSuccessListener { response ->
                    val token = response.token()
                    val result = mapOf<String, Any?>(
                        "token" to token,
                        "timestamp" to System.currentTimeMillis(),
                        "provider" to "play_integrity",
                        "verified" to null, // Server-side verification needed
                    )
                    cachedToken = result
                    cachedTimestamp = System.currentTimeMillis()
                    callback(result)
                }
                .addOnFailureListener { e ->
                    Log.w(TAG, "Play Integrity request failed: ${e.message}")
                    callback(null)
                }
        } catch (e: Exception) {
            Log.w(TAG, "Play Integrity unavailable: ${e.message}")
            callback(null)
        }
    }

    /**
     * Start periodic token refresh.
     *
     * @param intervalSeconds Refresh interval in seconds (minimum 60)
     */
    fun startRefresh(intervalSeconds: Int) {
        stopRefresh()
        val interval = intervalSeconds.coerceAtLeast(60).toLong()
        refreshFuture = scheduler.scheduleAtFixedRate(
            { requestToken { /* cache update only */ } },
            interval,
            interval,
            TimeUnit.SECONDS
        )
    }

    /** Stop periodic token refresh. */
    fun stopRefresh() {
        refreshFuture?.cancel(false)
        refreshFuture = null
    }

    /** Get the last cached attestation token, or null. */
    fun getCachedToken(): Map<String, Any?>? = cachedToken

    /**
     * Generate a unique nonce for the integrity request.
     * SHA-256 of device-specific data + timestamp + random bytes.
     */
    private fun generateNonce(): String {
        val random = ByteArray(16)
        SecureRandom().nextBytes(random)
        val data = "${android.os.Build.FINGERPRINT}:${System.currentTimeMillis()}:${random.joinToString("") { "%02x".format(it) }}"
        val digest = MessageDigest.getInstance("SHA-256").digest(data.toByteArray())
        return digest.joinToString("") { "%02x".format(it) }
    }
}
