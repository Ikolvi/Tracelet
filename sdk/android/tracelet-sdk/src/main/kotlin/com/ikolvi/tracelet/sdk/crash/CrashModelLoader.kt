package com.ikolvi.tracelet.sdk.crash

import android.content.Context
import uniffi.tracelet_core.CrashModel
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/**
 * Acquires + decrypts the opt-in crash ML model (#183), or returns `null` so the
 * SDK falls back to the rule-based detector. Never throws to the caller.
 *
 * Flow: use the cached **encrypted** blob if present, else download it; verify
 * the optional SHA-256; AES-256-GCM-decrypt via the Rust core
 * ([CrashModel.fromEncrypted]); return the loaded model. Only the *encrypted*
 * blob is ever written to disk — the decrypted model lives in memory only.
 */
object CrashModelLoader {
    /** Prefix shared by every cached model blob, so stale ones can be pruned. */
    internal const val CACHE_PREFIX = "tracelet_crash_model"

    /**
     * Cache filename for [url] (#314).
     *
     * Every model used to share one fixed filename, which made cache
     * invalidation depend entirely on the optional `crashModelSha256`. That
     * field is only "recommended", and the licensing unlock path may return no
     * digest at all — so pointing `crashModelUrl` at a new model kept loading
     * the old blob forever, with no signal to the host. Keying the cache on the
     * URL makes a URL change a cache miss on its own.
     */
    private fun cacheFileName(url: String): String =
        "${CACHE_PREFIX}_${sha256Hex(url.toByteArray(Charsets.UTF_8)).take(16)}.enc"

    /**
     * AES-256-GCM decryption key (32 bytes), supplied at runtime by the host —
     * injected from a build-time secret or fetched from a key endpoint. It is
     * **never** stored in this open-source repo. When unset, model loading is
     * skipped and the rule engine is used.
     */
    @Volatile
    @JvmStatic
    var decryptionKey: ByteArray? = null

    /**
     * Optional host-supplied provider of a Google Play Integrity token, used for
     * `prod` licenses during [unlock]. Kept as a callback so the base SDK does
     * **not** depend on `com.google.android.play:integrity` — apps that want
     * production licensing add that dependency themselves and set this provider.
     * Returns `null` (or unset) ⇒ no token sent (fine for `dev` licenses).
     */
    @Volatile
    @JvmStatic
    var integrityTokenProvider: (() -> String?)? = null

    /**
     * Loads the model for [url], or `null` to fall back to the rule engine.
     *
     * @param sha256 optional hex digest of the encrypted blob, verified after
     *   fetch; a mismatch discards the cache and returns `null`.
     */
    fun load(
        context: Context,
        url: String,
        sha256: String?,
        log: (String) -> Unit = {},
    ): CrashModel? {
        val key = decryptionKey
        if (key == null) {
            log("crash model: no decryption key set — using rule engine")
            return null
        }
        if (key.size != 32) {
            log("crash model: decryption key must be 32 bytes — using rule engine")
            return null
        }
        return try {
            val cache = File(context.filesDir, cacheFileName(url))
            // Drop blobs cached for any other model URL — only one model is ever
            // active, so keeping the others just wastes disk (#314).
            pruneStaleCaches(context, keep = cache.name)
            var blob = if (cache.exists() && cache.length() > 0) cache.readBytes() else null
            var fromCache = blob != null
            if (blob == null) {
                blob = download(url)
                cache.writeBytes(blob)
            }
            if (sha256 != null && !sha256Hex(blob).equals(sha256, ignoreCase = true)) {
                // Cache is stale (e.g. a new model version was published with a
                // fresh digest). Re-download once so the new model loads in this
                // same session instead of falling back for a cycle (#183).
                if (fromCache) {
                    log("crash model: cached blob is stale — re-downloading new version")
                    cache.delete()
                    blob = download(url)
                    cache.writeBytes(blob)
                    fromCache = false
                }
                if (!sha256Hex(blob).equals(sha256, ignoreCase = true)) {
                    log("crash model: SHA-256 mismatch — discarding cache, using rule engine")
                    cache.delete()
                    return null
                }
            }
            val model = CrashModel.fromEncrypted(blob, key)
            log("crash model: loaded (${model.treeCount()} trees)")
            model
        } catch (e: Exception) {
            log("crash model: load failed (${e.message}) — using rule engine")
            null
        }
    }

