package com.ikolvi.tracelet.sdk.location
import com.ikolvi.tracelet.sdk.util.TraceletLog

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.core.location.LocationManagerCompat
import com.ikolvi.tracelet.sdk.wrapper.*
import com.ikolvi.tracelet.sdk.wrapper.TraceletCancellationTokenSource
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.TraceletEventSender
import com.ikolvi.tracelet.sdk.StateManager
import com.ikolvi.tracelet.sdk.audit.AuditTrailManager
import com.ikolvi.tracelet.sdk.privacy.PrivacyZoneManager

import com.ikolvi.tracelet.sdk.util.BatteryUtils
import kotlin.math.roundToInt
import uniffi.tracelet_core.LocationProcessor as RustLocationProcessor
import uniffi.tracelet_core.KalmanLocationFilter as RustKalmanFilter
import uniffi.tracelet_core.LocationProcessorResult
import uniffi.tracelet_core.AdaptiveContext
import uniffi.tracelet_core.ActivityType as RustActivityType
import uniffi.tracelet_core.ActivityConfidence as RustActivityConfidence
import uniffi.tracelet_core.LocationTuning
import uniffi.tracelet_core.TransportMode as RustTransportMode
import android.os.SystemClock
import android.os.Handler
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * Core location tracking engine wrapping TraceletLocationClient.
 *
 * Handles:
 * - Continuous location tracking (start/stop)
 * - One-shot getCurrentPosition
 * - watchPosition (multiple concurrent watchers)
 * - Odometer calculation
 * - Location result enrichment (UUID, battery, activity, odometer)
 * - Persist to SQLite and dispatch to EventChannels
 */
interface LocationDataSink {
    fun insertLocation(location: Map<String, Any?>)
}

