package com.ikolvi.tracelet.sdk.algorithm

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sqrt

/**
 * 2D Extended Kalman Filter for GPS coordinate smoothing.
 *
 * Uses latitude/longitude in meters (via equirectangular projection) with
 * the device-reported GPS accuracy as measurement noise. Produces smoother
 * tracks, better speed estimates, and eliminates GPS jitter.
 *
 * Mirrors the Dart `KalmanLocationFilter` class.
 */
class KalmanLocationFilter {

    // State vector: [x, y, vx, vy] in meters from an arbitrary origin.
    private var x = 0.0   // position x (meters, east)
    private var y = 0.0   // position y (meters, north)
    private var vx = 0.0  // velocity x (m/s)
    private var vy = 0.0  // velocity y (m/s)

    // 4×4 covariance matrix stored as a flat 16-element array.
    private val p = DoubleArray(16)

    // Scratch buffer for covariance snapshots.
    private val pTemp = DoubleArray(16)

    // Conversion factors.
    private var originLat = 0.0
    private var originLng = 0.0
    private var metersPerDegreeLat = 111320.0
    private var metersPerDegreeLng = 111320.0

    private var lastTimestampMs = 0L

    /** Whether the filter has been initialized with at least one measurement. */
    var isInitialized = false
        private set

    /** The current estimated speed in m/s derived from the state vector. */
    val estimatedSpeed: Double
        get() = sqrt(vx * vx + vy * vy)

    /**
     * Process a new GPS measurement and return the smoothed coordinates.
     *
     * @param latitude Raw GPS latitude in degrees.
     * @param longitude Raw GPS longitude in degrees.
     * @param accuracy GPS horizontal accuracy in meters.
     * @param timestampMs Location timestamp in milliseconds since epoch.
     * @return Smoothed `Pair<latitude, longitude>` in degrees.
     */
    fun process(
        latitude: Double,
        longitude: Double,
        accuracy: Double,
        timestampMs: Long
    ): Pair<Double, Double> {
        val measAccuracy = accuracy.coerceAtLeast(1.0)

        if (!isInitialized) {
            initialize(latitude, longitude, measAccuracy, timestampMs)
            return Pair(latitude, longitude)
        }

        val dt = (timestampMs - lastTimestampMs) / 1000.0
        if (dt <= 0) return toLatLng()
        lastTimestampMs = timestampMs

        val mx = (longitude - originLng) * metersPerDegreeLng
        val my = (latitude - originLat) * metersPerDegreeLat

        predict(dt)
        update(mx, my, measAccuracy)

        return toLatLng()
    }

    /** Reset the filter state. Call when tracking restarts. */
    fun reset() {
        isInitialized = false
        lastTimestampMs = 0
        x = 0.0; y = 0.0; vx = 0.0; vy = 0.0
        p.fill(0.0)
    }

    // ─── Private ─────────────────────────────────────────────────────────

    private fun initialize(lat: Double, lng: Double, accuracy: Double, ts: Long) {
        originLat = lat
        originLng = lng
        metersPerDegreeLat = 111320.0
        metersPerDegreeLng = 111320.0 * cos(lat * PI / 180.0)

        x = 0.0; y = 0.0; vx = 0.0; vy = 0.0
        lastTimestampMs = ts
        isInitialized = true

        p.fill(0.0)
        p[0] = accuracy * accuracy   // position x variance
        p[5] = accuracy * accuracy   // position y variance
        p[10] = 100.0                // velocity x variance
        p[15] = 100.0                // velocity y variance
    }

