import Foundation

/// 2D Extended Kalman Filter for GPS coordinate smoothing.
///
/// Uses latitude/longitude in meters (via equirectangular projection) with
/// the device-reported GPS accuracy as measurement noise. Produces smoother
/// tracks, better speed estimates, and eliminates GPS jitter.
///
/// The filter maintains a 4-element state vector: `[x, y, vx, vy]`
/// (position + velocity in local meter coordinates). On each GPS fix,
/// it predicts the next state using elapsed time, then corrects using
/// the measured position weighted by the GPS accuracy.
///
/// Mirrors the Dart `KalmanLocationFilter` class.
public final class KalmanLocationFilter {

    // State vector: [x, y, vx, vy] in meters from an arbitrary origin.
    private var x: Double = 0   // position x (meters, east)
    private var y: Double = 0   // position y (meters, north)
    private var vx: Double = 0  // velocity x (m/s)
    private var vy: Double = 0  // velocity y (m/s)

    // 4×4 covariance matrix stored as a flat 16-element array.
    private var p = [Double](repeating: 0, count: 16)

    /// Scratch buffer for covariance snapshots — avoids per-fix allocation.
    private var pTemp = [Double](repeating: 0, count: 16)

    /// Process noise in m/s² — models acceleration uncertainty.
    private static let processNoise: Double = 3.0

    // Conversion factors.
    private var originLat: Double = 0
    private var originLng: Double = 0
    private var metersPerDegreeLat: Double = 111320
    private var metersPerDegreeLng: Double = 111320

    private var lastTimestampMs: Int = 0

    /// Whether the filter has been initialized with at least one measurement.
    public private(set) var isInitialized: Bool = false

    /// The current estimated speed in m/s derived from the state vector.
    public var estimatedSpeed: Double {
        sqrt(vx * vx + vy * vy)
    }

    public init() {}

    /// Process a new GPS measurement and return the smoothed coordinates.
    ///
    /// - Parameters:
    ///   - latitude: Raw GPS latitude in degrees.
    ///   - longitude: Raw GPS longitude in degrees.
    ///   - accuracy: GPS horizontal accuracy in meters.
    ///   - timestampMs: Location timestamp in milliseconds since epoch.
    /// - Returns: Smoothed `(latitude, longitude)` in degrees.
    public func process(
        latitude: Double,
        longitude: Double,
        accuracy: Double,
        timestampMs: Int
    ) -> (latitude: Double, longitude: Double) {
        let measAccuracy = max(accuracy, 1.0)

        if !isInitialized {
            initialize(lat: latitude, lng: longitude,
                       accuracy: measAccuracy, ts: timestampMs)
            return (latitude: latitude, longitude: longitude)
        }

        let dt = Double(timestampMs - lastTimestampMs) / 1000.0
        if dt <= 0 {
            return toLatLng()
        }
        lastTimestampMs = timestampMs

        // Convert measurement to local meters.
        let mx = (longitude - originLng) * metersPerDegreeLng
        let my = (latitude - originLat) * metersPerDegreeLat

        predict(dt: dt)
        update(mx: mx, my: my, accuracy: measAccuracy)

        return toLatLng()
    }

    /// Reset the filter state. Call when tracking restarts.
    public func reset() {
        isInitialized = false
        lastTimestampMs = 0
        x = 0; y = 0; vx = 0; vy = 0
        for i in 0..<16 { p[i] = 0 }
    }

    // MARK: - Private

    private func initialize(lat: Double, lng: Double,
                            accuracy: Double, ts: Int) {
        originLat = lat
        originLng = lng
        metersPerDegreeLat = 111320
        metersPerDegreeLng = 111320 * cos(lat * .pi / 180.0)

        x = 0; y = 0; vx = 0; vy = 0
        lastTimestampMs = ts
        isInitialized = true

        for i in 0..<16 { p[i] = 0 }
        p[0] = accuracy * accuracy   // position x variance
        p[5] = accuracy * accuracy   // position y variance
        p[10] = 100.0                // velocity x variance
        p[15] = 100.0                // velocity y variance
    }

    /// Predict step: state = F × state, P = F × P × Fᵀ + Q
    private func predict(dt: Double) {
        x += vx * dt
        y += vy * dt

        let dt2 = dt * dt
        let dt3 = dt2 * dt / 2.0
        let dt4 = dt2 * dt2 / 4.0
        let q = Self.processNoise * Self.processNoise

        pTemp = p
        let t = pTemp
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

    /// Update step: correct state using the GPS measurement.
    ///
    /// H = [[1,0,0,0],[0,1,0,0]] (we observe position only)
    private func update(mx: Double, my: Double, accuracy: Double) {
        let r = accuracy * accuracy

        let dx = mx - x
        let dy = my - y

        // Innovation covariance: S = H × P × Hᵀ + R.
        let s00 = p[0] + r
        let s01 = p[1]
        let s10 = p[4]
        let s11 = p[5] + r

        // Invert 2×2 S matrix.
        let det = s00 * s11 - s01 * s10
        if det == 0 { return } // singular — skip update
        let invDet = 1.0 / det
        let si00 = s11 * invDet
        let si01 = -s01 * invDet
        let si10 = -s10 * invDet
        let si11 = s00 * invDet

        // Kalman gain K = P × Hᵀ × S⁻¹ (4×2 matrix).
        let k00 = p[0] * si00 + p[1] * si10
        let k01 = p[0] * si01 + p[1] * si11
        let k10 = p[4] * si00 + p[5] * si10
        let k11 = p[4] * si01 + p[5] * si11
        let k20 = p[8] * si00 + p[9] * si10
        let k21 = p[8] * si01 + p[9] * si11
        let k30 = p[12] * si00 + p[13] * si10
        let k31 = p[12] * si01 + p[13] * si11

        // State correction.
        x  += k00 * dx + k01 * dy
        y  += k10 * dx + k11 * dy
        vx += k20 * dx + k21 * dy
        vy += k30 * dx + k31 * dy

        // Covariance correction: P = (I − K × H) × P.
        pTemp = p
        let t = pTemp
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

    /// Convert current state back to lat/lng degrees.
    private func toLatLng() -> (latitude: Double, longitude: Double) {
        (
            latitude: originLat + y / metersPerDegreeLat,
            longitude: originLng + x / metersPerDegreeLng
        )
    }
}
