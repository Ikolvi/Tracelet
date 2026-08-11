package com.ikolvi.tracelet.sdk.geofence
import com.ikolvi.tracelet.sdk.util.TraceletLog

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.location.Location
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.TraceletEventSender
import com.ikolvi.tracelet.sdk.util.BatteryUtils
import uniffi.tracelet_core.GeofenceEvaluator
import uniffi.tracelet_core.CoreGeofence
import uniffi.tracelet_core.Coordinate
import com.ikolvi.tracelet.sdk.receiver.GeofenceBroadcastReceiver
import com.ikolvi.tracelet.sdk.wrapper.TraceletGeofence
import com.ikolvi.tracelet.sdk.wrapper.TraceletGeofencingClient
import com.ikolvi.tracelet.sdk.wrapper.TraceletGeofencingRequest
import com.ikolvi.tracelet.sdk.wrapper.TraceletServices
import android.os.Looper
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Geofencing engine using Google Play Services GeofencingClient.
 *
 * Features:
 * - Add/remove individual and batch geofences
 * - Persist geofence definitions in SQLite
 * - Proximity-based monitoring: registers only geofences within proximity radius
 * - Knock-out mode: auto-remove after first trigger
 * - Re-registers geofences on boot/restart
 */
class GeofenceManager(
    private val context: Context,
    private val config: ConfigManager,
    private val events: TraceletEventSender,
    private val rustDatabase: uniffi.tracelet_core.DatabaseManager? = null,
    private val geofencingClient: TraceletGeofencingClient = TraceletServices.getInstance(context).getGeofencingClient(context),
    /**
     * Provides the most recent GPS fix so geofence transition payloads can be
     * enriched with real coordinate telemetry (accuracy/speed/heading/altitude)
     * instead of hardcoded zeros (#231). Wired from [TraceletSdk] to the active
     * [com.ikolvi.tracelet.sdk.location.LocationEngine].
     */
    private val lastLocationProvider: (() -> Location?)? = null,
) {
    var onGeofenceEvent: ((Map<String, Any?>) -> Unit)? = null

    /**
     * Invoked when the OS reports a transition for a fence the in-app evaluator
     * owns — i.e. the wake-up that [wakeupRadiusMeters]'s inflated registration
     * exists to produce (#355).
     *
     * The transition itself is discarded (it describes the 100 m wake-up
     * boundary, not the fence), but the *arrival* is information: the device is
     * near a fence only this SDK can decide, and deciding it needs the location
     * stream. In the killed state that stream may have been throttled to
     * stationary-periodic by #319's reconcile, so without this the wake-up wakes
     * nothing and a small fence goes quiet exactly when the app is gone.
     *
     * Hosts wire this to resume continuous tracking.
     */
    var onEvaluatorWakeup: (() -> Unit)? = null

    /**
     * Invoked whenever the stored fence set changes, because that is when the
     * answer to [hasEvaluatorOwnedGeofences] can change (#357).
     *
     * A fence the evaluator owns is decided from the raw fix stream, so who owns
     * the current fences dictates the cadence the provider is requested with.
     * The host answers that question at `start()`, but the fence set is mutable
     * for the rest of the session: a 10 m fence added afterwards left
     * `minUpdateDistanceMeters` at the configured distance filter and the
     * evaluator saw one fix per that many metres travelled — too few to ever
     * confirm an EXIT.
     *
     * Fired from the manager rather than the SDK facade so the internal removals
     * (KnockOut mode) are covered too.
     */
    var onEvaluatorOwnershipChanged: (() -> Unit)? = null
    companion object {
        private const val TAG = "GeofenceManager"
        const val ACTION_GEOFENCE_EVENT = "com.tracelet.ACTION_GEOFENCE_EVENT"

        /** Google Play Services maximum geofences per app. */
        private const val PLATFORM_MAX_GEOFENCES = 100

        /** Timeout for Play Services geofence registration (ms). */
        private const val REGISTRATION_TIMEOUT_MS = 5000L

        /**
         * SharedPreferences store for the persisted high-accuracy inside-set
         * ([knownInsideIds]). Kept separate from `com.tracelet.state` so a full
         * state reset does not clear crossing history and vice-versa (#292).
         */
        private const val GEOFENCE_STATE_PREFS = "com.tracelet.geofence.state"

        /** Key for the persisted set of geofence ids the device is inside (#292). */
        private const val KEY_KNOWN_INSIDE = "knownInsideIds"

        /**
         * Category prefix for geofence log lines.
         *
         * The persisted log store has a `source` column, but Android hardcodes
         * it to `"plugin"` and Dart's `LogEntry` drops it entirely, so a message
         * prefix is currently the only category that survives to
         * `Tracelet.getLogs()` and the Doctor bug report. Keep it greppable.
         */
        private const val GEOFENCE_LOG_TAG = "[geofence]"

        /**
         * Mirror of `GEOFENCE_EXIT_HYSTERESIS_FRACTION` in the Rust core's
         * `geofence_evaluator.rs`. Used for logging only — the Rust evaluator
         * remains the single source of truth for the actual decision.
         *
         * `GeofenceManagerTransitionLogTest` pins these against the evaluator's
         * real behavior at the boundary, so a change on the Rust side fails a
         * test rather than silently producing misleading log lines.
         */
        private const val EXIT_HYSTERESIS_FRACTION = 0.1

        /** Mirror of `GEOFENCE_MIN_EXIT_HYSTERESIS_METERS` in the Rust core. */
        private const val MIN_EXIT_HYSTERESIS_METERS = 20.0

        /** Mirror of `GEOFENCE_ABS_MIN_EXIT_HYSTERESIS_METERS` in the Rust core. */
        private const val ABS_MIN_EXIT_HYSTERESIS_METERS = 3.0

        /**
         * Smallest radius Play Services can decide for itself, in metres.
         *
         * Below this the fence is smaller than the error of the fixes it is
         * compared against, so the platform never becomes confident enough to
         * report a crossing: it fires the `INITIAL_TRIGGER_ENTER` on
         * registration — which looks like it works — and then nothing, ever
         * (#355).
         *
         * Small fences are *not* rejected. They are simply decided here instead:
         * a fence under this radius is owned by the in-app evaluator, which
         * knows the true radius and scales its hysteresis to the measured fix
         * accuracy rather than a flat 20 m (#355). See [isEvaluatorOwned].
         */
        private const val OS_MIN_RESOLVABLE_RADIUS_METERS = 100.0
    }

    /**
     * Whether the in-app evaluator — not the OS — decides this fence's
     * transitions.
     *
     * Three cases, and each is a case the OS cannot serve:
     *
     *  - **Polygons.** Play Services only monitors circles, so a polygon is
     *    never registered with it and has always been ours to evaluate.
     *  - **Sub-[OS_MIN_RESOLVABLE_RADIUS_METERS] circles.** Registered only as a
     *    coarse wake-up (see [wakeupRadiusMeters]); at that inflated radius the
     *    OS's own transitions are about the wrong boundary, so they are
     *    discarded and the true radius is applied here (#355).
     *  - **`geofenceModeHighAccuracy`.** The caller has asked for in-app
     *    evaluation of everything.
     *
     * Ownership is per fence, not global: a config with one 20 m fence and one
     * 500 m fence has the first decided here and the second by the OS, each by
     * whichever is actually able to.
     */
    private fun isEvaluatorOwned(geofence: Map<String, Any?>): Boolean {
        val vertices = geofence["vertices"]
        if (vertices is List<*> && vertices.size >= 3) return true
        if (config.getGeofenceModeHighAccuracy()) return true
        val radius = (geofence["radius"] as? Number)?.toDouble() ?: return false
        return radius > 0.0 && radius < OS_MIN_RESOLVABLE_RADIUS_METERS
    }

    /**
     * The radius a circular fence is registered with at the OS level.
     *
     * A sub-serviceable fence is inflated to [OS_MIN_RESOLVABLE_RADIUS_METERS]
     * because at its true radius Play Services will not reliably fire at all —
     * and firing is the entire point of the OS registration for these fences.
     * It is not there to detect the crossing (the evaluator does that, at the
     * true radius); it is there to wake the process when the device comes near,
     * which is the only way a 10 m fence can work in `geofences` tracking mode
     * or after the app is killed.
     *
     * The consequence — the OS reporting ENTER 100 m from a 10 m fence — is
     * handled by [isEvaluatorOwned] discarding those transitions.
     */
    private fun wakeupRadiusMeters(radius: Float): Float =
        if (radius > 0f && radius < OS_MIN_RESOLVABLE_RADIUS_METERS) {
            OS_MIN_RESOLVABLE_RADIUS_METERS.toFloat()
        } else {
            radius
        }

    /**
     * Whether any stored fence needs the uninterrupted fix stream that in-app
     * evaluation runs on.
     *
     * Drives `LocationEngine.geofenceHighAccuracyMode`, which drops the
     * OS-level distance filter so a slow-moving device is not starved of the
     * fixes its crossings are computed from.
     */
    fun hasEvaluatorOwnedGeofences(): Boolean =
        config.getGeofenceModeHighAccuracy() || getCachedGeofences().any { isEvaluatorOwned(it) }

    /**
     * Exit-hysteresis band the Rust evaluator applies for [radius] at a fix
     * accuracy of [accuracy]. Mirrors `exit_hysteresis_meters` in the core so
     * the decision trace reports the threshold actually used. Logging only.
     */
    private fun exitHysteresisMeters(radius: Double, accuracy: Double): Double {
        val jitter = if (accuracy > 0.0) {
            accuracy.coerceIn(ABS_MIN_EXIT_HYSTERESIS_METERS, MIN_EXIT_HYSTERESIS_METERS)
        } else {
            MIN_EXIT_HYSTERESIS_METERS
        }
        return maxOf(radius * EXIT_HYSTERESIS_FRACTION, jitter)
    }

    /**
     * Records that a sub-serviceable fence has been handed to the in-app
     * evaluator (#355).
     *
     * On the always-on lifecycle channel: which component owns a fence is the
     * first thing a "geofences stopped firing" report needs to establish, and
     * such a report arrives from a release build whose `logLevel` may be `off`.
     */
    private fun noteSmallRadiusHandling(identifier: String, radius: Double) {
        if (radius <= 0.0 || radius >= OS_MIN_RESOLVABLE_RADIUS_METERS) return
        TraceletLog.lifecycle(
            "$GEOFENCE_LOG_TAG $identifier radius=${fmt1(radius)}m is below the " +
                "${fmt1(OS_MIN_RESOLVABLE_RADIUS_METERS)}m Play Services can resolve — " +
                "transitions will be evaluated in-app at the true radius, and the OS " +
                "fence is registered at ${fmt1(OS_MIN_RESOLVABLE_RADIUS_METERS)}m as a " +
                "wake-up only. Requires location updates to be running (#355)"
        )
    }

    /** One-decimal formatter that avoids locale-dependent decimal separators in logs. */
    private fun fmt1(value: Double): String = String.format(java.util.Locale.US, "%.1f", value)

    private var geofencePendingIntent: PendingIntent? = null

    /**
     * In-memory cache of geofences to prevent executing database queries per GPS location update.
     * Maps are preserved to maintain compatibility with system location callbacks and Dart channel handlers.
     */
    private var cachedGeofences: List<Map<String, Any?>>? = null

    /**
     * Retrieves geofences from the local cache. If the cache is empty or has been invalidated,
     * it performs a fresh query against the shared Rust database and maps the [CoreGeofence]
     * models to generic map structures.
     */
    private fun getCachedGeofences(): List<Map<String, Any?>> {
        val cached = cachedGeofences
        if (cached != null) {
            return cached
        }
        val loaded = rustDatabase?.getGeofences() ?: emptyList()
        val mapped = loaded.map { mapFromCoreGeofence(it) }
        cachedGeofences = mapped
        return mapped
    }

    /**
     * Invalidates the in-memory geofence cache. Forces a query against the Rust DB on the next access.
     */
    private fun invalidateGeofenceCache() {
        cachedGeofences = null
    }

    /**
     * Helper method to transform a Rust [CoreGeofence] record into a generic map structure.
     * Translates coordinates and poly-vertex lists into the standard JSON-compatible formats.
     */
    private fun mapFromCoreGeofence(gf: CoreGeofence): Map<String, Any?> {
        val verticesList = gf.vertices.map { listOf(it.lat, it.lng) }
        val result = mutableMapOf<String, Any?>(
            "identifier" to gf.identifier,
            "latitude" to gf.latitude,
            "longitude" to gf.longitude,
            "radius" to gf.radius,
            "vertices" to verticesList,
            // #355: these four were absent here, so every fence rebuilt from
            // the database — on each proximity change, reboot and task removal
            // — was re-registered with notifyOnDwell=false and loiteringDelay=0,
            // silently killing DWELL for the rest of the install.
            "notifyOnEntry" to gf.notifyOnEntry,
            "notifyOnExit" to gf.notifyOnExit,
            "notifyOnDwell" to gf.notifyOnDwell,
            "loiteringDelay" to gf.loiteringDelay,
        )
        
        gf.extras?.let { extrasStr ->
            try {
                val jsonObject = org.json.JSONObject(extrasStr)
                val map = mutableMapOf<String, Any?>()
                val keys = jsonObject.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    map[key] = jsonObject.get(key)
                }
                result["extras"] = map
            } catch (e: Exception) {
                TraceletLog.warning("Failed to parse geofence extras from DB: ${e.message}")
            }
        }
        return result
    }

    /** Registered (active on the platform) geofence identifiers (thread-safe, A-M6). */
    private val activeGeofenceIds: MutableSet<String> = ConcurrentHashMap.newKeySet()

    /** High-accuracy mode: track which geofences the device is currently inside. */
    private val insideGeofenceIds = mutableSetOf<String>()

    private val geofenceStatePrefs: SharedPreferences by lazy {
        context.getSharedPreferences(GEOFENCE_STATE_PREFS, Context.MODE_PRIVATE)
    }

    /**
     * Geofences the device is inside per the last *emitted* high-accuracy
     * transition, persisted across process death.
     *
     * The Rust evaluator's own inside-set is in-memory only and is wiped on
     * every resume/boot by [clearHighAccuracyState] (via `startGeofences()` on
     * each `ready()`/takeover, and by `LocationService` after boot/task-removal).
     * A stationary device inside a fence therefore re-satisfies
     * `entered && !was_inside` after each wipe and the evaluator re-emits ENTER.
     * On an attendance backend every such ENTER becomes a false punch-in (#292).
     *
     * This set survives those resets, so [evaluateHighAccuracyProximity]
     * suppresses an ENTER for a fence it already reported and an EXIT for a
     * fence it never reported entering. It is cleared only by
     * [resetHighAccuracyInsideState] (fresh start) and [destroy].
     */
    private val knownInsideIds: MutableSet<String> by lazy {
        // getStringSet's returned instance must not be mutated (Android docs),
        // so copy into an owned mutable set.
        (geofenceStatePrefs.getStringSet(KEY_KNOWN_INSIDE, emptySet()) ?: emptySet())
            .toMutableSet()
    }

    /** Flushes [knownInsideIds] to disk. Passes a fresh copy (put must not alias). */
    private fun persistKnownInside() {
        geofenceStatePrefs.edit()
            .putStringSet(KEY_KNOWN_INSIDE, knownInsideIds.toSet())
            .apply()
    }

    /**
     * True once the freshly-constructed evaluator has been reconciled with the
     * persisted [knownInsideIds] for this manager lifetime (see
     * [seedEvaluatorFromKnownInside]).
     */
    private var evaluatorSeeded = false

    /**
     * Reconcile the newly-constructed (empty) evaluator with the persisted
     * [knownInsideIds] by replaying one synthetic in-fence fix per known-inside
     * geofence, so the evaluator — not a side table — stays the single source of
     * truth across process death (#292):
     *
     *  - a device still inside a fence produces no ENTER (the evaluator already
     *    knows it is inside), and
     *  - a device that left a fence *while the process was dead* produces a real
     *    EXIT on the first outside fix, instead of the inside-state getting
     *    stuck and suppressing the next genuine ENTER.
     *
     * The synthetic ENTERs are discarded — [knownInsideIds] already reflects
     * them. Runs once per manager lifetime, before the first real evaluation.
     */
    private fun seedEvaluatorFromKnownInside(byId: Map<String?, Map<String, Any?>>) {
        if (evaluatorSeeded) return
        evaluatorSeeded = true
        if (knownInsideIds.isEmpty()) return
        for (id in knownInsideIds) {
            val gf = byId[id] ?: continue
            val point = insidePoint(gf) ?: continue
            // Discard the synthetic ENTER; we only want the adopted inside-state.
            geofenceEvaluator.evaluateProximity(point.first, point.second, 0.0, listOf(mapToCoreGeofence(gf)))
        }
    }

    /**
     * A point guaranteed inside [gf] used to seed the evaluator: the centre for
     * a circle, the vertex centroid for a polygon (inside for convex polygons;
     * a concave polygon whose centroid falls outside simply is not seeded and
     * falls back to the persisted-set dedup).
     */
    private fun insidePoint(gf: Map<String, Any?>): Pair<Double, Double>? {
        val vertices = gf["vertices"]
        if (vertices is List<*> && vertices.size >= 3) {
            var sumLat = 0.0
            var sumLng = 0.0
            var n = 0
            for (v in vertices) {
                if (v is List<*> && v.size >= 2) {
                    val vLat = (v[0] as? Number)?.toDouble()
                    val vLng = (v[1] as? Number)?.toDouble()
                    if (vLat != null && vLng != null) {
                        sumLat += vLat
                        sumLng += vLng
                        n++
                    }
                }
            }
            if (n == 0) return null
            return Pair(sumLat / n, sumLng / n)
        }
        val lat = (gf["latitude"] as? Number)?.toDouble() ?: return null
        val lng = (gf["longitude"] as? Number)?.toDouble() ?: return null
        return Pair(lat, lng)
    }

    /** High-accuracy geofence evaluator (polygon + circular). */
    private val geofenceEvaluator = GeofenceEvaluator()

    /** Last known device location for proximity filtering. */
    private var lastLatitude: Double? = null
    private var lastLongitude: Double? = null

    // =========================================================================
    // Public API
    // =========================================================================

    /** Add a single geofence. Persists to DB and registers if within proximity. */
    fun addGeofence(geofenceMap: Map<String, Any?>): Boolean {
        val identifier = geofenceMap["identifier"] as? String ?: return false

        // Persist to database
        val lat = (geofenceMap["latitude"] as? Number)?.toDouble() ?: 0.0
        val lng = (geofenceMap["longitude"] as? Number)?.toDouble() ?: 0.0
        val radius = (geofenceMap["radius"] as? Number)?.toDouble() ?: 0.0

        // Noted at add time, not registration time: this is the moment the
        // caller chose the radius, and it fires once per fence rather than on
        // every proximity re-registration (#355).
        val isPolygonShape = (geofenceMap["vertices"] as? List<*>)?.let { it.size >= 3 } == true
        if (!isPolygonShape) noteSmallRadiusHandling(identifier, radius)

        val verticesRaw = geofenceMap["vertices"] as? List<*>
        var coreVertices: List<Coordinate>? = null
        if (verticesRaw != null) {
            val vList = mutableListOf<Coordinate>()
            for (v in verticesRaw) {
                if (v is List<*> && v.size >= 2) {
                    val vLat = (v[0] as? Number)?.toDouble()
                    val vLng = (v[1] as? Number)?.toDouble()
                    if (vLat != null && vLng != null) {
                        vList.add(Coordinate(vLat, vLng))
                    }
                }
            }
            coreVertices = vList.takeIf { it.isNotEmpty() }
        }

        val extrasRaw = geofenceMap["extras"] as? Map<*, *>
        var extrasStr: String? = null
        if (extrasRaw != null) {
            try {
                extrasStr = org.json.JSONObject(extrasRaw).toString()
            } catch (e: Exception) {
                TraceletLog.warning("Failed to stringify geofence extras: ${e.message}")
            }
        }
        
        // Same defaulting the registration path uses, so what is persisted is
        // exactly what was registered (#355).
        val notifyOnEntry = geofenceMap["notifyOnEntry"] != false
        val notifyOnExit = geofenceMap["notifyOnExit"] != false
        val notifyOnDwell = geofenceMap["notifyOnDwell"] == true
        val loiteringDelay = (geofenceMap["loiteringDelay"] as? Number)?.toInt() ?: 0

        try {
            rustDatabase?.insertGeofence(
                identifier, lat, lng, radius, coreVertices, extrasStr,
                notifyOnEntry, notifyOnExit, notifyOnDwell, loiteringDelay,
            )
        } catch (e: Exception) {
            TraceletLog.error("Failed to persist geofence to Rust DB", e)
        }
        
        invalidateGeofenceCache()
        onEvaluatorOwnershipChanged?.invoke()

        // Polygon geofences are evaluated in Dart — no system registration needed
        val vertices = geofenceMap["vertices"]
        if (vertices is List<*> && vertices.size >= 3) return true

        // If we have a known device location, use proximity-based registration
        val deviceLat = lastLatitude
        val deviceLng = lastLongitude
        if (deviceLat != null && deviceLng != null) {
            updateProximity(deviceLat, deviceLng)
            return true
        }

        // No known location — register directly (will be proximity-filtered later)
        return registerGeofence(geofenceMap)
    }

    /** Add multiple geofences. Returns true if all succeeded. */
    fun addGeofences(geofences: List<Map<String, Any?>>): Boolean {
        if (!hasPermission()) return false

        var allSuccess = true
        for (gf in geofences) {
            if (!addGeofence(gf)) allSuccess = false
        }
        return allSuccess
    }

    /** Remove a single geofence by identifier. */
    fun removeGeofence(identifier: String): Boolean {
        try {
            rustDatabase?.deleteGeofence(identifier)
        } catch (e: Exception) {
            TraceletLog.error("Failed to delete geofence from Rust DB", e)
        }
        invalidateGeofenceCache()
        onEvaluatorOwnershipChanged?.invoke()
        // Forget any inside-state for this fence so a later re-add — or an id
        // reused for a different location — starts clean instead of having its
        // ENTER suppressed by stale persisted state (#292).
        if (knownInsideIds.remove(identifier)) persistKnownInside()
        geofenceEvaluator.removeGeofence(identifier)
        return unregisterGeofence(identifier)
    }

    /** Remove all geofences. */
    fun removeGeofences(): Boolean {
        try {
            rustDatabase?.clearGeofences()
        } catch (e: Exception) {
            TraceletLog.error("Failed to clear geofences from Rust DB", e)
        }
        invalidateGeofenceCache()
        onEvaluatorOwnershipChanged?.invoke()
        // No fences means the device is inside nothing — forget all inside-state
        // so a subsequent add/enter is reported cleanly (#292).
        if (knownInsideIds.isNotEmpty()) {
            knownInsideIds.clear()
            persistKnownInside()
        }
        geofenceEvaluator.clear()
        return unregisterAllGeofences()
    }

    fun getGeofences(): List<Map<String, Any?>> = getCachedGeofences()

    /** Get a single geofence by identifier. */
    fun getGeofence(identifier: String): Map<String, Any?>? = getCachedGeofences().find { it["identifier"] == identifier }

    /** Check if a geofence exists. */
    fun geofenceExists(identifier: String): Boolean = getGeofence(identifier) != null

    /**
     * Re-registers persisted geofences with the GeofencingClient.
     * Called on boot/restart. Uses proximity filtering when a device location
     * is available; otherwise registers all (up to platform max).
     */
    fun reRegisterAll() {
        if (!hasPermission()) return
        val lat = lastLatitude
        val lng = lastLongitude
        if (lat != null && lng != null) {
            updateProximity(lat, lng)
            return
        }
        // No known location — register all circular geofences (capped at platform max)
        val geofences = getCachedGeofences()
        var count = 0
        val maxMonitored = resolveMaxMonitored()
        for (gf in geofences) {
            if (count >= maxMonitored) break
            val vertices = gf["vertices"]
            if (vertices is List<*> && vertices.size >= 3) continue
            val radius = (gf["radius"] as? Number)?.toFloat() ?: 0f
            if (radius <= 0f) continue
            registerGeofence(gf)
            count++
        }
    }

    /**
     * Called when a geofence event is received from GeofenceBroadcastReceiver.
     * Dispatches events via TraceletEventSender.
     *
     * OS-level events are dropped for fences the in-app evaluator owns (see
     * [isEvaluatorOwned]) — under `geofenceModeHighAccuracy` that is every
     * fence, and otherwise it is the small ones whose OS registration is
     * inflated to a wake-up radius and whose transitions therefore describe the
     * wrong boundary. [evaluateHighAccuracyProximity] reports those instead.
     */
    fun handleGeofenceEvent(
        transitionType: Int,
        triggeringGeofences: List<TraceletGeofence>,
        latitude: Double,
        longitude: Double,
    ) {
        // Per fence, not globally: a mixed set has its large fences decided by
        // the OS and its small ones in-app, and each must reach exactly one path.
        var sawEvaluatorOwned = false
        val triggeringGeofences = triggeringGeofences.filter { gf ->
            val stored = getGeofence(gf.requestId)
            val owned = stored != null && isEvaluatorOwned(stored)
            if (owned) {
                sawEvaluatorOwned = true
                TraceletLog.debug(
                    "$GEOFENCE_LOG_TAG ignoring OS transition for ${gf.requestId} " +
                        "— evaluated in-app at its true radius (#355)"
                )
            }
            !owned
        }

        // The discarded transition still did its job: it told us we are near a
        // fence only the evaluator can decide. Claim the wake-up before
        // returning, or the inflated registration is pure cost (#355).
        if (sawEvaluatorOwned) {
            TraceletLog.lifecycle(
                "$GEOFENCE_LOG_TAG wake-up from the OS near an in-app fence — " +
                    "resuming the location stream so its true radius can be " +
                    "evaluated (#355)"
            )
            onEvaluatorWakeup?.invoke()
        }
        if (triggeringGeofences.isEmpty()) return

        val action = when (transitionType) {
            1 -> "ENTER" // Geofence.GEOFENCE_TRANSITION_ENTER
            2 -> "EXIT"  // Geofence.GEOFENCE_TRANSITION_EXIT
            4 -> "DWELL" // Geofence.GEOFENCE_TRANSITION_DWELL
            else -> return
        }

        for (geofence in triggeringGeofences) {
            val identifier = geofence.requestId
            val storedGf = getGeofence(identifier)

            // The OS/AOSP path has no accuracy gating at all — the platform owns
            // debouncing. Log it distinctly so a bug report makes clear which
            // path produced the transition (source=os vs the in-app evaluator).
            //
            // On the always-on lifecycle channel (#318), not INFO: a crossing is
            // the SDK's primary product event and is exactly what a "geofences
            // stopped firing" report needs, but it arrives days later from a
            // release build whose logLevel may be `error` or `off` — which
            // dropped the INFO line and left the report with nothing to show
            // either way. Crossings are a handful a day, so the row budget is
            // unaffected (#352).
            TraceletLog.lifecycle(
                "$GEOFENCE_LOG_TAG $action $identifier source=os " +
                    "transitionType=$transitionType (no accuracy gating on this path)"
            )

            val eventData = mapOf(
                "uuid" to java.util.UUID.randomUUID().toString(),
                "event" to "geofence",
                "timestamp" to java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US).apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }.format(java.util.Date()),
                "coords" to buildCoords(latitude, longitude),
                "battery" to currentBattery(),
                "geofence" to mapOf(
                    "identifier" to identifier,
                    "action" to action,
                    "extras" to storedGf?.get("extras")
                )
            )

            onGeofenceEvent?.invoke(eventData)
            events.sendGeofence(eventData)

            // Knock-out mode: remove geofence after EXIT
            if (action == "EXIT" && config.getGeofenceModeKnockOut()) {
                removeGeofence(identifier)
            }
        }

        // Fire geofencesChange event
        val on = mutableListOf<Map<String, Any?>>()
        val off = mutableListOf<Map<String, Any?>>()
        for (gf in triggeringGeofences) {
            val gfMap = getGeofence(gf.requestId) ?: mapOf("identifier" to gf.requestId)
            when (action) {
                "ENTER" -> on.add(gfMap)
                "EXIT" -> off.add(gfMap)
            }
        }
        if (on.isNotEmpty() || off.isNotEmpty()) {
            events.sendGeofencesChange(mapOf("on" to on, "off" to off))
        }
    }

    /**
     * High-accuracy geofence evaluation.
     *
     * Uses [GeofenceEvaluator] to perform software-based ENTER/EXIT detection
     * for both circular and polygon geofences. Dispatches transition events
     * and geofencesChange events via [TraceletEventSender].
     *
     * Called on each location update when `geofenceModeHighAccuracy` is enabled.
     */
    /**
     * Applies the [ConfigManager.getGeofenceExitAccuracyMax] policy to the raw
     * fix accuracy before it reaches the evaluator's accuracy-aware EXIT test
     * (#274/#276):
     * - `-1` (default): pass accuracy through unchanged (full gating).
     * - `0`: return 0 — disables gating (fastest, drift-prone EXIT).
     * - `N > 0`: clamp accuracy to N, bounding the worst-case EXIT delay.
     */
    private fun effectiveExitAccuracy(accuracy: Double): Double {
        val max = config.getGeofenceExitAccuracyMax()
        return when {
            max < 0 -> accuracy
            max == 0 -> 0.0
            else -> minOf(accuracy, max.toDouble())
        }
    }

    /**
     * Builds the `[geofence]`-tagged decision trace logged alongside every
     * transition.
     *
     * A geofence crossing is the SDK's primary product event, yet nothing was
     * logged when one fired — so a field report of "occasional false EXIT" was
     * undiagnosable from a bug report, at any log level. This line carries every
     * input to the accuracy-aware EXIT test (#274/#276) so a drift-induced EXIT
     * can be told apart from a genuine one without a reproduction:
     *
     * - `dist` vs `thr` shows how far past the boundary the fix landed
     * - `accRaw`/`accEff` exposes the [effectiveExitAccuracy] clamp, including
     *   the case where `geofenceExitAccuracyMax` is set but never binds
     * - a small `accRaw` with a large `dist` is the signature of an
     *   over-confident fix, which accuracy gating cannot defend against
     */
    private fun transitionTrace(
        action: String,
        identifier: String,
        gfMap: Map<String, Any?>?,
        latitude: Double,
        longitude: Double,
        accuracyRaw: Double,
        accuracyEffective: Double,
    ): String {
        val builder = StringBuilder(GEOFENCE_LOG_TAG)
        builder.append(' ').append(action).append(' ').append(identifier)

        val gfLat = (gfMap?.get("latitude") as? Number)?.toDouble()
        val gfLng = (gfMap?.get("longitude") as? Number)?.toDouble()
        val radius = (gfMap?.get("radius") as? Number)?.toDouble()
        val vertices = gfMap?.get("vertices")
        val isPolygon = vertices is List<*> && vertices.size >= 3

        if (isPolygon) {
            // Polygon membership is a point-in-polygon test; radius, hysteresis
            // and accuracy gating do not participate.
            builder.append(" shape=polygon vertices=").append((vertices as List<*>).size)
        } else if (gfLat != null && gfLng != null && radius != null && radius > 0.0) {
            val distance = haversine(latitude, longitude, gfLat, gfLng)
            val buffer = exitHysteresisMeters(radius, accuracyEffective)
            val threshold = radius + buffer
            builder.append(" dist=").append(fmt1(distance))
                .append(" radius=").append(fmt1(radius))
                .append(" buffer=").append(fmt1(buffer))
                .append(" thr=").append(fmt1(threshold))
                .append(" margin=").append(fmt1(distance - accuracyEffective - threshold))
        }

        builder.append(" accRaw=").append(fmt1(accuracyRaw))
            .append(" accEff=").append(fmt1(accuracyEffective))
            .append(" exitAccuracyMax=").append(config.getGeofenceExitAccuracyMax())

        if (accuracyRaw <= 0.0) {
            // Android returns 0.0f from Location.getAccuracy() when the fix
            // carries no accuracy, and the evaluator maps any non-positive value
            // to "gating disabled". Unknown uncertainty therefore behaves as zero
            // uncertainty — flag it, because it makes a false EXIT far more
            // likely and is otherwise invisible. Mirrors the iOS trace, where
            // CoreLocation reports a negative horizontalAccuracy instead.
            builder.append(" accuracyInvalid=true gatingDisabled=true")
        } else if (accuracyEffective < accuracyRaw) {
            // The #276 clamp actually bound on this fix, weakening drift
            // immunity relative to the -1 default. Worth calling out explicitly.
            builder.append(" clampApplied=true")
        }
        return builder.toString()
    }

    fun evaluateHighAccuracyProximity(latitude: Double, longitude: Double, accuracy: Double = 0.0) {
        // Only the fences this path owns (see [isEvaluatorOwned]). Feeding the
        // evaluator a fence the OS is also reporting would double-fire it, so
        // ownership is exclusive on both sides of the split.
        val allGeofences = getCachedGeofences().filter { isEvaluatorOwned(it) }
        if (allGeofences.isEmpty()) return

        val geofenceMapById = allGeofences.associateBy { it["identifier"] as? String }
        // Reconcile a cold-started evaluator with the persisted inside-set before
        // the first real fix, so a leave-while-dead is caught (#292).
        seedEvaluatorFromKnownInside(geofenceMapById)

        val effectiveAccuracy = effectiveExitAccuracy(accuracy)
        val coreGeofences = allGeofences.map { mapToCoreGeofence(it) }
        val transitions = geofenceEvaluator.evaluateProximity(
            latitude = latitude,
            longitude = longitude,
            accuracy = effectiveAccuracy,
            geofences = coreGeofences,
        )
        if (transitions.isEmpty()) {
            if (effectiveAccuracy < accuracy) {
                // No transition, but the clamp bound on this fix. Cheap to log
                // and it surfaces a mis-set geofenceExitAccuracyMax without
                // waiting for a crossing.
                TraceletLog.debug(
                    "$GEOFENCE_LOG_TAG no transition — accRaw=${fmt1(accuracy)} " +
                        "accEff=${fmt1(effectiveAccuracy)} clampApplied=true " +
                        "exitAccuracyMax=${config.getGeofenceExitAccuracyMax()}"
                )
            }
            return
        }

        val on = mutableListOf<Map<String, Any?>>()
        val off = mutableListOf<Map<String, Any?>>()

        for (t in transitions) {
            // Persisted-state dedup (#292). The evaluator's in-memory inside-set
            // is wiped on every resume/boot, so a stationary device inside a
            // fence re-produces an ENTER the app already emitted. knownInsideIds
            // survives that reset: suppress an ENTER for a fence we already
            // reported inside, and an EXIT for a fence we never reported
            // entering. Genuine crossings still pass through and flip the set.
            val alreadyInside = knownInsideIds.contains(t.identifier)
            if (t.action == "ENTER" && alreadyInside) {
                TraceletLog.debug(
                    "$GEOFENCE_LOG_TAG suppressed duplicate ENTER ${t.identifier} " +
                        "— already inside per persisted state (resume/boot re-entry)"
                )
                continue
            }
            if (t.action == "EXIT" && !alreadyInside) {
                TraceletLog.debug(
                    "$GEOFENCE_LOG_TAG suppressed EXIT ${t.identifier} " +
                        "— not inside per persisted state"
                )
                continue
            }
            when (t.action) {
                "ENTER" -> knownInsideIds.add(t.identifier)
                "EXIT" -> knownInsideIds.remove(t.identifier)
            }
            persistKnownInside()

            val gfMap = geofenceMapById[t.identifier]

            // On the always-on lifecycle channel (#318), not INFO or DEBUG: a
            // false EXIT is reported days later by an end user, from a release
            // build whose logLevel may be `error` or `off` — which dropped even
            // the INFO line, so the bug report that was supposed to explain the
            // crossing contained no trace of it. Volume is a handful of lines
            // per day, and the line carries no coordinates (#352).
            TraceletLog.lifecycle(
                transitionTrace(
                    action = t.action,
                    identifier = t.identifier,
                    gfMap = gfMap,
                    latitude = latitude,
                    longitude = longitude,
                    accuracyRaw = accuracy,
                    accuracyEffective = effectiveAccuracy,
                )
            )

            val eventData = mapOf(
                "uuid" to java.util.UUID.randomUUID().toString(),
                "event" to "geofence",
                "timestamp" to java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US).apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }.format(java.util.Date()),
                "coords" to buildCoords(latitude, longitude),
                "battery" to currentBattery(),
                "geofence" to mapOf(
                    "identifier" to t.identifier,
                    "action" to t.action,
                    "extras" to gfMap?.get("extras")
                )
            )
            
            onGeofenceEvent?.invoke(eventData)
            events.sendGeofence(eventData)

            when (t.action) {
                "ENTER" -> gfMap?.let { on.add(it) }
                "EXIT" -> {
                    gfMap?.let { off.add(it) }
                    if (config.getGeofenceModeKnockOut()) {
                        removeGeofence(t.identifier)
                        geofenceEvaluator.removeGeofence(t.identifier)
                    }
                }
            }
        }

        if (on.isNotEmpty() || off.isNotEmpty()) {
            events.sendGeofencesChange(mapOf("on" to on, "off" to off))
        }
    }

    /**
     * Update proximity-based geofence monitoring.
     *
     * Evaluates which stored geofences are within [ConfigManager.getGeofenceProximityRadius]
     * of the given device location, sorts them by distance, and registers only the closest
     * N geofences with the OS (where N = min(maxMonitoredGeofences, PLATFORM_MAX_GEOFENCES)).
     *
     * Geofences that move out of proximity are unregistered. Geofences that move into
     * proximity are registered. A `geofencesChange` event is fired for any changes.
     *
     * This enables monitoring thousands of geofences despite the Android limit of 100.
     */
    fun updateProximity(latitude: Double, longitude: Double) {
        lastLatitude = latitude
        lastLongitude = longitude

        if (!hasPermission()) return

        val proximityRadius = config.getGeofenceProximityRadius()
        val maxMonitored = resolveMaxMonitored()

        // Get all stored geofences from cache, filter to circular ones with valid radius
        val candidates = getCachedGeofences()
            .filter { gf ->
                val vertices = gf["vertices"]
                !(vertices is List<*> && vertices.size >= 3)
            }
            .filter { gf ->
                val radius = (gf["radius"] as? Number)?.toFloat() ?: 0f
                radius > 0f
            }
            .map { gf ->
                val lat = (gf["latitude"] as? Number)?.toDouble() ?: 0.0
                val lng = (gf["longitude"] as? Number)?.toDouble() ?: 0.0
                val distance = haversine(latitude, longitude, lat, lng)
                Pair(gf, distance)
            }
            .filter { (_, distance) -> distance <= proximityRadius }
            .sortedBy { (_, distance) -> distance }
            .take(maxMonitored)

        val newActiveIds = candidates
            .mapNotNull { (gf, _) -> gf["identifier"] as? String }
            .toSet()

        val toRemove = activeGeofenceIds - newActiveIds
        val toAdd = newActiveIds - activeGeofenceIds

        if (toRemove.isEmpty() && toAdd.isEmpty()) return

        // Unregister geofences that left the proximity zone
        for (id in toRemove) {
            unregisterGeofence(id)
        }

        // Register geofences that entered the proximity zone
        val candidateMap = candidates.associate { (gf, _) ->
            (gf["identifier"] as? String ?: "") to gf
        }
        for (id in toAdd) {
            candidateMap[id]?.let { registerGeofence(it) }
        }

        // Fire geofencesChange event (on = activated, off = deactivated)
        val on = toAdd.mapNotNull { candidateMap[it] }
        val off = toRemove.map { getGeofence(it) ?: mapOf<String, Any?>("identifier" to it) }
        if (on.isNotEmpty() || off.isNotEmpty()) {
            events.sendGeofencesChange(mapOf("on" to on, "off" to off))
        }

        // Note for triage: this emits geofencesChange on/off for *monitoring*
        // scope, not ENTER/EXIT. An `off` here means the fence left the
        // geofenceProximityRadius window and was unregistered — it is not a
        // boundary crossing and is deliberately not accuracy-gated. Apps that
        // treat geofencesChange.off as an exit will see spurious "exits" from a
        // single far-drifting fix, so make the distinction explicit in the log.
        TraceletLog.debug(
            "$GEOFENCE_LOG_TAG proximity scope update (not ENTER/EXIT): " +
                "${activeGeofenceIds.size} active, +${toAdd.size}/-${toRemove.size}, " +
                "proximityRadius=${proximityRadius}m"
        )
    }

    /**
     * Clear the *in-memory* high-accuracy evaluator state.
     *
     * Deliberately does NOT touch the persisted [knownInsideIds]: this is called
     * on every resume/boot, and the persisted set is exactly what lets
     * [evaluateHighAccuracyProximity] suppress the re-ENTER a freshly-reset
     * evaluator would otherwise produce for a stationary device (#292). Use
     * [resetHighAccuracyInsideState] for a full reset that forgets crossings.
     */
    fun clearHighAccuracyState() {
        insideGeofenceIds.clear()
        geofenceEvaluator.clear()
    }

    /**
     * Full reset of high-accuracy inside-state — the in-memory evaluator AND the
     * persisted [knownInsideIds].
     *
     * Called only on a *fresh* `startGeofences()` (not a resume/boot) and on
     * [destroy], so a genuine fresh start re-emits the initial-entry ENTER once
     * while a resume/boot preserves the persisted set (#292).
     */
    fun resetHighAccuracyInsideState() {
        knownInsideIds.clear()
        persistKnownInside()
        clearHighAccuracyState()
    }

    /** Destroy and clean up. */
    fun destroy() {
        unregisterAllGeofences()
        insideGeofenceIds.clear()
        geofenceEvaluator.clear()
        knownInsideIds.clear()
        persistKnownInside()
        invalidateGeofenceCache()
    }

    // =========================================================================
    // Private methods
    // =========================================================================

    /**
     * Builds the `coords` payload for a geofence transition event.
     *
     * The geofence boundary latitude/longitude come from the triggering event,
     * but the remaining telemetry (accuracy, speed, heading, altitude and their
     * per-field accuracies) is sourced from the most recent GPS fix when
     * available. Previously these were hardcoded to `0.0`, leaving backends
     * blind to speed/heading/accuracy at the crossing (#231).
     */
    private fun buildCoords(latitude: Double, longitude: Double): Map<String, Any?> {
        val last = lastLocationProvider?.invoke()
            ?: return mapOf(
                "latitude" to latitude,
                "longitude" to longitude,
                "accuracy" to 0.0,
                "speed" to 0.0,
                "heading" to 0.0,
                "altitude" to 0.0,
            )

        return buildMap {
            put("latitude", latitude)
            put("longitude", longitude)
            put("accuracy", last.accuracy.toDouble())
            put("speed", if (last.hasSpeed()) last.speed.toDouble() else 0.0)
            put("heading", if (last.hasBearing()) last.bearing.toDouble() else 0.0)
            put("altitude", if (last.hasAltitude()) last.altitude else 0.0)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                put("speedAccuracy", if (last.hasSpeedAccuracy()) last.speedAccuracyMetersPerSecond.toDouble() else -1.0)
                put("headingAccuracy", if (last.hasBearingAccuracy()) last.bearingAccuracyDegrees.toDouble() else -1.0)
                put("altitudeAccuracy", if (last.hasVerticalAccuracy()) last.verticalAccuracyMeters.toDouble() else -1.0)
            } else {
                put("speedAccuracy", -1.0)
                put("headingAccuracy", -1.0)
                put("altitudeAccuracy", -1.0)
            }
        }
    }

    /** Current battery snapshot for geofence transition payloads (#231). */
    private fun currentBattery(): Map<String, Any?> = BatteryUtils.getBatteryInfo(context)

    private fun registerGeofence(geofenceMap: Map<String, Any?>): Boolean {
        if (!hasPermission()) return false

        val identifier = geofenceMap["identifier"] as? String ?: return false
        val latitude = (geofenceMap["latitude"] as? Number)?.toDouble() ?: return false
        val longitude = (geofenceMap["longitude"] as? Number)?.toDouble() ?: return false
        val radius = (geofenceMap["radius"] as? Number)?.toFloat() ?: 200f

        // Guard against invalid radius (e.g. polygon geofences with radius=0)
        if (radius <= 0f) return false
        val notifyOnEntry = geofenceMap["notifyOnEntry"] != false
        val notifyOnExit = geofenceMap["notifyOnExit"] != false
        val notifyOnDwell = geofenceMap["notifyOnDwell"] == true
        val loiteringDelay = (geofenceMap["loiteringDelay"] as? Number)?.toInt() ?: 0

        var transitionTypes = 0
        if (notifyOnEntry) transitionTypes = transitionTypes or 1 // ENTER
        if (notifyOnExit) transitionTypes = transitionTypes or 2  // EXIT
        if (notifyOnDwell) transitionTypes = transitionTypes or 4 // DWELL

        val initialTrigger = if (config.getGeofenceInitialTriggerEntry()) 1 else 0

        val request = TraceletGeofencingRequest(
            geofences = listOf(
                TraceletGeofence(
                    requestId = identifier,
                    latitude = latitude,
                    longitude = longitude,
                    // Inflated for sub-serviceable fences: at their true radius
                    // Play Services fires nothing, and the registration exists
                    // to wake us near the fence, not to judge it (#355).
                    radiusMeters = wakeupRadiusMeters(radius),
                    expirationTime = -1L, // Geofence.NEVER_EXPIRE
                    transitionTypes = transitionTypes,
                    loiteringDelayMs = loiteringDelay
                )
            ),
            initialTrigger = initialTrigger
        )

        return try {
            val latch = CountDownLatch(1)
            var success = false
            // The Flutter host invokes addGeofence()/registerGeofence() on the
            // Android main thread. GeofencingClient.addGeofences() is asynchronous
            // and also delivers its success/failure callback on the main looper,
            // so we must NOT block the main thread waiting for it. Off the main
            // thread we await the callback and return its real result; on the main
            // thread we return true once the request has been scheduled without
            // throwing synchronously — the geofence is already persisted and
            // registration is in flight. Returning the initial `success` on the
            // main thread reported a stale false for a geofence that was actually
            // created and shows up in getGeofences() (#265).
            val isMainThread = Looper.myLooper() == Looper.getMainLooper()
            geofencingClient.addGeofences(
                request = request,
                pendingIntent = getGeofencePendingIntent(),
                onSuccess = {
                    activeGeofenceIds.add(identifier)
                    success = true
                    latch.countDown()
                    TraceletLog.debug("Geofence registered: $identifier")
                },
                onFailure = { e ->
                    latch.countDown()
                    TraceletLog.error("Failed to register geofence $identifier: ${e.message}")
                }
            )
            if (!isMainThread) {
                latch.await(REGISTRATION_TIMEOUT_MS, TimeUnit.MILLISECONDS)
            }
            isMainThread || success
        } catch (e: SecurityException) {
            TraceletLog.error("Permission denied for geofencing: ${e.message}")
            false
        }
    }

    private fun unregisterGeofence(identifier: String): Boolean {
        val latch = CountDownLatch(1)
        geofencingClient.removeGeofences(
            requestIds = listOf(identifier),
            onSuccess = {
                activeGeofenceIds.remove(identifier)
                latch.countDown()
                TraceletLog.debug("Geofence removed: $identifier")
            },
            onFailure = { e ->
                latch.countDown()
                TraceletLog.warning("Failed to remove geofence $identifier: ${e.message}")
            }
        )
        if (Looper.myLooper() != Looper.getMainLooper()) {
            latch.await(REGISTRATION_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        }
        return true
    }

    private fun unregisterAllGeofences(): Boolean {
        geofencePendingIntent?.let {
            geofencingClient.removeGeofences(
                pendingIntent = it,
                onSuccess = {
                    activeGeofenceIds.clear()
                    TraceletLog.debug("All geofences removed")
                },
                onFailure = { e ->
                    TraceletLog.warning("Failed to remove all geofences: ${e.message}")
                }
            )
        }
        return true
    }

    private fun getGeofencePendingIntent(): PendingIntent {
        if (geofencePendingIntent != null) return geofencePendingIntent!!

        val intent = Intent(context, GeofenceBroadcastReceiver::class.java).apply {
            action = ACTION_GEOFENCE_EVENT
        }
        geofencePendingIntent = PendingIntent.getBroadcast(
            context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )
        return geofencePendingIntent!!
    }

    private fun hasPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
    }

    /**
     * Resolve the effective maximum number of simultaneously monitored geofences.
     * Uses [ConfigManager.getMaxMonitoredGeofences] if set (> 0), otherwise
     * falls back to the platform maximum (100 for Android).
     */
    private fun resolveMaxMonitored(): Int {
        val configured = config.getMaxMonitoredGeofences()
        return if (configured > 0) minOf(configured, PLATFORM_MAX_GEOFENCES)
        else PLATFORM_MAX_GEOFENCES
    }

    /**
     * Haversine formula — distance in meters between two lat/lng points.
     */
    private fun haversine(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val r = 6_371_000.0 // Earth radius in meters
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
                Math.sin(dLon / 2) * Math.sin(dLon / 2)
        val c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
        return r * c
    }

    private fun mapToCoreGeofence(gf: Map<String, Any?>): CoreGeofence {
        val identifier = gf["identifier"] as? String ?: ""
        val latitude = (gf["latitude"] as? Number)?.toDouble() ?: 0.0
        val longitude = (gf["longitude"] as? Number)?.toDouble() ?: 0.0
        val radius = (gf["radius"] as? Number)?.toDouble() ?: 0.0
        val verticesRaw = gf["vertices"]
        val vertices = mutableListOf<Coordinate>()
        if (verticesRaw is List<*>) {
            for (v in verticesRaw) {
                if (v is List<*> && v.size >= 2) {
                    val lat = (v[0] as? Number)?.toDouble()
                    val lng = (v[1] as? Number)?.toDouble()
                    if (lat != null && lng != null) {
                        vertices.add(Coordinate(lat, lng))
                    }
                }
            }
        }
        val extrasRaw = gf["extras"] as? Map<*, *>
        var extrasStr: String? = null
        if (extrasRaw != null) {
            try {
                extrasStr = org.json.JSONObject(extrasRaw).toString()
            } catch (e: Exception) {
                TraceletLog.warning("Failed to stringify geofence extras: ${e.message}")
            }
        }
        return CoreGeofence(
            identifier, latitude, longitude, radius, vertices, extrasStr,
            // Same defaulting as the registration and persistence paths (#355).
            notifyOnEntry = gf["notifyOnEntry"] != false,
            notifyOnExit = gf["notifyOnExit"] != false,
            notifyOnDwell = gf["notifyOnDwell"] == true,
            loiteringDelay = (gf["loiteringDelay"] as? Number)?.toInt() ?: 0,
        )
    }
}