class LocationEngine(
    val context: Context,
    private val config: ConfigManager,
    private val state: StateManager,
    var events: TraceletEventSender,
) {
    companion object {
        private const val TAG = "LocationEngine"

        /** Cached ISO 8601 formatter — thread-confined to the main/location thread. */
        private val isoFormatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }

        /** Maximum accuracy (meters) to consider a fused fix as GPS-sourced. */
        const val GPS_ACCURACY_THRESHOLD = 50f

        /**
         * Oldest a fix may be and still be allowed to drive the pace machine.
         *
         * Ten seconds: comfortably longer than any live fix interval, and far
         * shorter than the gap across which a cached fix survives a stationary
         * period. A reading older than this describes a moment that has passed.
         */
        private const val MAX_PACE_FIX_AGE_MS = 10_000L

        /**
         * How long a tracking session may accept nothing before the SDK says so
         * on the lifecycle channel (#397).
         *
         * Twice the processor's idle escape, so a stall this long means
         * something the escape cannot fix — every fix failing the accuracy gate,
         * a permission downgrade, a provider delivering nothing usable.
         */
        private const val STALL_ANNOUNCE_MS = 120_000L

        /**
         * How long a *continuous* stream may deliver nothing at all before the
         * SDK says so on the lifecycle channel (#407).
         *
         * Shorter than [STALL_ANNOUNCE_MS], because silence is a harder
         * failure than rejection: rejection means the pipeline is alive and
         * mis-tuned, silence means the OS has stopped talking to the app, which
         * no threshold change can recover.
         */
        private const val SILENCE_ANNOUNCE_MS = 45_000L

        /** How often the silence watchdog checks. Cheap; it only reads a clock. */
        private const val SILENCE_POLL_MS = 15_000L

        /**
         * Determines if a location fix is GPS-sourced (not network/cell).
         * FusedLocationProvider uses "fused" as provider, so we also check
         * accuracy as a heuristic: GPS fixes typically have accuracy ≤ 50m.
         */
        fun isGpsFix(location: Location): Boolean {
            return location.provider == "gps" ||
                (location.provider == "fused" && location.accuracy <= GPS_ACCURACY_THRESHOLD)
        }

        /**
         * Checks whether the hardware GPS provider is enabled on the device.
         * Returns false when the user has toggled GPS off in system settings.
         */
        fun isGpsProviderEnabled(context: Context): Boolean {
            val lm = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            return lm?.isProviderEnabled(LocationManager.GPS_PROVIDER) ?: false
        }
    }

    private val fusedClient: TraceletLocationClient =
        TraceletServices.getProvider(context).getLocationClient(context)

    private var trackingCallback: TraceletLocationCallback? = null

    /** Cancellation source for the in-flight stationary→moving one-shot fix.
     *  Cancelled on `stop()` and superseded on each new transition so that
     *  late callbacks from a prior request can’t leak past a stop. */
    private var immediateFixCts: TraceletCancellationTokenSource? = null
    private var lastLocation: Location? = null
    /** Last GPS-quality location (accuracy ≤ 100m).
     *  Used by heartbeat to avoid returning low-accuracy significant-change fixes. */
    private var lastGpsLocation: Location? = null
    private var currentActivityType: String = "unknown"
    private var currentActivityConfidence: Int = -1

    /**
     * Latest fused transport mode (e.g. "driving", "walking") from the transport
     * classifier, kept fresh by the SDK. When `fusedClassifierAuthoritative` is
     * enabled it becomes the persisted `activity.type`, so the classified mode
     * survives process termination and syncs historically (#214 part 3).
     */
    @Volatile
    var fusedTransportMode: String? = null

    /** Confidence (0.0–1.0) of [fusedTransportMode], kept fresh alongside it. */
    @Volatile
    var fusedTransportModeConfidence: Double = 0.0

    /**
     * The activity type to persist/dispatch: the fused transport mode when the
     * classifier is authoritative (and available), otherwise the raw AR activity.
     * Always expressed in the Activity Recognition vocabulary so `activity.type`
     * stays a single vocabulary for consumers regardless of the source.
     */
    private fun effectiveActivityType(): String {
        val fused = fusedTransportMode
        return if (config.getFusedClassifierAuthoritative() && fused != null) {
            arActivityName(fused)
        } else {
            currentActivityType
        }
    }

    /**
     * Maps the transport classifier's mode names to the Activity Recognition
     * vocabulary persisted in `activity.type` ("cycling" → "on_bicycle",
     * "vehicle" → "in_vehicle"); the remaining modes (still/walking/running/
     * unknown) are already identical in both.
     */
    private fun arActivityName(fusedMode: String): String = when (fusedMode) {
        "cycling" -> "on_bicycle"
        "vehicle" -> "in_vehicle"
        else -> fusedMode
    }

    /**
     * The activity confidence to persist/dispatch (0–100), matching
     * [effectiveActivityType]: the fused mode confidence (scaled from 0.0–1.0)
     * when authoritative and available, otherwise the platform AR confidence.
     */
    private fun effectiveActivityConfidence(): Int =
        if (config.getFusedClassifierAuthoritative() && fusedTransportMode != null) {
            (fusedTransportModeConfidence * 100).roundToInt()
        } else {
            currentActivityConfidence
        }

    /** Force accept the next location (even if distance is 0) to guarantee a motion change sync on wakeup. */
    var forcePersistNextFilteredLocation = false

    /** Native data sinks for DB persistence and auto HTTP sync. */
    private val sinks: MutableList<LocationDataSink> = mutableListOf()

    fun registerSink(sink: LocationDataSink) {
        // Dedupe: the same sink can otherwise be registered more than once across
        // init / ready / reconfigure cycles, which would fan a single persisted
        // location out to multiple sync triggers (Issue #204).
        if (!sinks.contains(sink)) sinks.add(sink)
    }

    /** Removes a previously-registered sink (used when a sync provider is replaced). */
    fun unregisterSink(sink: LocationDataSink) {
        sinks.remove(sink)
    }

    /**
     * Merges call-specific [extras] into the location map's existing extras
     * (the global HTTP extras set by [enrichLocation]) instead of replacing them,
     * so both global config extras and the per-call extras passed to
     * getCurrentPosition / getLastKnownLocation survive into the synced payload
     * (Issue #201).
     */
    private fun mergeExtras(target: MutableMap<String, Any?>, extras: Map<String, Any?>) {
        if (extras.isEmpty()) return
        @Suppress("UNCHECKED_CAST")
        val merged = (target["extras"] as? Map<String, Any?>)?.toMutableMap() ?: mutableMapOf()
        merged.putAll(extras)
        target["extras"] = merged
    }

    // =========================================================================
    // Rust-powered location processing (LocationProcessor + Kalman)
    // =========================================================================

    /** Rust-backed location processor for distance/accuracy/speed/mock filtering.
     *  Lazily created from config on first use, recreated on config changes. */
    private var locationProcessor: RustLocationProcessor? = null

    /** Rust-backed Kalman filter for smoothing lat/lng. */
    private var kalmanFilter: RustKalmanFilter? = null

    /** Build (or rebuild) the Rust LocationProcessor from current config. */
    fun rebuildProcessor() {
        locationProcessor?.destroy()
        locationProcessor = RustLocationProcessor(
            distanceFilter = config.getDistanceFilter(),
            disableElasticity = config.getDisableElasticity(),
            elasticityMultiplier = config.getElasticityMultiplier(),
            enableAdaptiveMode = config.getEnableAdaptiveMode(),
            trackingAccuracyThreshold = config.getTrackingAccuracyThreshold(),
            filterPolicy = config.getFilterPolicy(),
            maxImpliedSpeed = config.getMaxImpliedSpeed(),
            odometerAccuracyThreshold = config.getOdometerAccuracyThreshold(),
            rejectMockLocations = config.getRejectMockLocations(),
            mockDetectionLevel = config.getMockDetectionLevel(),
            enableSparseUpdates = config.getEnableSparseUpdates(),
            sparseDistanceThreshold = config.getSparseDistanceThreshold(),
            sparseMaxIdleSeconds = config.getSparseMaxIdleSeconds(),
        )
        kalmanFilter?.destroy()
        kalmanFilter = if (config.getEnableKalmanFilter()) RustKalmanFilter() else null
        // A rebuild must not drop a throttle that is still in force, or the gate
        // would tighten back under fixes the ladder is deliberately coarsening
        // (#396).
        if (budgetTrackingAccuracyFloor > 0) {
            locationProcessor?.setAccuracyFloor(budgetTrackingAccuracyFloor)
        }
    }

    /** Returns the processor, building it if needed. */
    private fun getProcessor(): RustLocationProcessor {
        return locationProcessor ?: run {
            rebuildProcessor()
            locationProcessor!!
        }
    }

    /**
     * Applies the filter thresholds appropriate to a committed transport mode (#299).
     *
     * Called only when the classifier *commits* a mode change — already gated by
     * confidence and an 8 s dwell — never per accelerometer window, so the
     * thresholds cannot chatter. A mode with no tuning (`unknown`) restores the
     * host's own configuration rather than guessing.
     *
     * Returns the applied tuning, or `null` when auto-tuning is disabled or the
     * mode carries no opinion. Callers surface it on the `modeChange` event so an
     * auto-tune shows up in logs instead of being a silent config mutation.
     */
    fun applyTransportModeTuning(mode: String): LocationTuning? {
        if (!config.getAutoTuneFromTransportMode()) {
            // #301: auto-tuning may have been switched off *after* a mode
            // committed. Undo any tuning still in force rather than leaving the
            // host running on thresholds it no longer asked for.
            restoreBaseTuning()
            return null
        }
        val processor = getProcessor()
        val tuning = uniffi.tracelet_core.tuningForTransportMode(rustTransportMode(mode))
        if (tuning == null) {
            processor.restoreBaseTuning()
            TraceletLog.debug("auto-tune: '$mode' has no tuning — restored configured thresholds")
            return null
        }
        processor.retune(tuning)
        TraceletLog.debug(
            "auto-tune: '$mode' → distanceFilter=${tuning.distanceFilter}m " +
                "trackingAccuracy=${tuning.trackingAccuracyThreshold}m " +
                "odometerAccuracy=${tuning.odometerAccuracyThreshold}m " +
                "maxImpliedSpeed=${tuning.maxImpliedSpeed}m/s",
        )
        return tuning
    }

    /**
     * Restores the thresholds this engine was configured with, undoing any
     * auto-tune (#301).
     *
     * No-op when no processor exists yet — unlike [getProcessor] this must not
     * build one as a side effect, since it is called from reconfiguration paths
     * that run before tracking has ever started.
     */
    fun restoreBaseTuning() {
        locationProcessor?.restoreBaseTuning()
    }

    /**
     * Pushes the four configured filter thresholds into the processor as its new
     * *base* tuning (#303).
     *
     * `setConfig` only rebuilt the processor for a short list of location keys,
     * so `trackingAccuracyThreshold`, `odometerAccuracyThreshold` and
     * `maxImpliedSpeed` never reached it — they sat in [ConfigManager] until the
     * next cold start, and [restoreBaseTuning] reverted to the values captured
     * when the processor was constructed rather than the ones the host had since
     * configured.
     *
     * Deliberately not a [rebuildProcessor] call: a rebuild drops the positional
     * anchor and forfeits one inter-fix delta from the odometer, which is exactly
     * what `retune` was introduced to avoid (#299). `setBaseTuning` preserves it,
     * and defers to an auto-tune that is currently in force while still updating
     * what a later restore lands on.
     *
     * No-op before a processor exists; the next [rebuildProcessor] reads the same
     * values straight from config.
     */
    fun applyConfiguredBaseTuning() {
        val processor = locationProcessor ?: return
        processor.setBaseTuning(
            LocationTuning(
                distanceFilter = config.getDistanceFilter(),
                trackingAccuracyThreshold = config.getTrackingAccuracyThreshold(),
                odometerAccuracyThreshold = config.getOdometerAccuracyThreshold(),
                maxImpliedSpeed = config.getMaxImpliedSpeed(),
            ),
        )
    }

    /**
     * The thresholds actually in force right now, or `null` before a processor
     * exists (#303).
     *
     * Reads back from the processor, never from config: the two disagreeing is
     * precisely the bug #303 fixed, so answering from config would make a
     * regression undetectable.
     */
    fun currentTuning(): LocationTuning? = locationProcessor?.currentTuning()

    /**
     * The thresholds actually in force right now, formatted for a log line
     * (#303).
     *
     * Reads back from the processor rather than from config, so the line reports
     * what the filter is really using — including an auto-tune the host did not
     * set. Returns `"no processor"` before one exists, which is itself the useful
     * answer on a pre-`start()` reconfiguration.
     */
    fun currentTuningDescription(): String {
        val t = locationProcessor?.currentTuning() ?: return "no processor"
        return "distanceFilter=${t.distanceFilter}m " +
            "trackingAccuracy=${t.trackingAccuracyThreshold}m " +
            "odometerAccuracy=${t.odometerAccuracyThreshold}m " +
            "maxImpliedSpeed=${t.maxImpliedSpeed}m/s"
    }

    /**
     * Brings the Kalman filter in line with `useKalmanFilter` (#303).
     *
     * The filter is otherwise only constructed inside [rebuildProcessor], and the
     * key is not one that triggers a rebuild — so toggling smoothing at runtime
     * did nothing until the app was restarted. That matters more since #299 made
     * Kalman smoothing feed the odometer: enabling it mid-session silently failed
     * to change recorded distance.
     *
     * Toggling rebuilds only the filter, never the processor, so the odometer
     * anchor survives. An already-correct state is left alone so the filter's own
     * velocity estimate is not reset on unrelated `setConfig` calls.
     */
    fun syncKalmanFilter() {
        val wanted = config.getEnableKalmanFilter()
        if (wanted && kalmanFilter == null) {
            kalmanFilter = RustKalmanFilter()
        } else if (!wanted && kalmanFilter != null) {
            kalmanFilter?.destroy()
            kalmanFilter = null
        }
    }

    /** Maps a classifier mode name back to the Rust [RustTransportMode] enum. */
    private fun rustTransportMode(mode: String): RustTransportMode = when (mode.lowercase()) {
        "still" -> RustTransportMode.STILL
        "walking" -> RustTransportMode.WALKING
        "running" -> RustTransportMode.RUNNING
        "cycling" -> RustTransportMode.CYCLING
        "vehicle" -> RustTransportMode.VEHICLE
        else -> RustTransportMode.UNKNOWN
    }

    /** Last computed effective speed (m/s) from tracking location updates.
     *  Used by the plugin for motionchange events since the cached Location.speed
     *  may be stale or 0. */
    var lastEffectiveSpeed: Double = 0.0
        private set

    /**
     * Optional callback invoked on every accepted location (for geofenceModeHighAccuracy).
     *
     * Params: latitude, longitude, horizontalAccuracy (meters). Accuracy feeds
     * the drift-aware geofence EXIT decision (issue #274); pass 0.0 when unknown.
     */
    var onLocationUpdate: ((Double, Double, Double) -> Unit)? = null

    /**
     * Optional callback invoked on every **raw** fix — before the Rust
     * [LocationProcessor] distance/accuracy/sparse filter — for
     * geofenceModeHighAccuracy crossing evaluation.
     *
     * The tracking distance filter exists to reduce *persistence* volume: a
     * stationary device's repeated fixes are dropped so the DB and sync queue
     * don't fill with duplicate points. But geofence crossing detection needs
     * to see *every* fix — a device drifting a few metres across a boundary, or
     * one whose EXIT must be confirmed across two consecutive out-of-fence
     * fixes (#294), is starved if the crossing evaluation only runs on the
     * fixes that survive the persistence filter. On a stable provider (GMS
     * Fused, since 3.7.3) a stationary device emits no accepted fixes at all,
     * so [onLocationUpdate] never fires and transitions are missed.
     *
     * This callback decouples the two: crossings are evaluated on the raw
     * stream while persistence keeps its distance filter. Params: latitude,
     * longitude, horizontalAccuracy (meters); pass 0.0 when accuracy unknown.
     */
    var onRawGeofenceLocation: ((Double, Double, Double) -> Unit)? = null

    /**
     * When true, the fused provider is requested with a **time-based** cadence
     * (minUpdateDistanceMeters = 0) so a stationary/backgrounded device is still
     * delivered fixes for [onRawGeofenceLocation] to evaluate. The persistence
     * distance filter (the Rust [LocationProcessor]) is unchanged, so this does
     * not increase stored/synced location volume. Set by the plugin around
     * startGeofences() from `hasEvaluatorOwnedGeofences()` — high-accuracy mode,
     * a polygon, or a sub-100 m circle — not from `geofenceModeHighAccuracy`
     * alone, and re-applied whenever the fence set changes (#357).
     */
    var geofenceHighAccuracyMode: Boolean = false
        set(value) {
            val changed = field != value
            field = value
            // Applied live: the fence set is mutable while tracking, so a fence
            // added mid-session must drop the distance gate immediately rather
            // than at the next start() — which, in continuous mode, never
            // comes (#357).
            if (changed) reapplyProviderOptionsIfTracking()
        }

    /** Optional callback invoked after a location is persisted to the database.
     *  Used by the plugin to trigger HTTP auto-sync. */
    var onLocationPersisted: (() -> Unit)? = null

    /** Optional audit trail manager (Enterprise). Set by the plugin after construction. */
    var auditTrailManager: AuditTrailManager? = null

    /** Optional privacy zone manager (Enterprise). Set by the plugin after construction. */
    var privacyZoneManager: PrivacyZoneManager? = null

    /** Optional callback invoked to feed effective speed to SpeedMotionManager. */
    var speedMotionSpeedSink: ((Double) -> Unit)? = null

    /**
     * Optional sink for the speed of every **raw** fix, before the processor's
     * distance/accuracy/speed filters (#299).
     *
     * The transport classifier consumes this rather than the speed of accepted
     * fixes. When auto-tuning is on, the classified mode selects the distance
     * filter — so classifying from post-filter speeds would close a loop where
     * tightening the filter changes the very speeds that chose it.
     */
    var rawSpeedSink: ((Double) -> Unit)? = null

    // watchPosition watchers: watchId -> LocationCallback
    private val watchers = ConcurrentHashMap<Int, TraceletLocationCallback>()
    private var nextWatchId = 1

    /** Whether a mock location warning has already been fired for this session. */
    private var mockLocationWarningFired = false

    /**
     * Whether continuous tracking priority was auto-downgraded because the
     * GPS hardware provider is disabled (user toggled GPS off).
     *
     * When true, the engine is using [TraceletLocationPriority.PRIORITY_BALANCED_POWER_ACCURACY]
     * to obtain Wi-Fi / cell tower fixes instead of the configured priority.
     * Once GPS is re-enabled, the engine restores the original priority and
     * re-subscribes to location updates.
     */
    private var gpsFallbackActive = false

    /**
     * Temporary OS-provider overrides. These intentionally do not mutate
     * ConfigManager or the Rust accepted-point filter. They only control how
     * the fused provider acquires and delivers fixes while continuous tracking
     * is active, and are cleared by stop(). Mirrors the iOS
     * LocationEngine.runtimeDesiredAccuracy/runtimeDistanceFilter overrides.
     */
    private var runtimeDesiredAccuracy: Int? = null
    private var runtimeDistanceFilter: Double? = null

    /**
     * The battery-budget ladder's overlay, if one is in force (#393, #396).
     *
     * Separate from the runtime overrides above, and deliberately not a write
     * into ConfigManager: the budget engine used to call `setConfig`, which made
     * its throttled values indistinguishable from the app's own — permanently,
     * since a configured `distanceFilter: 0` was clamped to 10 and nothing ever
     * restored it. An explicit `updateLocationProviderOptions` still wins.
     */
    private var budgetDesiredAccuracy: Int? = null
    private var budgetDistanceFilter: Double? = null
    private var budgetCadenceMultiplier: Double = 1.0
    private var budgetTrackingAccuracyFloor: Int = 0

    /** Whether continuous tracking is active. */
    val isTracking: Boolean get() = trackingCallback != null

    // =========================================================================
    // Stall watchdog (#397)
    // =========================================================================

    /**
     * Consecutive fixes whose speed was too old to drive the pace machine.
     *
     * Bounds the always-on logging to one line per run rather than one per fix.
     */
    private var staleFixesSincePace = 0

    /** When the processor last accepted a fix; null before the first one. */
    private var lastAcceptedFixAt: Long? = null

    /** Rejections since the last accepted fix, by reason. */
    private val rejectionsSinceAccept = mutableMapOf<String, Int>()

    /** Whether the current stall has already been announced. */
    private var stallAnnounced = false

    /**
     * Records the outcome of one filter decision and announces a stalled or
     * recovered stream on the always-on lifecycle channel.
     *
     * A stream that accepts nothing for minutes is indistinguishable from a
     * parked device in the logs, and both look like "tracking is running". That
     * ambiguity is what made the field reports for #393/#394 take two exports
     * and a source read to resolve — so the SDK now states it, at a level that
     * survives a released app's default `logLevel` (#318, #397).
     */
    private fun noteFilterDecision(result: LocationProcessorResult, accepted: Boolean) {
        val now = System.currentTimeMillis()
        if (accepted) {
            val since = lastAcceptedFixAt
            if (stallAnnounced && since != null) {
                TraceletLog.lifecycle(
                    "location stream recovered after ${(now - since) / 1000}s — " +
                        "${rejectionsSinceAccept.values.sum()} fix(es) rejected meanwhile " +
                        "[${rejectionHistogram()}]" +
                        if (result.idleEscape) ", admitted by the idle escape (#394)" else "",
                )
            }
            if (result.idleEscape && !stallAnnounced) {
                TraceletLog.lifecycle(
                    "adaptive sampling held a fix for ${"%.0f".format(result.anchorAgeSeconds)}s " +
                        "behind a ${"%.0f".format(result.effectiveDistanceFilter)}m gate — " +
                        "admitted it at the configured filter instead (#394)",
                )
            }
            if (result.anchorReseeded) {
                TraceletLog.lifecycle(
                    "anchor re-seeded after a ${"%.0f".format(result.anchorAgeSeconds)}s gap with " +
                        "no observations — position taken, " +
                        "${"%.0f".format(result.distance)}m span not counted as travel (#395)",
                )
            }
            lastAcceptedFixAt = now
            rejectionsSinceAccept.clear()
            stallAnnounced = false
            return
        }

        val reason = result.reason ?: "unknown"
        rejectionsSinceAccept[reason] = (rejectionsSinceAccept[reason] ?: 0) + 1

        val since = lastAcceptedFixAt
        if (since == null) {
            lastAcceptedFixAt = now
            return
        }
        val stalledForMs = now - since
        if (stallAnnounced || stalledForMs < STALL_ANNOUNCE_MS) return
        stallAnnounced = true

        TraceletLog.lifecycle(
            "location stream stalled — nothing accepted for ${stalledForMs / 1000}s, " +
                "${rejectionsSinceAccept.values.sum()} fix(es) rejected [${rejectionHistogram()}]; " +
                "last gate=${"%.1f".format(result.effectiveDistanceFilter)}m " +
                "(configured ${config.getDistanceFilter()}m), " +
                "last fix acc=${"%.1f".format(result.accuracy)}m, " +
                "in force: ${currentTuningDescription()}",
        )
    }

    private fun rejectionHistogram(): String =
        rejectionsSinceAccept.entries.sortedBy { it.key }.joinToString(" ") { "${it.key}=${it.value}" }

    private fun resetStallWatchdog(seed: Boolean) {
        lastAcceptedFixAt = if (seed) System.currentTimeMillis() else null
        rejectionsSinceAccept.clear()
        stallAnnounced = false
        if (seed) armSilenceWatchdog() else cancelSilenceWatchdog()
    }

    // =========================================================================
    // Silence watchdog (#407)
    // =========================================================================

    /**
     * When the last location callback arrived, or `null` if none has since the
     * stream started.
     *
     * Deliberately separate from [lastAcceptedFixAt]: that one tracks the
     * *filter*, this one tracks the *provider*. A stream that is delivering
     * fixes the filter rejects and a stream that is delivering nothing are
     * different faults with different fixes, and until #407 both were reported
     * as neither.
     *
     * On [android.os.SystemClock.elapsedRealtime], not the wall clock. This is
     * an interval measurement, and a wall clock that an NTP sync or a manual
     * change steps forward would announce a silence that never happened —
     * stepped backwards, it would hide a real one indefinitely.
     */
    private var lastCallbackAt: Long? = null

    private val silenceHandler = Handler(Looper.getMainLooper())
    private var silenceRunnable: Runnable? = null
    private var silenceAnnounced = false

    /**
     * Starts the timer that announces a stream delivering nothing at all.
     *
     * [noteFilterDecision] cannot do this: it only runs when a fix arrives, so
     * total silence — the case where the SDK is most blind — never reached it.
     * That is how a 52-second dead window came back from the field reported as
     * "the stream has been accepting fixes" (#405/#407).
     */
    private fun armSilenceWatchdog() {
        cancelSilenceWatchdog()
        silenceAnnounced = false
        lastCallbackAt = null
        val started = android.os.SystemClock.elapsedRealtime()
        val runnable = object : Runnable {
            override fun run() {
                // Periodic mode's silence between ticks is the design, not a
                // fault, so only a stream that is supposed to be continuous is
                // worth announcing.
                if (trackingCallback == null) return
                val last = lastCallbackAt
                val silentSinceMs = android.os.SystemClock.elapsedRealtime() - (last ?: started)
                if (silentSinceMs >= SILENCE_ANNOUNCE_MS && !silenceAnnounced) {
                    silenceAnnounced = true
                    TraceletLog.lifecycle(
                        "location stream silent — no fix delivered for " +
                            "${silentSinceMs / 1000}s" +
                            (if (last == null) " since the stream started" else "") +
                            ", requested accuracy=${effectiveDesiredAccuracy()} " +
                            "interval=${effectiveUpdateInterval()}ms " +
                            "distanceFilter=${effectiveDistanceFilter()}m. " +
                            "The provider is delivering nothing — this is not the filter " +
                            "rejecting fixes (#407).",
                    )
                }
                silenceHandler.postDelayed(this, SILENCE_POLL_MS)
            }
        }
        silenceRunnable = runnable
        silenceHandler.postDelayed(runnable, SILENCE_POLL_MS)
    }

    private fun cancelSilenceWatchdog() {
        silenceRunnable?.let { silenceHandler.removeCallbacks(it) }
        silenceRunnable = null
        silenceAnnounced = false
        lastCallbackAt = null
    }

    /**
     * Records that the provider delivered something, whatever the filter later
     * decides about it, and announces recovery from an earlier silence.
     */
    private fun noteCallbackDelivered() {
        val wasSilent = silenceAnnounced
        val since = lastCallbackAt
        val now = android.os.SystemClock.elapsedRealtime()
        lastCallbackAt = now
        silenceAnnounced = false
        if (wasSilent) {
            TraceletLog.lifecycle(
                "location stream resumed after ${(now - (since ?: now)) / 1000}s " +
                    "of silence (#407)",
            )
        }
    }

    /**
     * Installs the battery-budget ladder's overlay, or clears it when the ladder
     * returns to level 0 (#396).
     *
     * The accuracy floor is the only piece that reaches the Rust processor, and
     * it only ever *loosens* the tracking gate: a ladder that has asked the
     * fused provider for balanced-power fixes must not leave a 15 m gate in
     * place to reject them.
     */
    fun applyBudgetOverlay(
        distanceFilter: Double?,
        desiredAccuracy: Int?,
        cadenceMultiplier: Double,
        trackingAccuracyFloor: Int,
    ) {
        budgetDistanceFilter = distanceFilter
        budgetDesiredAccuracy = desiredAccuracy
        budgetCadenceMultiplier = if (cadenceMultiplier > 0) cadenceMultiplier else 1.0
        budgetTrackingAccuracyFloor = maxOf(0, trackingAccuracyFloor)
        locationProcessor?.setAccuracyFloor(budgetTrackingAccuracyFloor)
        // The fused provider takes a new request in place; no restart, so no gap
        // in the stream and no lost anchor.
        reapplyProviderOptionsIfTracking()
    }

    // =========================================================================
    // Dead Reckoning
    // =========================================================================

    private var deadReckoningEngine: DeadReckoningEngine? = null
    private val drHandler = Handler(Looper.getMainLooper())
    private var gpsLossRunnable: Runnable? = null

    /**
     * Starts continuous location tracking based on current config.
     *
     * If the GPS provider is disabled (user toggled GPS off in system
     * settings), the engine automatically downgrades to
     * [TraceletLocationPriority.PRIORITY_BALANCED_POWER_ACCURACY] so that
     * Wi-Fi / cell-tower fixes are delivered instead of nothing.
     * When GPS is re-enabled, [restoreOriginalPriority] re-subscribes
     * with the configured accuracy.
     */
    fun start() {
        if (!hasPermission()) {
            TraceletLog.warning("start() — no location permission granted, dispatching providerChange(status=0)")
            events.sendProviderChange(buildProviderState())
            return
        }
        stop() // Ensure clean state

        // The stall clock starts now, not at the first accepted fix: a session
        // that never accepts one at all is exactly the case worth announcing
        // (#397).
        resetStallWatchdog(seed = true)

        // Always-on: this is the transition the OS location indicator follows,
        // so "the icon disappeared" is answerable from a released app's report.
        TraceletLog.lifecycle(
            "location stream: continuous updates starting — " +
                "accuracy=${effectiveDesiredAccuracy()} " +
                "distanceFilter=${effectiveDistanceFilter()}m " +
                "interval=${effectiveUpdateInterval()}ms",
        )

        val request = buildLocationRequestWithGpsFallback()

        trackingCallback = object : TraceletLocationCallback {
            override fun onLocationResult(locations: List<Location>) {
                // #407: before the filter gets a say. What the provider
                // delivered and what the filter kept are separate questions,
                // and the watchdogs that answer them must not share a clock.
                noteCallbackDelivered()
                for (location in locations) {
                    onLocationReceived(location, "location")
                }
            }

            override fun onLocationAvailability(isLocationAvailable: Boolean) {
                val providerState = buildProviderState()
                val gpsNowEnabled = providerState["gps"] as? Boolean ?: false

                if (gpsFallbackActive && gpsNowEnabled) {
                    // GPS was re-enabled — restore original priority.
                    TraceletLog.debug("GPS re-enabled — restoring original priority")
                    restoreOriginalPriority()
                } else if (!gpsFallbackActive && !gpsNowEnabled && isHighAccuracyConfigured()) {
                    // GPS just disabled while we were expecting it — downgrade.
                    TraceletLog.debug("GPS disabled during tracking — downgrading to Wi-Fi/cell")
                    activateGpsFallback()
                }

                if (!isLocationAvailable) {
                    events.sendProviderChange(providerState)
                }
            }
        }

        try {
            fusedClient.requestLocationUpdates(request, trackingCallback!!, Looper.getMainLooper())
            startGpsLossTimer()
        } catch (e: SecurityException) {
            trackingCallback = null
        }
    }

    /** Stops continuous location tracking. */
    fun stop() {
        gpsFallbackActive = false
        runtimeDesiredAccuracy = null
        runtimeDistanceFilter = null
        // The budget overlay deliberately survives: a session that stops and
        // starts again has not changed how fast the device is draining (#396).
        resetStallWatchdog(seed = false)
        staleFixesSincePace = 0
        if (trackingCallback != null) {
            TraceletLog.lifecycle("location stream: continuous updates stopping")
        }
        trackingCallback?.let {
            fusedClient.removeLocationUpdates(it)
            trackingCallback = null
        }
        // Cancel any in-flight stationary→moving one-shot so its success
        // callback won’t fire after stop().
        immediateFixCts?.cancel()
        immediateFixCts = null
        stopPeriodic()
        deactivateDeadReckoning()
        cancelGpsLossTimer()
    }

    // =========================================================================
    // Periodic one-shot tracking (foreground service + timer strategy)
    // =========================================================================

    private var periodicRunnable: Runnable? = null
    private val periodicHandler = android.os.Handler(Looper.getMainLooper())

    /** Whether periodic one-shot tracking is active. */
    val isPeriodicTracking: Boolean get() = periodicRunnable != null

    /**
     * Starts periodic one-shot location tracking using a Handler timer.
     *
     * This is the foreground-service strategy: the service stays alive with a
     * notification, but GPS is only activated for ~5 seconds per fix. Between
     * fixes the GPS radio is off and no GPS icon is shown.
     *
     * For the WorkManager strategy (no foreground service), see
     * [PeriodicLocationWorker].
     */
    fun startPeriodic() {
        if (!hasPermission()) {
            TraceletLog.warning("startPeriodic() — no location permission, aborting")
            return
        }
        stopPeriodic()

        val intervalMs = config.getPeriodicLocationInterval() * 1000L
        TraceletLog.debug("startPeriodic() — interval=${intervalMs}ms")

        periodicRunnable = object : Runnable {
            override fun run() {
                if (!state.enabled) {
                    TraceletLog.debug("periodic tick — state.enabled=false, skipping")
                    return
                }

                TraceletLog.debug("periodic tick — requesting one-shot fix")

                // Perform a one-shot fix using the periodic accuracy setting
                val options = mapOf<String, Any?>(
                    "desiredAccuracy" to config.getPeriodicDesiredAccuracy(),
                    "persist" to true,
                    "samples" to 1,
                )
                getCurrentPosition(options) { location ->
                    val resolved = location ?: run {
                        // Fallback: use last known location if fresh fix failed
                        TraceletLog.warning("periodic fix returned null — trying lastKnownLocation fallback")
                        val last = getLastLocation()
                        if (last != null) enrichLocation(last, "periodic") else null
                    }

                    if (resolved != null) {
                        val lat = resolved["latitude"] as? Double
                        val lng = resolved["longitude"] as? Double
                        val accuracy = resolved["accuracy"] as? Double
                            ?: (resolved["coords"] as? Map<*, *>)?.get("accuracy") as? Double
                            ?: 0.0

                        // Update odometer from distance since last periodic fix
                        if (lat != null && lng != null) {
                            val lastLat = state.lastPeriodicLatitude
                            val lastLng = state.lastPeriodicLongitude
                            if (!lastLat.isNaN() && !lastLng.isNaN()) {
                                val results = FloatArray(1)
                                android.location.Location.distanceBetween(
                                    lastLat, lastLng, lat, lng, results,
                                )
                                val distance = results[0].toDouble()
                                val threshold = config.getOdometerAccuracyThreshold()
                                if (threshold <= 0 || accuracy <= threshold) {
                                    state.addOdometer(distance)
                                }
                            }
                            state.lastPeriodicLatitude = lat
                            state.lastPeriodicLongitude = lng
                        }

                        // Enrich with periodic event tag and updated odometer
                        val enriched = resolved.toMutableMap()
                        enriched["event"] = "periodic"
                        enriched["odometer"] = state.odometer
                        
                        // Only a speed the fix actually carried. `?: 0.0` here fed
                        // the motion machine a fabricated "stopped" every time a
                        // periodic fix arrived without one, which is the same
                        // fabricated zero that drops a moving session to SLOWING.
                        val speed = resolved["speed"] as? Double
                        if (speed != null && speed > 0) {
                            speedMotionSpeedSink?.invoke(speed)
                        }
                        
                        events.sendLocation(enriched)
                        TraceletLog.debug("periodic fix dispatched — lat=$lat, lng=$lng, acc=$accuracy, speed=${speed ?: "unknown"}")

                        // Notify proximity-based geofence monitoring.
                        //
                        // Geofence work lives on [onRawGeofenceLocation] (#352), so a
                        // periodic fix must drive that hook too — periodic fixes never
                        // reach the processor, so this is their only path to geofence
                        // registration. [onLocationUpdate] still fires for its other
                        // consumers (trip waypoints).
                        if (lat != null && lng != null) {
                            onRawGeofenceLocation?.invoke(lat, lng, accuracy ?: 0.0)
                            onLocationUpdate?.invoke(lat, lng, accuracy ?: 0.0)
                        }
                    } else {
                        TraceletLog.warning("periodic fix — no location available (fresh + fallback both null)")
                    }
                }

                periodicHandler.postDelayed(this, intervalMs)
            }
        }

        // Fire immediately, then repeat at interval
        periodicHandler.post(periodicRunnable!!)
    }

    /** Stops periodic one-shot tracking. */
    fun stopPeriodic() {
        periodicRunnable?.let { periodicHandler.removeCallbacks(it) }
        periodicRunnable = null
        // Reset last periodic coordinates so the next start doesn't
        // compute distance from a stale position.
        state.lastPeriodicLatitude = Double.NaN
        state.lastPeriodicLongitude = Double.NaN
    }

    /**
     * One-shot current position with configurable accuracy and sampling.
     *
     * Supported [options]:
     * - `desiredAccuracy` (Int): Accuracy level override.
     * - `timeout` (Long): Timeout in seconds (default 30).
     * - `maximumAge` (Long): Max age in ms of acceptable cached location.
     * - `persist` (Boolean): Whether to persist to DB (default true).
     * - `samples` (Int): Number of samples to collect; returns best accuracy (default 1).
     * - `accuracyTarget` (Double): Optional horizontal target in metres.
     * - `requestId` (String): Optional caller-owned cancellation identifier.
     * - `extras` (Map): Extra data to attach to the location.
     *
     * [callback] receives the enriched location map or null.
     */
    fun getCurrentPosition(options: Map<String, Any?>, callback: (Map<String, Any?>?) -> Unit) {
        if (!hasPermission()) {
            callback(null)
            return
        }

        val timeout = (options["timeout"] as? Number)?.toLong() ?: 30L
        val desiredAccuracy = (options["desiredAccuracy"] as? Number)?.toInt()
            ?: config.getDesiredAccuracy()
        val maximumAge = (options["maximumAge"] as? Number)?.toLong() ?: 0L
        val persist = options["persist"] as? Boolean ?: true
        val samples = (options["samples"] as? Number)?.toInt()?.coerceAtLeast(1) ?: 1
        val accuracyTarget = (options["accuracyTarget"] as? Number)?.toFloat()
            ?.takeIf { it.isFinite() && it >= 0f }
        val requestId = options["requestId"] as? String
        @Suppress("UNCHECKED_CAST")
        val extras = options["extras"] as? Map<String, Any?> ?: emptyMap()
        // An explicit one-shot getCurrentPosition() must actively obtain a fix.
        // PRIORITY_PASSIVE (used by the passive tracking profile) only yields a
        // location when *another* app is actively requesting one, so the fused
        // client returns nothing and the request times out with LOCATION_FAILURE.
        // Floor passive to BALANCED so an explicit position request always works,
        // regardless of the background tracking profile.
        val priority = accuracyToPriority(desiredAccuracy)
            .let {
                if (it == TraceletLocationPriority.PRIORITY_PASSIVE)
                    TraceletLocationPriority.PRIORITY_BALANCED_POWER_ACCURACY
                else it
            }

        var cachedCandidate: Location? = null
        if (maximumAge > 0) {
            val cached = lastLocation
            if (cached != null) {
                val age = System.currentTimeMillis() - cached.time
                if (age <= maximumAge) {
                    if ((accuracyTarget == null || cached.accuracy <= accuracyTarget) &&
                        requestId == null
                    ) {
                        val enriched = enrichLocation(cached, "getCurrentPosition").toMutableMap()
                        mergeExtras(enriched, extras)
                        resolveAddressAndDispatch(cached, enriched) { finalEnriched ->
                            if (persist) onLocationPersisted?.invoke()
                            callback(finalEnriched)
                        }
                        return
                    }
                    cachedCandidate = cached
                }
            }
        }

        // Use collectSamples for all cases — including samples == 1.
        // TraceletLocationClient.getCurrentLocation() may return a stale
        // cached location without waking the GPS hardware, causing
        // getCurrentPosition() to return old positions. collectSamples uses
        // requestLocationUpdates() which forces a fresh GPS fix with proper
        // timeout handling.
        collectSamples(
            priority,
            samples,
            accuracyTarget,
            requestId,
            listOfNotNull(cachedCandidate),
            timeout,
            persist,
            extras,
            callback,
        )
    }

    /**
     * Returns the last known location from the fused provider cache.
     *
     * This never activates any location provider — it is a zero-battery-cost
     * operation. Returns null if no cached location is available.
     *
     * Supported [options]:
     * - `persist` (Boolean): Whether to persist to DB (default false).
     * - `extras` (Map): Extra data to attach to the location.
     */
    fun getLastKnownLocation(options: Map<String, Any?>, callback: (Map<String, Any?>?) -> Unit) {
        if (!hasPermission()) {
            callback(null)
            return
        }

        val persist = options["persist"] as? Boolean ?: false
        /** Forces the engine to bypass the fast in-memory cache and fetch a fresh location from the provider */
        val skipCache = options["skipCache"] as? Boolean ?: false
        @Suppress("UNCHECKED_CAST")
        val extras = options["extras"] as? Map<String, Any?> ?: emptyMap()

        // 1. Check our own in-memory cache first (most reliable) if allowed.
        if (!skipCache) {
            val cached = lastLocation
            if (cached != null) {
                val enriched = enrichLocation(cached, "getLastKnownLocation").toMutableMap()
                mergeExtras(enriched, extras)
                resolveAddressAndDispatch(cached, enriched) { finalEnriched ->
                    if (persist) {
                        onLocationPersisted?.invoke()
                    }
                    callback(finalEnriched)
                }
                return
            }
        }

        // 2. Try TraceletLocationClient cache.
        try {
            fusedClient.getLastLocation(onSuccess = { location ->
                if (location != null) {
                    lastLocation = location
                    val enriched = enrichLocation(location, "getLastKnownLocation").toMutableMap()
                    mergeExtras(enriched, extras)
                    resolveAddressAndDispatch(location, enriched) { finalEnriched ->
                        if (persist) {
                            onLocationPersisted?.invoke()
                        }
                        callback(finalEnriched)
                    }
                } else {
                    // 3. Fallback to system LocationManager — works even when
                    //    TraceletLocationClient has no cache.
                    val fallback = getSystemLastKnownLocation()
                    if (fallback != null) {
                        lastLocation = fallback
                        val enriched = enrichLocation(fallback, "getLastKnownLocation").toMutableMap()
                        mergeExtras(enriched, extras)
                        resolveAddressAndDispatch(fallback, enriched) { finalEnriched ->
                            if (persist) {
                                onLocationPersisted?.invoke()
                            }
                            callback(finalEnriched)
                        }
                    } else {
                        callback(null)
                    }
                }
            }, onFailure = {
                // Fallback to system LocationManager on failure too.
                val fallback = getSystemLastKnownLocation()
                if (fallback != null) {
                    lastLocation = fallback
                    val enriched = enrichLocation(fallback, "getLastKnownLocation").toMutableMap()
                    mergeExtras(enriched, extras)
                    if (persist) {
                        onLocationPersisted?.invoke()
                    }
                    callback(enriched)
                } else {
                    callback(null)
                }
            })
        } catch (e: SecurityException) {
            callback(null)
        }
    }

    /**
     * Fallback: queries the Android [LocationManager] for cached GPS /
     * network locations. Returns the most recent one, or null.
     */
    private fun getSystemLastKnownLocation(): Location? {
        val lm = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            ?: return null
        return try {
            val gps = lm.getLastKnownLocation(LocationManager.GPS_PROVIDER)
            val network = lm.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
            when {
                gps != null && network != null ->
                    if (gps.time >= network.time) gps else network
                gps != null -> gps
                else -> network
            }
        } catch (_: SecurityException) {
            null
        }
    }

    /**
     * Starts a watch position with the given options.
     * Returns the watchId.
     */
    fun watchPosition(options: Map<String, Any?>): Int {
        if (!hasPermission()) return -1

        val watchId = nextWatchId++
        val interval = (options["interval"] as? Number)?.toLong() ?: 1000L
        val distanceFilter = (options["distanceFilter"] as? Number)?.toFloat() ?: 0f
        val desiredAccuracy = (options["desiredAccuracy"] as? Number)?.toInt() ?: 0
        val priority = accuracyToPriority(desiredAccuracy)

        val request = TraceletLocationRequest(priority = priority, intervalMillis = interval, minUpdateDistanceMeters = distanceFilter)

        val watchCallback = object : TraceletLocationCallback {
            override fun onLocationResult(locations: List<Location>) {
                for (location in locations) {
                    // Mock rejection applies to watched fixes too — they bypass
                    // onLocationReceived()'s defense-in-depth check.
                    if (config.getRejectMockLocations() && isLocationMock(location)) {
                        TraceletLog.warning("watchPosition: rejected mock location")
                        continue
                    }
                    // enrichLocation() already returns a MutableMap; avoid
                    // unnecessary shallow copy from toMutableMap() (A-L3).
                    val data = enrichLocation(location, "watchPosition") as MutableMap<String, Any?>
                    data["watchId"] = watchId
                    events.sendWatchPosition(data)
                }
            }
            override fun onLocationAvailability(isLocationAvailable: Boolean) {}
        }

        try {
            fusedClient.requestLocationUpdates(request, watchCallback, Looper.getMainLooper())
            watchers[watchId] = watchCallback
        } catch (e: SecurityException) {
            return -1
        }

        return watchId
    }

    /** Stops a specific watch position. */
    fun stopWatchPosition(watchId: Int): Boolean {
        val callback = watchers.remove(watchId) ?: return false
        fusedClient.removeLocationUpdates(callback)
        return true
    }

    /** Stops all watch positions. */
    fun stopAllWatchers() {
        for ((_, callback) in watchers) {
            fusedClient.removeLocationUpdates(callback)
        }
        watchers.clear()
    }

    /**
     * Toggle pace: if [isMoving] is true, switch to high-frequency tracking;
     * if false, stop location updates (simulate stationary).
     */
    fun changePace(isMoving: Boolean): Boolean {
        val wasTracking = isTracking
        state.isMoving = isMoving
        if (isMoving && !isTracking) {
            start()
        } else if (!isMoving && isTracking) {
            // Stopping here is #319's premise — nothing needs the continuous
            // stream while the device is still. A fence the OS cannot resolve
            // breaks it: since #355 that fence is decided *from* this stream, so
            // dropping it leaves the evaluator with nothing to judge and the
            // fence silently dead until the device happens to move again. The
            // killed-state reconcile already refuses this for the same reason
            // (LocationService.reconcile); the alive app has to as well (#357).
            if (geofenceHighAccuracyMode) {
                TraceletLog.lifecycle(
                    "motion: staying continuous while stationary — an " +
                        "in-app-evaluated geofence is decided from the location " +
                        "stream (#357)"
                )
            } else {
                stop()
            }
        }
        // On an actual stationary → moving transition, fire an additional
        // one-shot getCurrentLocation() so a fresh GPS fix arrives as soon
        // as the hardware is warm, bypassing the `locationUpdateInterval`
        // wait on the continuous stream. Routed through onLocationReceived()
        // so the full processing pipeline (filters, Kalman, persistence)
        // still applies.
        if (isMoving && !wasTracking) {
            requestImmediateFix()
        }
        // Dispatch motionChange event
        val locationMap = lastLocation?.let { enrichLocation(it, "motionchange", lastEffectiveSpeed) }
            ?: mapOf("is_moving" to isMoving)
        events.sendMotionChange(locationMap)
        return true
    }

    /**
     * Acquires the single fix that anchors a session which *starts* stationary
     * (#385).
     *
     * A fresh `start()` with `motion.isMoving: false` — the default — runs no
     * continuous stream by design, and on this path the stationary schedule is
     * not armed either: the SMART coordinator is synced to STATIONARY_PERIODIC
     * before both of its inputs are pushed to stationary, so `evaluate_state`
     * sees no mode change and returns `None`. Nothing called the provider at
     * all, and the app got no location until the device physically moved and
     * [changePace] took the transition below.
     *
     * Passive is floored to balanced for the same reason
     * [getCurrentPosition] floors it: PRIORITY_PASSIVE only yields a fix while
     * *another* app is actively requesting one, so a passive tracking profile
     * would otherwise reproduce the very silence this exists to fix. It is
     * floored only here — the transition path keeps its configured priority,
     * where the continuous stream it accompanies is the thing actually
     * acquiring.
     */
    fun requestStartupFix() {
        // The stream is already acquiring — a moving start, or the
        // in-app-evaluated-geofence branch of a stationary one (#357).
        if (isTracking) return
        requestImmediateFix(isStartupFix = true)
    }

    /**
     * Fires a single [getCurrentLocation] request to deliver a fresh fix
     * immediately after a stationary → moving transition, or at the start of a
     * session that begins stationary ([requestStartupFix], [isStartupFix]).
     *
     * The result is fed into the same [onLocationReceived] pipeline used
     * by the continuous stream, so all filters, Kalman, persistence, and
     * event dispatch remain consistent.
     */
    private fun requestImmediateFix(isStartupFix: Boolean = false) {
        if (!hasPermission()) return
        // Supersede any prior in-flight one-shot so we never have two racing.
        immediateFixCts?.cancel()
        val cts = TraceletCancellationTokenSource()
        immediateFixCts = cts
        val priority = accuracyToPriority(config.getDesiredAccuracy())
            .let {
                if (isStartupFix && it == TraceletLocationPriority.PRIORITY_PASSIVE)
                    TraceletLocationPriority.PRIORITY_BALANCED_POWER_ACCURACY
                else it
            }
        try {
            fusedClient.getCurrentLocation(priority, cts.token, onSuccess = { location ->
                if (location != null && immediateFixCts === cts) {
                    onLocationReceived(location, "location", isStartupFix = isStartupFix)
                }
            })
        } catch (_: SecurityException) {
            // Permission revoked mid-call — ignore.
        }
    }

    /** Returns the current odometer value. */
    fun getOdometer(): Double = state.odometer

    /**
     * Sets the odometer to a specific value.
     *
     * The processor's odometer anchor goes with it (#387). Distance is measured
     * from that anchor, not from the total, so writing the counter alone left
     * the next accepted fix to add the whole span since the previous one — for
     * the common "reset to zero, then start tracking", however far the device
     * had travelled while it was not being tracked. `setOdometer(0)` meant
     * "the odometer is zero" for exactly one fix.
     *
     * Only the odometer anchor is cleared, never the tracking one: that would
     * waive the distance filter for the next fix and change which locations are
     * recorded, which is not something setting a counter should do.
     */
    fun setOdometer(value: Double): Map<String, Any?> {
        state.odometer = value
        locationProcessor?.resetOdometerAnchor()
        return lastLocation?.let { enrichLocation(it, "setOdometer") }
            ?: mapOf("odometer" to value)
    }

    /** Updates the current activity (from MotionDetector). */
    fun setCurrentActivity(type: String, confidence: Int) {
        currentActivityType = type
        currentActivityConfidence = confidence
    }

    /** Returns the last known location or null. */
    fun getLastLocation(): Location? = lastLocation

    /** Returns the best location for heartbeat: prefers the last GPS-quality
     *  fix (≤100m accuracy) over a potentially stale significant-change fix.
     *  Falls back to lastLocation if no GPS fix exists. */
    fun getLastGpsLocation(): Location? = lastGpsLocation ?: lastLocation

    /** Returns provider state info. */
    fun buildProviderState(): Map<String, Any?> {
        val lm = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        val hasFine = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
        val hasCoarse = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
        val hasBackground = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION) ==
                PackageManager.PERMISSION_GRANTED

        val status = when {
            hasBackground -> 3 // ALWAYS
            hasFine || hasCoarse -> 2 // WHEN_IN_USE
            else -> 0 // DENIED
        }

        return mapOf(
            "enabled" to (lm?.let { LocationManagerCompat.isLocationEnabled(it) } ?: false),
            "status" to status,
            "gps" to (lm?.isProviderEnabled(LocationManager.GPS_PROVIDER) ?: false),
            "network" to (lm?.isProviderEnabled(LocationManager.NETWORK_PROVIDER) ?: false),
            "accuracyAuthorization" to if (hasFine) 0 else 1, // 0=full, 1=reduced
            "platform" to "android",
        )
    }

    /** Destroys resources. */
    fun destroy() {
        stop()
        stopAllWatchers()
        locationProcessor?.destroy()
        locationProcessor = null
        kalmanFilter?.destroy()
        kalmanFilter = null
    }

    // =========================================================================
    // Private methods
    // =========================================================================

    /**
     * @param isStartupFix true only for the anchor fix [requestStartupFix]
     * takes at the start of a stationary session. It reaches the app, the DB
     * and the geofence evaluator like any other fix, but it is kept out of the
     * speed motion machine — see the sink below.
     */
    private fun onLocationReceived(location: Location, event: String, isStartupFix: Boolean = false) {
        // Only reset DR timer when GPS hardware is enabled AND the fix
        // is GPS-quality.  When the user has toggled GPS off,
        // FusedLocationProvider can still deliver accurate Wi-Fi / cell
        // fixes — those must NOT prevent DR from activating.
        val gpsEnabled = isGpsProviderEnabled(context)
        if (gpsEnabled && isGpsFix(location)) {
            resetGpsLossTimer()
            if (deadReckoningEngine?.isActive == true) {
                TraceletLog.debug("GPS signal recovered — deactivating dead reckoning")
                deactivateDeadReckoning()
            }
        }

        val speed = location.speed.toDouble()
        
        // --- Mock location rejection (defense-in-depth) ---
        if (config.getRejectMockLocations() && isLocationMock(location)) {
            // Fire a provider change event to notify Dart that mock was detected.
            if (!mockLocationWarningFired) {
                mockLocationWarningFired = true
                val providerState = buildProviderState().toMutableMap()
                providerState["mockLocationsDetected"] = true
                events.sendProviderChange(providerState)
            }
            return // Drop the mock location entirely.
        }

        // --- Geofence crossing evaluation on the RAW stream ---
        // Runs before the persistence distance filter below so a stationary
        // device (whose fixes that filter drops) is never starved of crossing
        // evaluations. See [onRawGeofenceLocation]. Persistence is unaffected —
        // the processor filter still gates what reaches the DB/sync queue.
        onRawGeofenceLocation?.invoke(
            location.latitude, location.longitude, location.accuracy.toDouble(),
        )

        // Calculate distance from last location for odometer
        val distance = lastLocation?.distanceTo(location)?.toDouble() ?: 0.0

        // --- Compute speed from distance/time as fallback ---
        val timeDelta = if (lastLocation != null) {
            (location.time - lastLocation!!.time).toDouble() / 1000.0 // seconds
        } else {
            0.0
        }
        val rawComputedSpeed = if (distance > 0 && timeDelta > 0) distance / timeDelta else 0.0

        // A derived speed is only as good as its time base, and `timeDelta > 0` is
        // satisfied by one millisecond. Two fixes delivered back to back — routine
        // when a session starts and a cached fix arrives alongside a fresh one —
        // divide a real distance by an almost-zero interval, which produced
        // thousands of m/s from a stationary device, enough to wake the speed
        // motion machine out of STATIONARY since speedWakeConfirmCount is 1 by
        // default (#342).
        //
        // `maxImpliedSpeed` already encodes what counts as credible movement; above
        // it this is an artefact, not a measurement. Report *no* speed rather than a
        // fabricated one. That is not #332 in reverse: this branch is only reached
        // when the platform supplied no speed at all, so 0 is the pre-existing
        // meaning of "unknown" rather than a value invented in place of a real
        // reading. A genuinely moving device has a Doppler speed and never gets here.
        val maxImplied = config.getMaxImpliedSpeed().toDouble()
        val computedSpeed = if (maxImplied > 0 && rawComputedSpeed > maxImplied) {
            TraceletLog.debug(
                "Discarding implausible derived speed $rawComputedSpeed m/s " +
                    "(${distance}m over ${timeDelta}s, max $maxImplied m/s) — reporting no speed",
            )
            0.0
        } else {
            rawComputedSpeed
        }

        // Use platform speed if available, otherwise use computed speed.
        //
        // The startup anchor (#385) has no valid time base for the derivation:
        // `lastLocation` survives stop(), so the first fix of a new session in a
        // live process would be derived against wherever the *previous* session
        // ended. A device carried 5 km between two sessions yields ~8 m/s —
        // inside `maxImpliedSpeed` (80 m/s), so nothing discards it. A Doppler
        // reading is a real measurement and is kept; the derivation is dropped,
        // for this one fix only, which is what "no speed" already means here.
        val effectiveSpeed = if (location.hasSpeed() && location.speed > 0) {
            location.speed.toDouble()
        } else if (isStartupFix) {
            0.0
        } else {
            computedSpeed
        }

        // Feed the transport classifier from the raw stream — see [rawSpeedSink].
        rawSpeedSink?.invoke(effectiveSpeed)

        // --- Kalman smoothing (optional) ---
        // Runs BEFORE the processor so the odometer accumulates over the smoothed
        // track rather than the raw one (#299). Previously this ran afterwards and
        // only fed `coords`, which meant enabling `useKalmanFilter` visibly
        // smoothed the map but left distance accumulating raw GPS jitter — the
        // reported "distance is 3x too high while walking" symptom.
        //
        // Feeding every fix (not only accepted ones) also keeps the filter's
        // velocity estimate continuous across fixes the processor rejects.
        var smoothedLat = location.latitude
        var smoothedLng = location.longitude
        kalmanFilter?.let { kalman ->
            val smoothed = kalman.process(
                latitude = location.latitude,
                longitude = location.longitude,
                accuracy = location.accuracy.toDouble(),
                timestampMs = location.time,
            )
            smoothedLat = smoothed.latitude
            smoothedLng = smoothed.longitude
        }

        // --- Rust-powered filtering (distance, accuracy, speed, mock, sparse) ---
        val mock = isLocationMock(location)
        val processor = getProcessor()
        val battery = BatteryUtils.getBatteryInfo(context)
        val batteryLevel = (battery["level"] as? Number)?.toDouble() ?: -1.0
        val isCharging = (battery["is_charging"] as? Boolean) ?: false
        val adaptiveCtx = AdaptiveContext(
            // #299: use the effective activity, so a `fusedClassifierAuthoritative`
            // classifier actually reaches the adaptive sampler as documented.
            // Previously this passed the raw AR activity unconditionally, which
            // made the setting a no-op for sampling.
            activityType = mapActivityType(effectiveActivityType()),
            activityConfidence = mapActivityConfidence(effectiveActivityConfidence()),
            batteryLevel = batteryLevel,
            isCharging = isCharging,
            speed = effectiveSpeed,
        )
        val result = processor.process(
            latitude = smoothedLat,
            longitude = smoothedLng,
            accuracy = location.accuracy.toDouble(),
            speed = effectiveSpeed,
            timestampMs = location.time,
            isMock = mock,
            adaptiveContext = adaptiveCtx,
        )
        // IMPORTANT: Always feed the speed motion state machine, even when the
        // Rust processor rejects the location for persistence/dispatch. The speed
        // SM needs every speed reading to correctly transition between
        // MOVING → SLOWING → STATIONARY. Without this, a stationary device
        // whose locations are filtered (e.g. same lat/lng, no distance change)
        // will never transition out of MOVING state.
        //
        // `result.effectiveSpeed` is the speed the processor resolved for this
        // fix whether or not it accepted it — it used to be hardcoded to 0 on
        // every rejection, which fed the machine a fabricated "stopped" for
        // most of every drive (#332).
        //
        // The anchor keeps the measured-speed-only rule applied above: the
        // *processor* derives its own speed from its own last accepted fix
        // (`state.last_latitude`), which stop() does not clear either, so
        // `result.effectiveSpeed` re-introduces exactly the cross-session
        // derivation that `effectiveSpeed` just declined. Left alone it would
        // overturn the pace `start()` committed a few lines before asking for
        // the anchor — 8 m/s is well above `speedMovingThreshold` (1.5 m/s) —
        // which is the silent override of a committed pace that #344 and
        // StartCommittedPaceTest exist to prevent (#385).
        val motionSpeed = if (isStartupFix) effectiveSpeed else result.effectiveSpeed

        // Only a *current* fix may tell the pace machine how fast we are going.
        //
        // The fused provider delivers its cached last-known fix the moment
        // `requestLocationUpdates` is called, and that fix carries the speed
        // from whenever it was taken — which, on a session the accelerometer
        // has just woken, is from before the device stopped. The trace shows
        // the consequence in the same second as the wake:
        //
        //   16:59:52 speed-motion: STATIONARY -> MOVING — manual pace change
        //   16:59:52 speed-motion: MOVING -> SLOWING — speed=0.10 m/s
        //
        // and STATIONARY again 30 s later. Walking in the background therefore
        // produced a cycle — accelerometer wakes the stream, a stale reading
        // stands it down, the stream stops — instead of tracking, with the
        // location indicator flickering off and staying off.
        //
        // Persistence and dispatch are deliberately untouched: a cached fix is
        // still a real position and the processor's own gates decide whether to
        // keep it. It is only its *speed* that says nothing about now.
        val fixAgeMs = (SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos) / 1_000_000
        if (fixAgeMs <= MAX_PACE_FIX_AGE_MS) {
            if (staleFixesSincePace > 0) {
                // Always-on: this is the moment the pace machine regains a real
                // input, and its absence is what a "tracking stopped by itself"
                // report is actually describing.
                TraceletLog.lifecycle(
                    "pace: a current fix again after $staleFixesSincePace stale one(s) — " +
                        "speed=${"%.2f".format(motionSpeed)} m/s",
                )
                staleFixesSincePace = 0
            }
            speedMotionSpeedSink?.invoke(motionSpeed)
        } else {
            staleFixesSincePace++
            // Once per run of stale fixes, not once per fix: the run is the
            // event, and a released app has to be able to report it.
            if (staleFixesSincePace == 1) {
                TraceletLog.lifecycle(
                    "pace: ignoring a ${fixAgeMs}ms-old fix's speed " +
                        "(${"%.2f".format(motionSpeed)} m/s) — a reading older than " +
                        "${MAX_PACE_FIX_AGE_MS}ms says nothing about the current pace, and " +
                        "letting it through stood a just-woken session back down",
                )
            }
        }

        var isForcedAccept = false
        if (!result.accepted) {
            if (forcePersistNextFilteredLocation) {
                TraceletLog.debug("Location filtered by Rust processor, but FORCE ACCEPTING due to pending motion change.")
                isForcedAccept = true
                forcePersistNextFilteredLocation = false
            } else {
                // #334: the speed handed to the motion machine belongs on this
                // line. Without it, a rejected fix's contribution to a
                // stationary decision can only be inferred by cross-reading the
                // speed-motion entries.
                //
                // #397: so do the numbers the decision was actually made on. A
                // bare DISTANCE_FILTER cannot be checked against anything — an
                // 8 m gate and the 750 m one adaptive sampling can inflate it to
                // look identical in a log, and telling them apart is the whole
                // diagnosis.
                val tuning = locationProcessor?.currentTuning()
                TraceletLog.debug(
                    "Location filtered by Rust processor: ${result.reason} " +
                        "(speed=${"%.2f".format(result.effectiveSpeed)} m/s fed to speed motion, " +
                        "acc=${"%.1f".format(result.accuracy)}m, " +
                        "moved=${"%.1f".format(result.distance)}m vs " +
                        "gate=${"%.1f".format(result.effectiveDistanceFilter)}m, " +
                        "anchor=${"%.0f".format(result.anchorAgeSeconds)}s, " +
                        "thresholds df=${tuning?.distanceFilter}/" +
                        "acc=${tuning?.trackingAccuracyThreshold}/" +
                        "spd=${tuning?.maxImpliedSpeed})",
                )
                noteFilterDecision(result, accepted = false)
                // Still update odometer if the processor computed a delta
                if (result.odometerDelta > 0) {
                    state.addOdometer(result.odometerDelta)
                }
                return
            }
        } else {
            forcePersistNextFilteredLocation = false
            // Hand back the slot the anchor just took (#385).
            //
            // The processor waives the distance filter only for a fix with no
            // predecessor (`state.last_latitude.is_some() && distance < ...`).
            // Before the anchor existed, the fix that woke a stationary session
            // — the #54 one-shot on a changePace(true), or the first fix of the
            // stream the SMART coordinator starts — *was* that first fix, and
            // was delivered for free. The anchor now holds that slot, and the
            // wake fix is metres away from it, so it would be dropped as a
            // duplicate: the app would be told it is moving and handed no
            // position to go with it.
            //
            // Deliberately not scoped to any one wake path: this is about the
            // *next* fix whatever produces it, which is what makes it cover the
            // accelerometer wake as well as the explicit pace change. While the
            // session stays stationary there is no stream, so nothing else can
            // consume it in the meantime.
            if (isStartupFix) forcePersistNextFilteredLocation = true
        }

        noteFilterDecision(result, accepted = true)

        // Odometer update from processor's computed delta
        if (result.odometerDelta > 0) {
            state.addOdometer(result.odometerDelta)
        }

        lastLocation = location
        if (location.accuracy > 0 && location.accuracy <= 100) {
            lastGpsLocation = location
        }
        // `motionSpeed`, not `result.effectiveSpeed`: this field is read as the
        // session's current speed, and start() seeds the speed machine with it
        // — so an anchor's derived value would reach the machine one session
        // later through that door even though the sink above declined it (#385).
        lastEffectiveSpeed = motionSpeed
        state.lastLocationTime = location.time

        val actualEvent = if (isForcedAccept) "motionchange" else event
        // Identical to result.effectiveSpeed for every fix but the anchor,
        // which reports what was measured rather than what was derived (#385).
        val enriched = enrichLocation(location, actualEvent, motionSpeed, smoothedLat, smoothedLng)

        fun dispatch(finalEnriched: Map<String, Any?>) {
            // Privacy zone check (Enterprise) — BEFORE audit + persist + send.
            // Evaluates whether the location falls inside a registered privacy zone
            // and applies the configured action (exclude / degrade / event-only).
            val privacyResult = privacyZoneManager?.processLocation(finalEnriched)
            if (privacyResult != null) {
                when (privacyResult.action) {
                    PrivacyZoneManager.ProcessedLocation.Action.DROP -> {
                        // Exclusion zone — drop this location entirely.
                        return
                    }
                    PrivacyZoneManager.ProcessedLocation.Action.EVENT_ONLY -> {
                        // Dispatch to Dart but do NOT persist or audit.
                        val locationData = privacyResult.location ?: finalEnriched
                        events.sendLocation(locationData)
                        onLocationUpdate?.invoke(location.latitude, location.longitude, location.accuracy.toDouble())
                        return
                    }
                    PrivacyZoneManager.ProcessedLocation.Action.DEGRADED -> {
                        // Use the degraded location for audit + persist + dispatch.
                        val degraded = privacyResult.location ?: finalEnriched
                        val auditFields = auditTrailManager?.appendToChain(degraded)
                        val withAudit = if (auditFields != null) {
                            degraded.toMutableMap().apply { putAll(auditFields) }
                        } else {
                            degraded
                        }
                        persistLocationIfAllowed(withAudit, actualEvent)
                        events.sendLocation(withAudit)
                        onLocationUpdate?.invoke(location.latitude, location.longitude, location.accuracy.toDouble())
                        
                        if (isForcedAccept) {
                            try {
                                com.ikolvi.tracelet.sdk.TraceletSdk.getInstance(context).sync {}
                            } catch (e: Exception) {}
                        }
                        return
                    }
                    else -> { /* PASS_THROUGH — fall through to normal flow */ }
                }
            }

            // Compute audit trail hash (Enterprise) — must happen BEFORE persist
            // so the chain is sequential with DB inserts.
            val auditFields = auditTrailManager?.appendToChain(finalEnriched)
            val enrichedWithAudit = if (auditFields != null) {
                finalEnriched.toMutableMap().apply { putAll(auditFields) }
            } else {
                finalEnriched
            }

            // Persist to database (respecting persistMode)
            persistLocationIfAllowed(enrichedWithAudit, actualEvent)

            // Dispatch to Dart
            events.sendLocation(enrichedWithAudit)

            // Notify geofenceModeHighAccuracy listener (if active)
            onLocationUpdate?.invoke(location.latitude, location.longitude, location.accuracy.toDouble())
            
            if (isForcedAccept) {
                try {
                    com.ikolvi.tracelet.sdk.TraceletSdk.getInstance(context).sync {}
                } catch (e: Exception) {}
            }
        }

        resolveAddressAndDispatch(location, enriched) { finalEnriched ->
            dispatch(finalEnriched)
        }
    }

    /**
     * Enriches a raw [Location] into a full map ready for Dart/DB.
     *
     * @param location      The raw platform location.
     * @param event         The event name (e.g. "motionchange").
     * @param speed         Pre-computed effective speed (m/s).
     * @param smoothedLat   Kalman-smoothed latitude (null = use raw).
     * @param smoothedLng   Kalman-smoothed longitude (null = use raw).
     */
    fun enrichLocation(
        location: Location,
        event: String,
        speed: Double? = null,
        smoothedLat: Double? = null,
        smoothedLng: Double? = null,
    ): Map<String, Any?> {
        val battery = BatteryUtils.getBatteryInfo(context)
        val timestamp = isoFormatter.format(Date(location.time))

        // Use provided effective speed, or fall back to platform speed.
        val effectiveSpeed = speed ?: location.speed.toDouble()

        val mock = isLocationMock(location)

        // Always include heuristic metadata (like satellite count) even if rejection is off
        val extras = location.extras
        val satellites = extras?.getInt("satellites", -1) ?: -1
        val driftNanos = SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos
        val driftMs = driftNanos / 1_000_000.0
        val mockHeuristics = mapOf(
            "satellites" to satellites,
            "elapsedRealtimeDriftMs" to driftMs,
            "platformFlagMock" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) location.isMock else location.isFromMockProvider,
        )

        // Classify the location source based on provider and accuracy.
        val locationSource = when {
            location.provider == "gps" -> "gps"
            location.provider == "fused" && location.accuracy <= GPS_ACCURACY_THRESHOLD -> "gps"
            location.provider == "network" || gpsFallbackActive -> "network"
            location.provider == "fused" && location.accuracy <= 200f -> "wifi"
            location.provider == "fused" -> "cell"
            else -> "unknown"
        }

        val result = mutableMapOf<String, Any?>(
            "uuid" to UUID.randomUUID().toString(),
            "timestamp" to timestamp,
            "is_moving" to state.isMoving,
            "odometer" to state.odometer,
            "event" to event,
            "locationSource" to locationSource,
            "reducedAccuracy" to false,  // Android has no reduced-accuracy concept like iOS 14+
            "mock" to mock,
            "mockHeuristics" to mockHeuristics,
            "coords" to mapOf(
                "latitude" to (smoothedLat ?: location.latitude),
                "longitude" to (smoothedLng ?: location.longitude),
                "altitude" to location.altitude,
                "speed" to effectiveSpeed,
                "heading" to location.bearing.toDouble(),
                "accuracy" to location.accuracy.toDouble(),
                "speedAccuracy" to if (location.hasSpeedAccuracy()) location.speedAccuracyMetersPerSecond.toDouble() else -1.0,
                "headingAccuracy" to if (location.hasBearingAccuracy()) location.bearingAccuracyDegrees.toDouble() else -1.0,
                "altitudeAccuracy" to if (location.hasVerticalAccuracy()) location.verticalAccuracyMeters.toDouble() else -1.0,
            ),
            "activity" to mapOf(
                // #214 pt3: persist the fused transport mode when authoritative so
                // it survives termination and syncs historically (falls back to AR).
                "type" to effectiveActivityType(),
                "confidence" to effectiveActivityConfidence(),
            ),
            "battery" to battery,
        )

        val httpExtras = config.getHttpExtras()
        if (httpExtras.isNotEmpty()) {
            result["extras"] = httpExtras
        }

        // enableTimestampMeta: attach additional timing metadata
        if (config.getEnableTimestampMeta()) {
            result["timestampMeta"] = mapOf(
                "time" to location.time,
                "systemTime" to System.currentTimeMillis(),
                "systemClockElapsedRealtime" to SystemClock.elapsedRealtime(),
            )
        }

        return result
    }

    private val currentPositionCancellations = mutableMapOf<String, () -> Unit>()

    fun cancelCurrentPosition(requestId: String): Boolean {
        val cancel = currentPositionCancellations.remove(requestId) ?: return false
        cancel()
        return true
    }

    /**
     * Collects fresh updates until [accuracyTarget] is reached or the deadline
     * expires. Without a target, [count] retains the legacy best-of-N contract.
     */
    private fun collectSamples(
        priority: Int,
        count: Int,
        accuracyTarget: Float?,
        requestId: String?,
        initialCandidates: List<Location>,
        timeoutSeconds: Long,
        persist: Boolean,
        extras: Map<String, Any?>,
        callback: (Map<String, Any?>?) -> Unit,
    ) {
        val collected = initialCandidates.toMutableList()
        val handler = android.os.Handler(Looper.getMainLooper())
        var acquisitionFinished = false
        var terminal = false
        var cancelled = false
        var updatesCallback: TraceletLocationCallback? = null
        var providerStarted = false
        lateinit var timeoutRunnable: Runnable
        lateinit var cancelRequest: () -> Unit

        fun complete(result: Map<String, Any?>?) {
            if (terminal) return
            terminal = true
            requestId?.let { id ->
                if (currentPositionCancellations[id] === cancelRequest) {
                    currentPositionCancellations.remove(id)
                }
            }
            callback(if (cancelled) null else result)
        }

        fun stopUpdates() {
            if (providerStarted) {
                updatesCallback?.let(fusedClient::removeLocationUpdates)
            }
        }

        fun finish(deliverResult: Boolean = true) {
            if (acquisitionFinished) return
            acquisitionFinished = true
            stopUpdates()
            if (!deliverResult) {
                complete(null)
                return
            }
            if (collected.isNotEmpty()) {
                deliver(collected, persist, extras, ::complete)
                return
            }
            val fallback = lastLocation?.takeUnless {
                config.getRejectMockLocations() && isLocationMock(it)
            }
            if (fallback != null) {
                deliver(listOf(fallback), persist, extras, ::complete)
            } else {
                complete(null)
            }
        }

        fun cancel() {
            if (terminal) return
            cancelled = true
            if (!acquisitionFinished) {
                acquisitionFinished = true
                stopUpdates()
            }
            complete(null)
        }

        timeoutRunnable = Runnable(::finish)
        cancelRequest = ::cancel
        val callbackForUpdates = object : TraceletLocationCallback {
            override fun onLocationResult(locations: List<Location>) {
                if (acquisitionFinished) return
                for (location in locations) {
                    if (config.getRejectMockLocations() && isLocationMock(location)) {
                        TraceletLog.warning("getCurrentPosition: rejected mock location sample")
                        continue
                    }
                    collected.add(location)
                    if (accuracyTarget != null && location.accuracy <= accuracyTarget) {
                        finish()
                        return
                    }
                    if (accuracyTarget == null && collected.size >= count) {
                        finish()
                        return
                    }
                }
            }

            override fun onLocationAvailability(isLocationAvailable: Boolean) = Unit
        }
        updatesCallback = callbackForUpdates
        requestId?.let { id ->
            currentPositionCancellations.remove(id)?.invoke()
            currentPositionCancellations[id] = cancelRequest
        }
        if (accuracyTarget != null &&
            collected.any { it.accuracy <= accuracyTarget }
        ) {
            finish()
            return
        }

        handler.postDelayed(timeoutRunnable, timeoutSeconds * 1000L)
        val request = TraceletLocationRequest(
            priority = priority,
            intervalMillis = 800L,
            minUpdateDistanceMeters = 0f,
        )
        providerStarted = true
        try {
            fusedClient.requestLocationUpdates(
                request,
                callbackForUpdates,
                Looper.getMainLooper(),
            )
        } catch (_: SecurityException) {
            finish()
        }
    }

    /**
     * Picks the best-accuracy location from [samples] and delivers it.
     */
    private fun deliver(
        samples: List<Location>,
        persist: Boolean,
        extras: Map<String, Any?>,
        callback: (Map<String, Any?>?) -> Unit,
    ) {
        val best = samples.minByOrNull { it.accuracy } ?: run {
            callback(null)
            return
        }
        val enriched = enrichLocation(best, "getCurrentPosition").toMutableMap()
        mergeExtras(enriched, extras)
        resolveAddressAndDispatch(best, enriched) { finalEnriched ->
            if (persist) {
                persistLocationIfAllowed(finalEnriched, "location")
                events.sendLocation(finalEnriched)
            }
            callback(finalEnriched)
        }
    }

    /**
     * Effective provider options: the temporary runtime override when one is
     * active (see [updateLocationProviderOptions]), otherwise the persisted
     * config values.
     */
    private fun effectiveDesiredAccuracy(): Int =
        runtimeDesiredAccuracy ?: budgetDesiredAccuracy ?: config.getDesiredAccuracy()

    private fun effectiveDistanceFilter(): Double =
        runtimeDistanceFilter ?: budgetDistanceFilter ?: config.getDistanceFilter()

    /**
     * The update interval, stretched while the battery-budget ladder is in
     * force (#396).
     *
     * Cadence is the knob that actually costs power on Android, which is why the
     * ladder reaches for it before it touches accuracy.
     */
    private fun effectiveUpdateInterval(): Long =
        (config.getLocationUpdateInterval() * budgetCadenceMultiplier).toLong()

    private fun buildLocationRequest(): TraceletLocationRequest {
        val priority = accuracyToPriority(effectiveDesiredAccuracy())
        val deferTime = config.getDeferTime().toLong()

        val isSpeedMode = config.getMotionDetectionMode() == com.ikolvi.tracelet.sdk.model.MotionDetectionMode.SPEED
        // High-accuracy geofence mode needs time-based delivery so a stationary
        // device still gets fixes to evaluate crossings against (0 = no distance
        // gate). Persistence volume is unaffected — the Rust processor keeps its
        // own distance filter.
        val distanceFilter = if (isSpeedMode || geofenceHighAccuracyMode) 0f else effectiveDistanceFilter().toFloat()

        return TraceletLocationRequest(
            priority = priority,
            intervalMillis = effectiveUpdateInterval(),
            minUpdateDistanceMeters = distanceFilter,
            minUpdateIntervalMillis = config.getFastestLocationUpdateInterval(),
            maxUpdateDelayMillis = if (deferTime > 0) deferTime else 0L
        )
    }

    /**
     * Replaces the active, temporary provider override without dropping the
     * tracking callback — the Android analogue of the iOS live update in
     * `LocationEngine.updateLocationProviderOptions`. Re-registering the same
     * callback replaces the fused request in place (the same mechanism
     * [activateGpsFallback]/[restoreOriginalPriority] already rely on), so
     * processor state, odometer continuity, and accepted-point filtering are
     * untouched. Passing null for both values restores the configured provider
     * options. Returns false when continuous tracking is inactive, periodic
     * mode is active, or the distance filter is invalid.
     */
    fun updateLocationProviderOptions(desiredAccuracy: Int?, distanceFilter: Double?): Boolean {
        if (!isTracking || isPeriodicTracking) return false
        if (distanceFilter != null && (!distanceFilter.isFinite() || distanceFilter < 0)) return false
        val callback = trackingCallback ?: return false

        val previousAccuracy = runtimeDesiredAccuracy
        val previousFilter = runtimeDistanceFilter
        runtimeDesiredAccuracy = desiredAccuracy
        runtimeDistanceFilter = distanceFilter

        return try {
            fusedClient.requestLocationUpdates(
                buildLocationRequestWithGpsFallback(), callback, Looper.getMainLooper()
            )
            true
        } catch (e: SecurityException) {
            // Subscription unchanged — don't leave a stored override that the
            // next rebuild would silently apply.
            runtimeDesiredAccuracy = previousAccuracy
            runtimeDistanceFilter = previousFilter
            false
        }
    }

    /**
     * Re-issues the fused request from the current settings, without touching
     * the runtime overrides [updateLocationProviderOptions] owns.
     *
     * Re-registering the same callback replaces the request in place, so
     * processor state, odometer continuity and accepted-point filtering are
     * untouched — the same mechanism [updateLocationProviderOptions] relies on.
     * Used when [geofenceHighAccuracyMode] changes mid-session (#357).
     */
    private fun reapplyProviderOptionsIfTracking() {
        if (!isTracking || isPeriodicTracking) return
        val callback = trackingCallback ?: return
        try {
            fusedClient.requestLocationUpdates(
                buildLocationRequestWithGpsFallback(), callback, Looper.getMainLooper()
            )
        } catch (e: SecurityException) {
            TraceletLog.warning(
                "Could not re-apply provider options for the geofence evaluator: ${e.message}"
            )
        }
    }

    /**
     * Builds a [LocationRequest] with automatic GPS-off fallback.
     *
     * If the configured accuracy requires GPS ([TraceletLocationPriority.PRIORITY_HIGH_ACCURACY])
     * but the GPS provider is disabled, downgrades to
     * [TraceletLocationPriority.PRIORITY_BALANCED_POWER_ACCURACY] so the fused engine delivers
     * Wi-Fi / cell-tower fixes instead of timing out.
     */
    private fun buildLocationRequestWithGpsFallback(): TraceletLocationRequest {
        val configuredPriority = accuracyToPriority(effectiveDesiredAccuracy())
        val effectivePriority = if (configuredPriority == TraceletLocationPriority.PRIORITY_HIGH_ACCURACY &&
            !isGpsProviderEnabled(context)
        ) {
            gpsFallbackActive = true
            TraceletLog.debug("GPS provider disabled — using BALANCED_POWER_ACCURACY (Wi-Fi/cell)")
            TraceletLocationPriority.PRIORITY_BALANCED_POWER_ACCURACY
        } else {
            gpsFallbackActive = false
            configuredPriority
        }

        val deferTime = config.getDeferTime().toLong()
        val isSpeedMode = config.getMotionDetectionMode() == com.ikolvi.tracelet.sdk.model.MotionDetectionMode.SPEED
        // See buildLocationRequest(): geofence high-accuracy mode delivers
        // time-based fixes so a stationary device isn't starved of crossings.
        val distanceFilter = if (isSpeedMode || geofenceHighAccuracyMode) 0f else effectiveDistanceFilter().toFloat()

        return TraceletLocationRequest(
            priority = effectivePriority,
            intervalMillis = config.getLocationUpdateInterval(),
            minUpdateDistanceMeters = distanceFilter,
            minUpdateIntervalMillis = config.getFastestLocationUpdateInterval(),
            maxUpdateDelayMillis = if (deferTime > 0) deferTime else 0L
        )
    }

    /** Returns true if the effective desired accuracy requires GPS hardware. */
    private fun isHighAccuracyConfigured(): Boolean {
        return effectiveDesiredAccuracy() == 0 // 0 = high accuracy (GPS)
    }

    /**
     * Downgrades to Wi-Fi/cell priority while keeping the existing tracking
     * callback. Re-subscribes with [PRIORITY_BALANCED_POWER_ACCURACY].
     */
    private fun activateGpsFallback() {
        if (gpsFallbackActive) return
        gpsFallbackActive = true

        val callback = trackingCallback ?: return
        val fallbackRequest = TraceletLocationRequest(
            priority = TraceletLocationPriority.PRIORITY_BALANCED_POWER_ACCURACY,
            intervalMillis = config.getLocationUpdateInterval(),
            minUpdateDistanceMeters = effectiveDistanceFilter().toFloat(),
            minUpdateIntervalMillis = config.getFastestLocationUpdateInterval()
        )

        try {
            // Re-subscribe with lower priority (replaces existing request).
            fusedClient.requestLocationUpdates(fallbackRequest, callback, Looper.getMainLooper())
            TraceletLog.debug("GPS fallback active — now using Wi-Fi/cell positioning")
            val providerState = buildProviderState().toMutableMap()
            providerState["gpsFallback"] = true
            events.sendProviderChange(providerState)
        } catch (_: SecurityException) { /* permission lost */ }
    }

    /**
     * Restores the original configured priority after GPS is re-enabled.
     * Re-subscribes with the user's configured accuracy.
     */
    private fun restoreOriginalPriority() {
        if (!gpsFallbackActive) return
        gpsFallbackActive = false

        val callback = trackingCallback ?: return
        val originalRequest = buildLocationRequest()

        try {
            fusedClient.requestLocationUpdates(originalRequest, callback, Looper.getMainLooper())
            TraceletLog.debug("GPS restored — using original priority")
            val providerState = buildProviderState().toMutableMap()
            providerState["gpsFallback"] = false
            events.sendProviderChange(providerState)
        } catch (_: SecurityException) { /* permission lost */ }
    }

    private fun accuracyToPriority(accuracy: Int): Int {
        return when (accuracy) {
            0 -> TraceletLocationPriority.PRIORITY_HIGH_ACCURACY       // high
            1 -> TraceletLocationPriority.PRIORITY_BALANCED_POWER_ACCURACY // medium
            2 -> TraceletLocationPriority.PRIORITY_LOW_POWER            // low
            3 -> TraceletLocationPriority.PRIORITY_PASSIVE              // veryLow
            4 -> TraceletLocationPriority.PRIORITY_PASSIVE              // passive
            else -> TraceletLocationPriority.PRIORITY_HIGH_ACCURACY
        }
    }

    private fun hasPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED ||
                ContextCompat.checkSelfPermission(
                    context, Manifest.permission.ACCESS_COARSE_LOCATION
                ) == PackageManager.PERMISSION_GRANTED
    }

    /**
     * Returns `true` if the app holds ACCESS_BACKGROUND_LOCATION (API 29+).
     * On API < 29, foreground permission implies background access.
     */
    fun hasBackgroundPermission(): Boolean {
        if (!hasPermission()) return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ContextCompat.checkSelfPermission(
                context, Manifest.permission.ACCESS_BACKGROUND_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true // Pre-Q: foreground grant implies background
        }
    }

    /**
     * Persists a location to the database only if allowed by persistMode.
     *
     * Retention pruning (`maxDaysToPersist` / `maxRecordsToPersist`) is applied by
     * `TraceletSdk.enforceRetentionCaps`, at the DB insert itself — this is only
     * one of the paths that reaches it (#361).
     *
     * persistMode: 0 = all, 1 = location only, 2 = geofence only, 3 = none
     */
    private fun persistLocationIfAllowed(location: Map<String, Any?>, event: String) {
        val persistMode = config.getPersistMode()
        // Mode 3 = none, Mode 2 = geofence only → skip location inserts
        if (persistMode == 3 || persistMode == 2) return
        // Mode 1 = location only → fine for location events
        // Skip provider change records if disabled
        if (event == "providerchange" && config.getDisableProviderChangeRecord()) return

        // Route through Native Sinks for DB persistence + auto HTTP sync
        sinks.forEach { it.insertLocation(location) }

        // Notify callback so auto-sync can fire
        onLocationPersisted?.invoke()
    }

    /**
     * Detects whether a [Location] was produced by a mock/spoofing provider.
     *
     * Detection level is controlled by `mockDetectionLevel` in config:
     * - **0 (disabled)**: Always returns `false`.
     * - **1 (basic)**: Uses `Location.isMock()` (API 31+) or
     *   `Location.isFromMockProvider()` (API 18–30).
     * - **2 (heuristic)**: Basic + satellite count check + elapsed realtime
     *   drift check.
     *
     * **Note:** On rooted devices with Xposed/Magisk modules, platform flags
     * can be stripped. Heuristic checks partially compensate for this.
     */
    private fun isLocationMock(location: Location): Boolean =
        isLocationMock(location, config.getMockDetectionLevel(), config.getDeferTime(), context)

    // =========================================================================
    // Dead Reckoning (Enterprise) — IMU sensor fusion
    // =========================================================================

    /**
     * Get the current dead reckoning state.
     *
     * Returns null when dead reckoning is not active (GPS available or
     * feature is disabled). When active, returns a map with:
     * - "active" (Boolean) — true if DR is currently estimating position
     * - "elapsed" (Int) — seconds since DR was activated
     * - "estimatedAccuracy" (Double) — estimated position accuracy in meters
     */
    fun getDeadReckoningState(): Map<String, Any?>? {
        return deadReckoningEngine?.getState()
    }

    /**
     * Starts the GPS-loss timer. After [deadReckoningActivationDelay] seconds
     * without a GPS fix, dead reckoning activates automatically.
     */
    private fun startGpsLossTimer() {
        if (!config.getEnableDeadReckoning()) return
        cancelGpsLossTimer()

        val delayMs = config.getDeadReckoningActivationDelay() * 1000L
        TraceletLog.debug("DR: GPS-loss timer started (${delayMs}ms)")
        gpsLossRunnable = Runnable { activateDeadReckoning() }
        drHandler.postDelayed(gpsLossRunnable!!, delayMs)
    }

    /** Resets the GPS-loss timer (called on each GPS fix). */
    private fun resetGpsLossTimer() {
        if (!config.getEnableDeadReckoning()) return
        cancelGpsLossTimer()
        startGpsLossTimer()
    }

    private fun cancelGpsLossTimer() {
        gpsLossRunnable?.let { drHandler.removeCallbacks(it) }
        gpsLossRunnable = null
    }

    /** Activates dead reckoning from the last known GPS position. */
    private fun activateDeadReckoning() {
        val last = lastLocation
        if (last == null) {
            TraceletLog.warning("DR: Cannot activate — no last known location")
            // Restart timer so we try again once a location arrives.
            startGpsLossTimer()
            return
        }
        TraceletLog.debug("DR: GPS lost for ${config.getDeadReckoningActivationDelay()}s — activating (last=${last.latitude},${last.longitude} acc=${last.accuracy})")

        val engine = DeadReckoningEngine(context, config)
        engine.onEstimatedLocation = { drLocation -> onDrLocationEstimated(drLocation) }
        engine.onDeactivated = {
            TraceletLog.debug("Dead reckoning auto-stopped (max duration)")
        }
        engine.activate(
            lat = last.latitude,
            lng = last.longitude,
            altitude = last.altitude,
            heading = last.bearing.toDouble(),
            activity = currentActivityType,
        )
        deadReckoningEngine = engine
    }

    /** Deactivates dead reckoning. */
    private fun deactivateDeadReckoning() {
        deadReckoningEngine?.deactivate()
        deadReckoningEngine = null
    }

    /**
     * Processes a dead-reckoned location estimate.
     * Enriches it into the standard location format and dispatches it.
     */
    private fun onDrLocationEstimated(drLocation: Map<String, Any?>) {
        val lat = drLocation["latitude"] as? Double ?: return
        val lng = drLocation["longitude"] as? Double ?: return
        val altitude = drLocation["altitude"] as? Double ?: 0.0
        val heading = drLocation["heading"] as? Double ?: 0.0
        val accuracy = drLocation["accuracy"] as? Double ?: 50.0
        val speed = drLocation["speed"] as? Double ?: 0.0

        val timestamp = isoFormatter.format(Date())
        val battery = BatteryUtils.getBatteryInfo(context)

        val enriched = mutableMapOf<String, Any?>(
            "uuid" to UUID.randomUUID().toString(),
            "timestamp" to timestamp,
            "is_moving" to state.isMoving,
            "odometer" to state.odometer,
            "event" to "dead_reckoning",
            "mock" to false,
            "isDeadReckoned" to true,
            "coords" to mapOf(
                "latitude" to lat,
                "longitude" to lng,
                "altitude" to altitude,
                "speed" to speed,
                "heading" to heading,
                "accuracy" to accuracy,
                "speedAccuracy" to -1.0,
                "headingAccuracy" to -1.0,
                "altitudeAccuracy" to -1.0,
            ),
            "activity" to mapOf(
                // #214 pt3: persist the fused transport mode when authoritative so
                // it survives termination and syncs historically (falls back to AR).
                "type" to effectiveActivityType(),
                "confidence" to effectiveActivityConfidence(),
            ),
            "battery" to battery,
        )

        // Persist and dispatch
        persistLocationIfAllowed(enriched, "dead_reckoning")
        events.sendLocation(enriched)
    }

    // =========================================================================
    // Activity type mapping helpers (Android string → Rust enum)
    // =========================================================================

    private fun mapActivityType(type: String): RustActivityType {
        return when (type.lowercase()) {
            "still" -> RustActivityType.STILL
            "walking" -> RustActivityType.WALKING
            "running" -> RustActivityType.RUNNING
            "on_foot" -> RustActivityType.ON_FOOT
            "in_vehicle" -> RustActivityType.IN_VEHICLE
            "on_bicycle" -> RustActivityType.ON_BICYCLE
            else -> RustActivityType.UNKNOWN
        }
    }

    private fun mapActivityConfidence(confidence: Int): RustActivityConfidence {
        return when {
            confidence >= 75 -> RustActivityConfidence.HIGH
            confidence >= 50 -> RustActivityConfidence.MEDIUM
            else -> RustActivityConfidence.LOW
        }
    }
    
    private fun resolveAddressAndDispatch(
        location: Location,
        enriched: Map<String, Any?>,
        dispatch: (Map<String, Any?>) -> Unit
    ) {
        val resolveEnabled = config.getResolveAddress()
        val geocoderPresent = android.location.Geocoder.isPresent()
        TraceletLog.verbose("resolveAddressAndDispatch: resolveAddressConfig=$resolveEnabled, geocoderPresent=$geocoderPresent")
        
        if (resolveEnabled && geocoderPresent) {
            TraceletLog.verbose("resolveAddressAndDispatch: Starting reverse geocode lookup for lat=${location.latitude}, lng=${location.longitude} on background thread.")
            java.util.concurrent.Executors.newSingleThreadExecutor().execute {
                try {
                    val geocoder = android.location.Geocoder(context, java.util.Locale.getDefault())
                    val addresses = geocoder.getFromLocation(location.latitude, location.longitude, 1)
                    
                    if (!addresses.isNullOrEmpty()) {
                        TraceletLog.verbose("resolveAddressAndDispatch: Geocoder returned ${addresses.size} addresses.")
                        val addr = addresses[0]
                        TraceletLog.verbose("resolveAddressAndDispatch: First address: $addr")
                        
                        val addressMap = mutableMapOf<String, Any?>()
                        addr.thoroughfare?.let { addressMap["street"] = it }
                        addr.locality?.let { addressMap["city"] = it }
                        addr.adminArea?.let { addressMap["state"] = it }
                        addr.postalCode?.let { addressMap["postalCode"] = it }
                        addr.countryName?.let { addressMap["country"] = it }
                        if (addressMap.isEmpty() && addr.featureName != null) {
                            addressMap["street"] = addr.featureName
                        }
                        
                        TraceletLog.verbose("resolveAddressAndDispatch: Parsed addressMap: $addressMap")
                        
                        val mutableEnriched = enriched.toMutableMap()
                        if (addressMap.isNotEmpty()) mutableEnriched["address"] = addressMap
                        
                        android.os.Handler(android.os.Looper.getMainLooper()).post { dispatch(mutableEnriched) }
                    } else {
                        TraceletLog.warning("resolveAddressAndDispatch: Geocoder returned empty address list for lat=${location.latitude}, lng=${location.longitude}")
                        android.os.Handler(android.os.Looper.getMainLooper()).post { dispatch(enriched) }
                    }
                } catch (e: java.lang.Exception) {
                    TraceletLog.error("resolveAddressAndDispatch: Exception during reverse geocoding", e)
                    android.os.Handler(android.os.Looper.getMainLooper()).post { dispatch(enriched) }
                }
            }
        } else {
            TraceletLog.verbose("resolveAddressAndDispatch: Skipping geocoding. resolveAddressConfig=$resolveEnabled, geocoderPresent=$geocoderPresent")
            dispatch(enriched)
        }
    }
}

