package com.ikolvi.tracelet.sdk.receiver
import com.ikolvi.tracelet.sdk.util.TraceletLog

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.TraceletSdk
import com.ikolvi.tracelet.sdk.model.MotionDetectionMode
import com.ikolvi.tracelet.sdk.model.SpeedMotionState
import com.ikolvi.tracelet.sdk.model.StationaryTrackingMode
import com.ikolvi.tracelet.sdk.model.TrackingMode
import com.ikolvi.tracelet.sdk.service.LocationService

/**
 * Static manifest-declared receiver for Activity Recognition Transition updates.
 *
 * Guarantees that Google Play Services transition events are delivered and processed
 * even when the app is backgrounded, sleeping, or in Doze/standby mode, completely
 * bypassing standard background dynamic receiver constraints.
 */
class ActivityTransitionReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "ActivityTransitionRcvr"
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent == null || context == null) return
        TraceletLog.debug("onReceive: Activity transition broadcast received")

        try {
            val sdk = TraceletSdk.getInstance(context)
            if (sdk.isReady) {
                TraceletLog.debug("Forwarding transition event to active SDK MotionDetector")
                sdk.motionDetector.handleTransitionIntent(intent)
            } else {
                TraceletLog.debug("SDK not ready — attempting to route transition event to boot-mode MotionDetector")
                val bootMotionDetector = LocationService.bootMotionDetector
                if (bootMotionDetector != null) {
                    bootMotionDetector.handleTransitionIntent(intent)
                } else {
                    TraceletLog.warning("No active or boot-mode MotionDetector found to handle transition")
                    val state = com.ikolvi.tracelet.sdk.StateManager(context)
                    if (state.enabled) {
                        val extractor = com.ikolvi.tracelet.sdk.wrapper.TraceletServices.getInstance(context).getEventExtractor()
                        val result = extractor.extractActivityTransitionResult(intent)
                        if (result != null) {
                            val configManager = ConfigManager.getInstance(context)
                            val keepStationaryStream = configManager.getStationaryTrackingMode() ==
                                StationaryTrackingMode.CONTINUOUS &&
                                state.sessionTrackingMode == TrackingMode.CONTINUOUS &&
                                configManager.getMotionDetectionMode() != MotionDetectionMode.ACCELEROMETER
                            for (event in result.transitionEvents) {
                                // 0 = ENTER, 3 = STILL
                                if (event.transitionType == 0) {
                                    if (event.activityType != 3) {
                                        if (state.trackingMode == TrackingMode.PERIODIC ||
                                            (keepStationaryStream && !state.isMoving)
                                        ) {
                                            TraceletLog.debug("Detected moving transition while killed and stationary — waking up SDK!")
                                            state.isMoving = true
                                            if (keepStationaryStream) state.speedMotionState = SpeedMotionState.MOVING
                                            state.trackingMode = TrackingMode.CONTINUOUS
                                            if (!keepStationaryStream || configManager.isForegroundServiceEnabled()) {
                                                LocationService.startFromBoot(context)
                                            }
                                            break
                                        }
                                    } else {
                                        if (state.trackingMode == TrackingMode.CONTINUOUS) {
                                            TraceletLog.debug("Detected STILL transition while in killed continuous mode — switching to stationary!")
                                            state.isMoving = false
                                            val useForeground = configManager.isForegroundServiceEnabled()
                                            
                                            if (configManager.getStationaryTrackingMode() == StationaryTrackingMode.GEOFENCES) {
                                                state.trackingMode = TrackingMode.GEOFENCES
                                            } else if (!keepStationaryStream) {
                                                state.trackingMode = TrackingMode.PERIODIC
                                                val interval = configManager.getStationaryPeriodicInterval()
                                                val useExactAlarms = configManager.getPeriodicUseExactAlarms() || interval < 900
                                                if (useExactAlarms) {
                                                    com.ikolvi.tracelet.sdk.location.PeriodicLocationWorker.scheduleOneTime(context)
                                                    com.ikolvi.tracelet.sdk.location.PeriodicLocationWorker.scheduleExactAlarm(context, interval)
                                                } else {
                                                    com.ikolvi.tracelet.sdk.location.PeriodicLocationWorker.schedule(context, interval)
                                                }
                                            }
                                            
                                            if (useForeground) {
                                                LocationService.startFromBoot(context)
                                            }
                                            break
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch (e: Exception) {
            TraceletLog.error("Error processing activity transition: ${e.message}", e)
        }
    }
}