    private fun predict(dt: Double) {
        x += vx * dt
        y += vy * dt

        val q = PROCESS_NOISE * PROCESS_NOISE
        val dt2 = dt * dt
        val dt3 = dt2 * dt / 2.0
        val dt4 = dt2 * dt2 / 4.0

        System.arraycopy(p, 0, pTemp, 0, 16)
        val t = pTemp
        p[0]  = t[0]  + dt * (t[2]  + t[8])  + dt2 * t[10] + q * dt4
        p[1]  = t[1]  + dt * (t[3]  + t[9])  + dt2 * t[11]
        p[2]  = t[2]  + dt * t[10] + q * dt3
        p[3]  = t[3]  + dt * t[11]
        p[4]  = t[4]  + dt * (t[6]  + t[12]) + dt2 * t[14]
        p[5]  = t[5]  + dt * (t[7]  + t[13]) + dt2 * t[15] + q * dt4
        p[6]  = t[6]  + dt * t[14]
        p[7]  = t[7]  + dt * t[15] + q * dt3
        p[8]  = t[8]  + dt * t[10] + q * dt3
        p[9]  = t[9]  + dt * t[11]
        p[10] = t[10] + q * dt2
        p[11] = t[11]
        p[12] = t[12] + dt * t[14]
        p[13] = t[13] + dt * t[15] + q * dt3
        p[14] = t[14]
        p[15] = t[15] + q * dt2
    }

    private fun update(mx: Double, my: Double, accuracy: Double) {
        val r = accuracy * accuracy
        val dx = mx - x
        val dy = my - y

        val s00 = p[0] + r
        val s01 = p[1]
        val s10 = p[4]
        val s11 = p[5] + r

        val det = s00 * s11 - s01 * s10
        if (det == 0.0) return
        val invDet = 1.0 / det
        val si00 = s11 * invDet
        val si01 = -s01 * invDet
        val si10 = -s10 * invDet
        val si11 = s00 * invDet

        val k00 = p[0] * si00 + p[1] * si10
        val k01 = p[0] * si01 + p[1] * si11
        val k10 = p[4] * si00 + p[5] * si10
        val k11 = p[4] * si01 + p[5] * si11
        val k20 = p[8] * si00 + p[9] * si10
        val k21 = p[8] * si01 + p[9] * si11
        val k30 = p[12] * si00 + p[13] * si10
        val k31 = p[12] * si01 + p[13] * si11

        x  += k00 * dx + k01 * dy
        y  += k10 * dx + k11 * dy
        vx += k20 * dx + k21 * dy
        vy += k30 * dx + k31 * dy

        System.arraycopy(p, 0, pTemp, 0, 16)
        val t = pTemp
        p[0]  = t[0]  - k00 * t[0]  - k01 * t[4]
        p[1]  = t[1]  - k00 * t[1]  - k01 * t[5]
        p[2]  = t[2]  - k00 * t[2]  - k01 * t[6]
        p[3]  = t[3]  - k00 * t[3]  - k01 * t[7]
        p[4]  = t[4]  - k10 * t[0]  - k11 * t[4]
        p[5]  = t[5]  - k10 * t[1]  - k11 * t[5]
        p[6]  = t[6]  - k10 * t[2]  - k11 * t[6]
        p[7]  = t[7]  - k10 * t[3]  - k11 * t[7]
        p[8]  = t[8]  - k20 * t[0]  - k21 * t[4]
        p[9]  = t[9]  - k20 * t[1]  - k21 * t[5]
        p[10] = t[10] - k20 * t[2]  - k21 * t[6]
        p[11] = t[11] - k20 * t[3]  - k21 * t[7]
        p[12] = t[12] - k30 * t[0]  - k31 * t[4]
        p[13] = t[13] - k30 * t[1]  - k31 * t[5]
        p[14] = t[14] - k30 * t[2]  - k31 * t[6]
        p[15] = t[15] - k30 * t[3]  - k31 * t[7]
    }

    private fun toLatLng(): Pair<Double, Double> = Pair(
        originLat + y / metersPerDegreeLat,
        originLng + x / metersPerDegreeLng
    )

    companion object {
        /** Process noise in m/s² — models acceleration uncertainty. */
        private const val PROCESS_NOISE = 3.0
    }
}
