package com.ikolvi.tracelet.sdk.motion

import android.content.Context
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.TraceletEventSender
import com.ikolvi.tracelet.sdk.location.LocationEngine
import com.ikolvi.tracelet.sdk.service.LocationService
import com.ikolvi.tracelet.sdk.location.PeriodicLocationWorker
import com.ikolvi.tracelet.sdk.model.TrackingMode
import com.ikolvi.tracelet.sdk.StateManager
import com.ikolvi.tracelet.sdk.util.TraceletLogger

/**
 * Coordinates between MotionDetector (Accelerometer/ActivityRecognition) and
 * SpeedMotionManager (GPS Speed) to implement the 'smart' MotionDetectionMode.
 *
 * Implements a Logical OR:
 * If EITHER sensor detects motion, the app stays in continuous tracking mode.
 * If BOTH sensors detect stationary, the app stops continuous tracking and relies
 * on Geofences/periodic wakeups to save battery.
 */
class SmartMotionCoordinator(
    private val context: Context,
    private val configManager: ConfigManager,
    private val stateManager: StateManager,
    var events: TraceletEventSender,
    private val locationEngine: LocationEngine,
    private val motionDetector: MotionDetector,
    private val logger: TraceletLogger,
) {
    private val coreCoordinator = uniffi.tracelet_core.SmartMotionCoordinator(
        configManager.getStationaryTrackingMode() == com.ikolvi.tracelet.sdk.model.StationaryTrackingMode.GEOFENCES
    )

    val isAccelMoving: Boolean
        get() = coreCoordinator.isAccelMoving()

    val isSpeedMoving: Boolean
        get() = coreCoordinator.isSpeedMoving()

    /**
     * Called when the accelerometer/activity recognition state changes.
     * Returns the action taken by the coordinator so the caller can
     * conditionally reset the speed state machine on real wake-ups.
     */
    fun onAccelStateChange(isMoving: Boolean): uniffi.tracelet_core.CoordinatorAction {
        val action = coreCoordinator.onAccelStateChange(isMoving)
        logger.debug("SmartMotionCoordinator: onAccelStateChange -> isMoving=$isMoving, action=$action, isAccelMoving=${coreCoordinator.isAccelMoving()}, isSpeedMoving=${coreCoordinator.isSpeedMoving()}")
        handleAction(action)
        return action
    }

    /**
     * The last speed this process actually resolved, or `null` if it has not
     * resolved one yet.
     *
     * [LocationEngine.lastEffectiveSpeed] and `lastLocation` are written
     * together on every accepted fix, so a null location is exactly "no fix has
     * been accepted in this process" — which is *unknown*, not zero.
     */
    private val resolvedSpeed: Double?
        get() = locationEngine.getLastLocation()?.let { locationEngine.lastEffectiveSpeed }

    /**
     * Called when the GPS speed state changes.
     */
    fun onSpeedStateChange(isMoving: Boolean) {
        if (!isMoving && coreCoordinator.isAccelMoving()) {
            // Speed SM declared stationary (30s of speed < 1.5 m/s) but accel
            // still reports moving. This could be:
            //   a) Hand tremor while physically still (GPS speed ≈ 0 m/s)
            //   b) Walking slowly (GPS speed 0.3-0.5 m/s, below speed threshold)
            // Only override accel for case (a) — truly near-zero GPS speed.
            // For case (b), trust the accelerometer: the user IS moving.
            //
            // #333: this used to read the raw `Location.speed`, which reports
            // 0.0 on a fix that carries no speed at all, so an unknown speed
            // passed the near-zero test and overruled a positive motion signal
            // on missing data. `lastEffectiveSpeed` is the resolved value — it
            // falls back to a distance/time derivation exactly when the platform
            // reading is absent — and no resolved speed at all now leaves the
            // accelerometer standing rather than silently siding against it.
            val lastSpeed = resolvedSpeed
            when {
                lastSpeed == null ->
                    logger.info("SmartMotionCoordinator: no GPS speed resolved yet — trusting accel, staying continuous.")
                lastSpeed <= TREMOR_SPEED_THRESHOLD -> {
                    logger.info("SmartMotionCoordinator: GPS speed near zero ($lastSpeed m/s) but accel moving — overriding accel to false (hand tremor).")
                    coreCoordinator.onAccelStateChange(false)
                }
                else ->
                    logger.info("SmartMotionCoordinator: GPS speed $lastSpeed m/s is above the $TREMOR_SPEED_THRESHOLD m/s tremor threshold — trusting accel, staying continuous.")
            }
        }
        val action = coreCoordinator.onSpeedStateChange(isMoving)
        logger.debug("SmartMotionCoordinator: onSpeedStateChange -> isMoving=$isMoving, action=$action, isAccelMoving=${coreCoordinator.isAccelMoving()}, isSpeedMoving=${coreCoordinator.isSpeedMoving()}")
        handleAction(action)
    }

    /**
     * Called when the user manually forces the pace via changePace().
     */
    fun onManualPaceChange(isMoving: Boolean) {
        val accelAction = coreCoordinator.onAccelStateChange(isMoving)
        handleAction(accelAction)
        
        val speedAction = coreCoordinator.onSpeedStateChange(isMoving)
        handleAction(speedAction)
    }
    
    /**
     * Synchronize the Rust core mode with the native StateManager on startup or mode change.
     *
     * `stateManager.trackingMode` and the coordinator's `currentMode` measure
     * different things, and conflating them wedged the coordinator (#344):
     *
     * * `trackingMode` is the **session** mode — which start API was called. It
     *   is set to CONTINUOUS by `start()` and stays there for the whole session;
     *   the stationary switch records the pace in `stateManager.isMoving`.
     * * `currentMode` is the **posture** — whether the engine is running
     *   continuous location updates right now or is parked in a stationary
     *   schedule.
     *
     * `start()` sets `isMoving` from `motion.isMoving` (false by default) and
     * then calls this, so mapping CONTINUOUS -> CONTINUOUS wrote CONTINUOUS into
     * a coordinator whose inputs both said stationary. The core's
     * `evaluate_state` emits no action for that pair in either direction: a
     * moving accelerometer sees `currentMode == CONTINUOUS` and returns None, so
     * the session stayed parked — no fixes recorded, nothing to sync — until the
     * process was killed. Reading the posture off `isMoving` keeps the two in
     * step, and the first real accel or speed event produces the wake-up.
     *
     * #409 is the same wedge from the other side: `isMoving` false with a *live*
     * stream parked the coordinator while the engine kept streaming, and
     * `evaluate_state` returns None for that pair too. The posture is now the OR
     * of the committed pace and the engine's actual state — the only reading
     * that survives both directions.
     */
    fun syncCurrentMode() {
        val useGeofences = configManager.getStationaryTrackingMode() ==
            com.ikolvi.tracelet.sdk.model.StationaryTrackingMode.GEOFENCES
        val stationaryMode = if (useGeofences) {
            uniffi.tracelet_core.TrackingMode.STATIONARY_GEOFENCES
        } else {
            uniffi.tracelet_core.TrackingMode.STATIONARY_PERIODIC
        }
        val mode = when (stateManager.trackingMode) {
            TrackingMode.CONTINUOUS ->
                // `isMoving` predicts what start() is *about* to do; `isTracking`
                // reports what the engine is doing *now*. Either alone gets a case
                // wrong, so the posture is the OR of them (#409).
                //
                // `isMoving` alone was the wedge. start() syncs before it touches
                // the engine, so a session resuming stationary while a stream was
                // still live — a ready() takeover after the boot engine handed
                // over — wrote StationaryPeriodic into a coordinator whose engine
                // was streaming. evaluate_state only emits the stop action when it
                // believes the mode is Continuous, so every later stationary
                // decision returned None and the stream ran at the configured
                // interval for the rest of the session, on a device the SDK
                // correctly reported as parked.
                //
                // `isTracking` alone breaks the other direction: this runs before
                // start() starts the engine, so a moving start would sync
                // stationary and then stream — the same wedge, mirrored.
                if (stateManager.isMoving || locationEngine.isTracking) {
                    uniffi.tracelet_core.TrackingMode.CONTINUOUS
                } else {
                    stationaryMode
                }
            TrackingMode.GEOFENCES -> uniffi.tracelet_core.TrackingMode.STATIONARY_GEOFENCES
            TrackingMode.PERIODIC -> uniffi.tracelet_core.TrackingMode.STATIONARY_PERIODIC
            else -> uniffi.tracelet_core.TrackingMode.CONTINUOUS
        }
        coreCoordinator.setCurrentMode(mode)
        coreCoordinator.setUseGeofencesWhenStationary(useGeofences)
    }

    /**
     * Records a tracking-mode switch on the always-on lifecycle channel, naming
     * both inputs of the OR (#334).
     *
     * The coordinator is a logical OR of the accelerometer and the GPS-speed
     * machine, so a downgrade means *both* said stationary. Which one flipped
     * last — and what the other was doing at the time — is the first question
     * asked of any "it stopped tracking while I was moving" report, and at the
     * shipped log levels the answer was not recorded anywhere.
     */
    private fun recordModeSwitch(mode: String) {
        val speedText = resolvedSpeed?.toString() ?: "unknown"
        com.ikolvi.tracelet.sdk.util.TraceletLog.lifecycle(
            "smart-motion: switching to $mode — accelMoving=${coreCoordinator.isAccelMoving()} " +
                "speedMoving=${coreCoordinator.isSpeedMoving()} lastSpeed=${speedText}m/s",
        )
    }

    private fun handleAction(action: uniffi.tracelet_core.CoordinatorAction) {
        when (action) {
            uniffi.tracelet_core.CoordinatorAction.SWITCH_TO_CONTINUOUS -> {
                recordModeSwitch("CONTINUOUS")
                val useForeground = configManager.isForegroundServiceEnabled()
                logger.debug("SmartMotionCoordinator: SWITCH_TO_CONTINUOUS — useForeground=$useForeground")
                if (useForeground) {
                    LocationService.switchToContinuous(locationEngine, stateManager)
                } else {
                    PeriodicLocationWorker.cancel(context)
                    locationEngine.start()
                }
                stateManager.isMoving = true
                logger.debug("SmartMotionCoordinator: SWITCH_TO_CONTINUOUS — calling motionDetector.onManualPaceChange(true)")
                motionDetector.onManualPaceChange(true)
                
                // Dispatch motionchange event
                val locationMap = locationEngine.getLastLocation()?.let {
                    locationEngine.enrichLocation(it, "motionchange")
                } ?: mapOf("is_moving" to true)
                events.sendMotionChange(locationMap)
            }
            uniffi.tracelet_core.CoordinatorAction.SWITCH_TO_STATIONARY_GEOFENCES -> {
                recordModeSwitch("STATIONARY_GEOFENCES")
                val useForeground = configManager.isForegroundServiceEnabled()
                if (useForeground) {
                    LocationService.switchToStationaryGeofences(locationEngine, stateManager, configManager)
                } else {
                    if (configManager.getGeofenceModeHighAccuracy()) {
                        locationEngine.start()
                    } else {
                        locationEngine.stop()
                    }
                }
                stateManager.isMoving = false
                motionDetector.onManualPaceChange(false)
                
                val locationMap = locationEngine.getLastLocation()?.let {
                    locationEngine.enrichLocation(it, "motionchange")
                } ?: mapOf("is_moving" to false)
                events.sendMotionChange(locationMap)
            }
            uniffi.tracelet_core.CoordinatorAction.SWITCH_TO_STATIONARY_PERIODIC -> {
                recordModeSwitch("STATIONARY_PERIODIC")
                val useForeground = configManager.isForegroundServiceEnabled()
                logger.debug("SmartMotionCoordinator: SWITCH_TO_STATIONARY_PERIODIC — useForeground=$useForeground")
                if (useForeground) {
                    LocationService.switchToStationaryPeriodic(locationEngine, configManager, stateManager)
                } else {
                    locationEngine.stop()
                    val lastLoc = locationEngine.getLastLocation()
                    if (lastLoc != null) {
                        stateManager.lastPeriodicLatitude = lastLoc.latitude
                        stateManager.lastPeriodicLongitude = lastLoc.longitude
                        stateManager.lastLocationTime = lastLoc.time
                    }
                    val interval = configManager.getStationaryPeriodicInterval()
                    
                    val useExactAlarms = configManager.getPeriodicUseExactAlarms() || interval < 900
                    if (useExactAlarms) {
                        PeriodicLocationWorker.scheduleOneTime(context)
                        PeriodicLocationWorker.scheduleExactAlarm(context, interval)
                    } else {
                        PeriodicLocationWorker.schedule(context, interval)
                    }
                }
                stateManager.isMoving = false
                logger.debug("SmartMotionCoordinator: SWITCH_TO_STATIONARY_PERIODIC — calling motionDetector.onManualPaceChange(false)")
                motionDetector.onManualPaceChange(false)
                
                val locationMap = locationEngine.getLastLocation()?.let {
                    locationEngine.enrichLocation(it, "motionchange")
                } ?: mapOf("is_moving" to false)
                events.sendMotionChange(locationMap)
            }
            uniffi.tracelet_core.CoordinatorAction.NONE -> {
                // Do nothing
            }
        }
    }

    private companion object {
        /**
         * GPS speed at or below which a *moving* accelerometer is read as hand
         * tremor on a physically still device rather than as real motion.
         */
        const val TREMOR_SPEED_THRESHOLD = 0.15
    }
}