/**
 * Detects whether a [Location] was produced by a mock/spoofing provider.
 *
 * Top-level so it is shared by [LocationEngine] and [PeriodicLocationWorker]
 * (which has no engine instance in its background process).
 *
 * Detection [level] (from `mockDetectionLevel` in config):
 * - **0 (disabled)**: Always returns `false`.
 * - **1 (basic)**: Uses `Location.isMock()` (API 31+) or
 *   `Location.isFromMockProvider()` (API 18–30).
 * - **2 (heuristic)**: Basic + satellite count check + elapsed realtime
 *   drift check. [deferTimeMs] widens the timestamp-mismatch tolerance for
 *   batched delivery.
 *
 * **Note:** On rooted devices with Xposed/Magisk modules, platform flags
 * can be stripped. Heuristic checks partially compensate for this.
 */
@Suppress("DEPRECATION")
internal fun isLocationMock(location: Location, level: Int, deferTimeMs: Int, context: Context): Boolean {
    if (level == 0) return false

    // Level 1+ (basic): Platform API flag
    val platformFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        location.isMock
    } else {
        location.isFromMockProvider
    }

    TraceletLog.verbose("isLocationMock: platformFlag=$platformFlag, level=$level")

    if (platformFlag) return true
    if (level < 2) return false

    // Level 2 (heuristic): Additional native-side checks
    val gpsEnabled = LocationEngine.isGpsProviderEnabled(context)
    val extras = location.extras
    val satellites = extras?.getInt("satellites", -1) ?: -1

    TraceletLog.verbose("isLocationMock: heuristic check — satellites=$satellites, gpsEnabled=$gpsEnabled, accuracy=${location.accuracy}")

    if (gpsEnabled && satellites == 0 && location.accuracy < 50.0) {
        TraceletLog.debug("isLocationMock: detected via 0 satellites")
        return true
    }

    val locationElapsedNanos = location.elapsedRealtimeNanos
    val currentElapsedNanos = SystemClock.elapsedRealtimeNanos()
    val driftNanos = currentElapsedNanos - locationElapsedNanos
    val driftMs = driftNanos / 1_000_000.0

    TraceletLog.verbose("isLocationMock: driftMs=$driftMs ms")

    if (driftMs < -500.0) {
        TraceletLog.debug("isLocationMock: detected via negative elapsedRealtime drift (location from the future: $driftMs ms)")
        return true
    }

    // 3. Timestamp vs ElapsedRealtime mismatch
    val locationTimeMs = location.time
    val currentTimeMs = System.currentTimeMillis()
    val ageByWallClockMs = currentTimeMs - locationTimeMs
    val ageByMonotonicMs = driftMs.toLong()

    // If the location age according to the monotonic clock differs significantly
    // from the wall clock age (e.g., > 10 seconds), the location was likely replayed
    // or the elapsedRealtime was manipulated (common in mock location apps).
    val discrepancyMs = kotlin.math.abs(ageByWallClockMs - ageByMonotonicMs)
    val maxDriftMs = 10000L + deferTimeMs
    TraceletLog.verbose("isLocationMock: discrepancyMs=$discrepancyMs ms, maxDriftMs=$maxDriftMs ms")
    if (discrepancyMs > maxDriftMs) {
        TraceletLog.debug("isLocationMock: detected via timestamp/elapsed mismatch (>10s)")
        return true
    }

    return false
}