    /** Deletes cached model blobs other than [keep] (#314). */
    private fun pruneStaleCaches(context: Context, keep: String) {
        try {
            context.filesDir
                .listFiles { f -> f.name.startsWith(CACHE_PREFIX) && f.name != keep }
                ?.forEach { it.delete() }
        } catch (_: Exception) {
            // Best-effort housekeeping — never fail a load over it.
        }
    }

    private fun download(url: String): ByteArray {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000
            readTimeout = 30_000
            requestMethod = "GET"
        }
        try {
            val code = conn.responseCode
            if (code != 200) throw RuntimeException("download HTTP $code")
            return conn.inputStream.use { it.readBytes() }
        } finally {
            conn.disconnect()
        }
    }

    /** The model URL + integrity digest returned by a successful [unlock]. */
    data class Unlocked(val url: String, val sha256: String?)

    /**
     * Calls a licensing endpoint (the crash-model unlock Worker, #183) to obtain
     * the AES decryption key for a valid [licenseKey], sets [decryptionKey], and
     * returns the model [Unlocked.url] + [Unlocked.sha256] to pass into [load].
     *
     * The key is held in memory only — never written to disk. Returns `null` on
     * any failure (offline, invalid/expired/revoked license, bad response) so the
     * caller falls back to the rule engine.
     *
     * @param unlockUrl POST endpoint, e.g. `https://<worker>.workers.dev/unlock`.
     * @param licenseKey the customer license (`<payload>.<sig>`).
     * @param integrityToken optional Play Integrity token — required only for
     *   `prod` licenses (debug/`dev` licenses omit it).
     */
    fun unlock(
        unlockUrl: String,
        licenseKey: String,
        integrityToken: String? = null,
        log: (String) -> Unit = {},
    ): Unlocked? = try {
        val payload = buildString {
            append("{\"licenseKey\":\"").append(jsonEscape(licenseKey)).append('"')
            if (integrityToken != null) {
                append(",\"integrityToken\":\"").append(jsonEscape(integrityToken)).append('"')
            }
            append('}')
        }
        val conn = (URL(unlockUrl).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000
            readTimeout = 30_000
            requestMethod = "POST"
            doOutput = true
            setRequestProperty("content-type", "application/json")
        }
        try {
            conn.outputStream.use { it.write(payload.toByteArray(Charsets.UTF_8)) }
            val code = conn.responseCode
            if (code != 200) {
                val err = (conn.errorStream ?: conn.inputStream)?.use {
                    String(it.readBytes(), Charsets.UTF_8)
                }
                log("crash model: unlock HTTP $code ${err ?: ""} — using rule engine")
                return null
            }
            val body = conn.inputStream.use { String(it.readBytes(), Charsets.UTF_8) }
            val key = jsonString(body, "key")
            val url = jsonString(body, "url")
            if (key == null || url == null) {
                log("crash model: unlock response missing key/url — using rule engine")
                return null
            }
            val keyBytes = android.util.Base64.decode(key, android.util.Base64.DEFAULT)
            if (keyBytes.size != 32) {
                log("crash model: unlock key not 32 bytes — using rule engine")
                return null
            }
            decryptionKey = keyBytes
            log("crash model: unlocked (${jsonString(body, "scope") ?: "?"})")
            Unlocked(url, jsonString(body, "sha256"))
        } finally {
            conn.disconnect()
        }
    } catch (e: Exception) {
        log("crash model: unlock failed (${e.message}) — using rule engine")
        null
    }

    private fun jsonEscape(s: String): String =
        s.replace("\\", "\\\\").replace("\"", "\\\"")

    /** Minimal string-field extractor for the flat unlock JSON (no deps). */
    private fun jsonString(json: String, field: String): String? {
        val m = Regex("\"" + Regex.escape(field) + "\"\\s*:\\s*\"([^\"]*)\"").find(json)
        return m?.groupValues?.get(1)
    }

    private fun sha256Hex(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256")
            .digest(bytes)
            .joinToString("") { "%02x".format(it) }
}
