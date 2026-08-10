use crate::algorithms::geo_utils::haversine;
use std::sync::Mutex;

/// Represents the interpreted physical activity state of the device.
#[derive(uniffi::Enum, Clone, Copy, PartialEq)]
pub enum ActivityType {
    Still,
    Walking,
    Running,
    OnFoot,
    InVehicle,
    OnBicycle,
    Unknown,
}

/// Confidence level of the associated physical activity.
#[derive(uniffi::Enum, Clone, Copy, PartialEq)]
pub enum ActivityConfidence {
    Low,
    Medium,
    High,
}

/// Environmental context used to adapt location sampling frequency.
#[derive(uniffi::Record)]
pub struct AdaptiveContext {
    pub battery_level: f64,
    pub is_charging: bool,
    pub activity_type: ActivityType,
    pub activity_confidence: ActivityConfidence,
    pub speed: f64,
}

impl Default for AdaptiveContext {
    fn default() -> Self {
        Self {
            battery_level: -1.0,
            is_charging: false,
            activity_type: ActivityType::Unknown,
            activity_confidence: ActivityConfidence::Low,
            speed: 0.0,
        }
    }
}

/// The primary factor driving the current adaptive sampling rate.
#[derive(uniffi::Enum, Clone, Copy, PartialEq)]
pub enum AdaptiveSource {
    Activity,
    Speed,
    Static,
}

/// Results from evaluating the current context to determine the optimal sampling parameters.
#[derive(uniffi::Record)]
pub struct AdaptiveSamplingResult {
    pub effective_distance_filter: f64,
    pub base_distance_filter: f64,
    pub activity_factor: f64,
    pub battery_factor: f64,
    pub speed_factor: f64,
    pub source: AdaptiveSource,
}

/// Core logic engine for dynamically adjusting distance filters based on context.
#[derive(uniffi::Object)]
pub struct AdaptiveSamplingEngine {
    base_distance_filter: f64,
    elasticity_multiplier: f64,
}

#[uniffi::export]
impl AdaptiveSamplingEngine {
    #[uniffi::constructor]
    pub fn new(base_distance_filter: f64, elasticity_multiplier: f64) -> Self {
        Self {
            base_distance_filter,
            elasticity_multiplier,
        }
    }

    pub fn compute(&self, context: AdaptiveContext) -> AdaptiveSamplingResult {
        let mut activity_factor = 1.0;
        let mut speed_factor = 1.0;
        let mut source = AdaptiveSource::Static;

        let use_activity = context.activity_type != ActivityType::Unknown
            && context.activity_confidence != ActivityConfidence::Low;

        if use_activity {
            let activity_distance = Self::activity_distance(context.activity_type);
            activity_factor = activity_distance / self.base_distance_filter;
            source = AdaptiveSource::Activity;
        } else if context.speed > 0.0 {
            let mult = self.elasticity_multiplier.max(0.1);
            speed_factor = (context.speed / 10.0).clamp(1.0, 10.0) * mult;
            source = AdaptiveSource::Speed;
        }

        let batt_factor = Self::battery_factor(context.battery_level, context.is_charging);

        let effective = match source {
            AdaptiveSource::Activity => self.base_distance_filter * activity_factor * batt_factor,
            AdaptiveSource::Speed => self.base_distance_filter * speed_factor * batt_factor,
            AdaptiveSource::Static => self.base_distance_filter * batt_factor,
        };

        AdaptiveSamplingResult {
            effective_distance_filter: effective,
            base_distance_filter: self.base_distance_filter,
            activity_factor,
            battery_factor: batt_factor,
            speed_factor,
            source,
        }
    }
}

impl AdaptiveSamplingEngine {
    const DISTANCE_STILL: f64 = 500.0;
    const DISTANCE_WALKING: f64 = 50.0;
    const DISTANCE_RUNNING: f64 = 30.0;
    const DISTANCE_BICYCLE: f64 = 25.0;
    const DISTANCE_VEHICLE: f64 = 10.0;

    const BATTERY_HIGH_THRESHOLD: f64 = 0.50;
    const BATTERY_MEDIUM_THRESHOLD: f64 = 0.20;
    const BATTERY_LOW_THRESHOLD: f64 = 0.10;

    const BATTERY_MEDIUM_FACTOR: f64 = 1.5;
    const BATTERY_LOW_FACTOR: f64 = 2.5;
    const BATTERY_CRITICAL_FACTOR: f64 = 5.0;

    fn activity_distance(activity: ActivityType) -> f64 {
        match activity {
            ActivityType::Still => Self::DISTANCE_STILL,
            ActivityType::Walking | ActivityType::OnFoot => Self::DISTANCE_WALKING,
            ActivityType::Running => Self::DISTANCE_RUNNING,
            ActivityType::OnBicycle => Self::DISTANCE_BICYCLE,
            ActivityType::InVehicle => Self::DISTANCE_VEHICLE,
            ActivityType::Unknown => 10.0,
        }
    }

    fn battery_factor(battery_level: f64, is_charging: bool) -> f64 {
        if is_charging || battery_level < 0.0 {
            return 1.0;
        }
        if battery_level < Self::BATTERY_LOW_THRESHOLD {
            return Self::BATTERY_CRITICAL_FACTOR;
        }
        if battery_level < Self::BATTERY_MEDIUM_THRESHOLD {
            return Self::BATTERY_LOW_FACTOR;
        }
        if battery_level < Self::BATTERY_HIGH_THRESHOLD {
            return Self::BATTERY_MEDIUM_FACTOR;
        }
        1.0
    }
}

/// Represents the outcome of filtering and processing a single location update.
#[derive(uniffi::Record)]
pub struct LocationProcessorResult {
    pub accepted: bool,
    pub effective_speed: f64,
    pub odometer_delta: f64,
    pub distance: f64,
    pub reason: Option<String>,
    pub error_message: Option<String>,
    pub is_error: bool,
}

impl LocationProcessorResult {
    fn accept(effective_speed: f64, odometer_delta: f64, distance: f64) -> Self {
        Self {
            accepted: true,
            effective_speed,
            odometer_delta,
            distance,
            reason: None,
            error_message: None,
            is_error: false,
        }
    }

    /// A fix we decline to store still answers "how fast is this device?", and
    /// `effective_speed` is the only channel that answer travels on (#332).
    ///
    /// Both hosts feed *every* fix into the GPS-speed motion state machine,
    /// accepted or not — deliberately, because a parked device's fixes are all
    /// distance-filtered and the machine would otherwise never leave MOVING.
    /// Hardcoding `0.0` here therefore reported "stopped" once per rejected fix.
    /// That is the common case in a vehicle, not a corner case: at a 30 m
    /// distance filter and ~1 Hz fixes, most of a 10 m/s drive is rejected, so
    /// the machine saw a stream of zeros on a motorway, ran its SLOWING
    /// countdown to completion and downgraded the host to periodic tracking
    /// mid-trip.
    ///
    /// Callers pass the speed they still trust from the fix. Rejections that
    /// impugn the fix itself — a spoofed location, a teleport — pass `0.0`
    /// rather than lending credibility to a reading they just refused.
    fn filtered(reason: &str, effective_speed: f64) -> Self {
        Self {
            accepted: false,
            effective_speed,
            odometer_delta: 0.0,
            distance: 0.0,
            reason: Some(reason.to_string()),
            error_message: None,
            is_error: false,
        }
    }

    /// As [`Self::filtered`], for rejections the host surfaces as errors.
    fn error(reason: &str, message: &str, effective_speed: f64) -> Self {
        Self {
            accepted: false,
            effective_speed,
            odometer_delta: 0.0,
            distance: 0.0,
            reason: Some(reason.to_string()),
            error_message: Some(message.to_string()),
            is_error: true,
        }
    }
}

/// The four thresholds that govern how much distance a fix may contribute.
///
/// Split out from the rest of the processor config because these — and only
/// these — may be swapped at runtime by transport-mode auto-tuning. See
/// [`crate::algorithms::transport_mode::tuning_for_transport_mode`].
#[derive(uniffi::Record, Clone, Copy, Debug, PartialEq)]
pub struct LocationTuning {
    /// Minimum movement (m) between recorded fixes.
    pub distance_filter: f64,
    /// Reject fixes with accuracy worse than this (m). `<= 0` disables.
    pub tracking_accuracy_threshold: i32,
    /// Only fixes at least this accurate (m) contribute to the odometer.
    /// `<= 0` disables, letting every accepted fix count.
    pub odometer_accuracy_threshold: i32,
    /// Reject fixes implying a speed above this (m/s). `<= 0` disables.
    pub max_implied_speed: i32,
}

struct LocationProcessorState {
    last_latitude: Option<f64>,
    last_longitude: Option<f64>,
    last_timestamp_ms: i64,
    sparse_last_lat: Option<f64>,
    sparse_last_lng: Option<f64>,
    sparse_last_timestamp_ms: i64,
    last_effective_speed: f64,
    /// Anchor the odometer measures from. Advances only on fixes that clear the
    /// accuracy gate, so coarse fixes defer distance rather than losing it.
    odo_last_latitude: Option<f64>,
    odo_last_longitude: Option<f64>,
    /// Live thresholds. Seeded from the constructor, replaced by `retune`.
    tuning: LocationTuning,
    /// The constructor's thresholds, kept so `restore_base_tuning` can undo an
    /// auto-tune when the mode goes back to Unknown.
    base_tuning: LocationTuning,
}

/// Core location processing engine that handles filtering out inaccurate or redundant points.
#[derive(uniffi::Object)]
pub struct LocationProcessor {
    disable_elasticity: bool,
    elasticity_multiplier: f64,
    enable_adaptive_mode: bool,
    filter_policy: i32,
    reject_mock_locations: bool,
    mock_detection_level: i32,
    enable_sparse_updates: bool,
    sparse_distance_threshold: f64,
    sparse_max_idle_seconds: i32,
    state: Mutex<LocationProcessorState>,
}

#[uniffi::export]
impl LocationProcessor {
    #[uniffi::constructor]
    pub fn new(
        distance_filter: f64,
        disable_elasticity: bool,
        elasticity_multiplier: f64,
        enable_adaptive_mode: bool,
        tracking_accuracy_threshold: i32,
        filter_policy: i32,
        max_implied_speed: i32,
        odometer_accuracy_threshold: i32,
        reject_mock_locations: bool,
        mock_detection_level: i32,
        enable_sparse_updates: bool,
        sparse_distance_threshold: f64,
        sparse_max_idle_seconds: i32,
    ) -> Self {
        let base_tuning = LocationTuning {
            distance_filter,
            tracking_accuracy_threshold,
            odometer_accuracy_threshold,
            max_implied_speed,
        };
        Self {
            disable_elasticity,
            elasticity_multiplier,
            enable_adaptive_mode,
            filter_policy,
            reject_mock_locations,
            mock_detection_level,
            enable_sparse_updates,
            sparse_distance_threshold,
            sparse_max_idle_seconds,
            state: Mutex::new(LocationProcessorState {
                last_latitude: None,
                last_longitude: None,
                last_timestamp_ms: 0,
                sparse_last_lat: None,
                sparse_last_lng: None,
                sparse_last_timestamp_ms: 0,
                last_effective_speed: 0.0,
                odo_last_latitude: None,
                odo_last_longitude: None,
                tuning: base_tuning,
                base_tuning,
            }),
        }
    }

    pub fn last_effective_speed(&self) -> f64 {
        self.state.lock().unwrap().last_effective_speed
    }

    pub fn has_last_location(&self) -> bool {
        self.state.lock().unwrap().last_latitude.is_some()
    }

    /// Swaps the distance/accuracy/odometer/speed thresholds in place.
    ///
    /// Deliberately leaves the positional state (last lat/lng/timestamp) alone:
    /// rebuilding the processor to change thresholds would drop the anchor point
    /// and silently forfeit one inter-fix delta from the odometer every time the
    /// transport mode changed.
    /// A configured `distance_filter` of 0 survives the swap (#346).
    ///
    /// Zero is not "unset" — the hosts default it to 10 m, so reaching 0 takes a
    /// deliberate "record every fix", the same opt-out the sibling thresholds
    /// document as `<= 0 disables`. Auto-tuning used to overwrite it like any
    /// other value, and `Still` carries the widest non-vehicle gate in the table
    /// at 25 m. A parked device never travels 25 m, so every fix came back
    /// `DISTANCE_FILTER`, nothing was persisted, and the host saw it as sync
    /// having stopped — while the pace machine, which has its own idea of when a
    /// device is parked, was meanwhile holding continuous GPS open and throwing
    /// away roughly two fixes a second.
    ///
    /// Only the distance gate is preserved. The accuracy and implied-speed
    /// thresholds are about whether a fix is *trustworthy*, which the mode
    /// genuinely knows better than a static config, so those still tune.
    pub fn retune(&self, tuning: LocationTuning) {
        let mut state = self.state.lock().unwrap();
        let mut tuning = tuning;
        if state.base_tuning.distance_filter == 0.0 {
            tuning.distance_filter = 0.0;
        }
        state.tuning = tuning;
    }

    /// Restores the thresholds the processor was constructed with, undoing any
    /// [`Self::retune`]. Used when the classifier drops back to `Unknown` and
    /// the host's own configuration should take over again.
    pub fn restore_base_tuning(&self) {
        let mut state = self.state.lock().unwrap();
        state.tuning = state.base_tuning;
    }

    /// Replaces the *base* thresholds — the ones [`Self::restore_base_tuning`]
    /// reverts to — so a host reconfiguration reaches the processor (#303).
    ///
    /// Until this existed, `base_tuning` was frozen at construction, so the only
    /// way to change a threshold was to rebuild the processor. That is exactly
    /// what [`Self::retune`] documents as unacceptable: a rebuild drops the
    /// positional anchor and forfeits one inter-fix delta from the odometer.
    /// `setConfig` therefore left `trackingAccuracyThreshold`,
    /// `odometerAccuracyThreshold` and `maxImpliedSpeed` stranded in the host's
    /// config cache, and `restore_base_tuning` reverted to stale values the host
    /// had already replaced.
    ///
    /// When no auto-tune is in force the live thresholds move too, so the change
    /// takes effect on the very next fix. When one *is* in force the committed
    /// mode keeps priority and only the restore target is updated — the new
    /// configuration takes over when the mode goes back to `Unknown` or
    /// auto-tuning is switched off. An active auto-tune is detected by comparing
    /// the live tuning against the base rather than tracking a separate flag, so
    /// this cannot disagree with [`Self::retune`] about what is in force.
    pub fn set_base_tuning(&self, tuning: LocationTuning) {
        let mut state = self.state.lock().unwrap();
        let auto_tune_in_force = state.tuning != state.base_tuning;
        state.base_tuning = tuning;
        if !auto_tune_in_force {
            state.tuning = tuning;
        }
    }

    /// The thresholds currently in force.
    pub fn current_tuning(&self) -> LocationTuning {
        self.state.lock().unwrap().tuning
    }

    pub fn process(
        &self,
        latitude: f64,
        longitude: f64,
        accuracy: f64,
        speed: f64,
        timestamp_ms: i64,
        is_mock: bool,
        adaptive_context: Option<AdaptiveContext>,
    ) -> LocationProcessorResult {
        let mut state = self.state.lock().unwrap();
        let tuning = state.tuning;

        // Mock rejections report 0.0: a fix the platform flagged as spoofed is
        // untrusted in full, and its speed must not be able to hold the motion
        // state machine awake (#332).
        if self.reject_mock_locations && is_mock {
            return if self.filter_policy == 2 {
                LocationProcessorResult::error(
                    "MOCK_LOCATION",
                    "Location rejected: flagged as mock/spoofed by the platform",
                    0.0,
                )
            } else {
                LocationProcessorResult::filtered("MOCK_LOCATION", 0.0)
            };
        }

        if self.mock_detection_level >= 2
            && self.reject_mock_locations
            && state.last_timestamp_ms > 0
            && timestamp_ms < state.last_timestamp_ms
        {
            return if self.filter_policy == 2 {
                LocationProcessorResult::error(
                    "MOCK_LOCATION_TIMESTAMP",
                    &format!(
                        "Location rejected: timestamp {} is before previous {} (non-monotonic)",
                        timestamp_ms, state.last_timestamp_ms
                    ),
                    0.0,
                )
            } else {
                LocationProcessorResult::filtered("MOCK_LOCATION_TIMESTAMP", 0.0)
            };
        }

        let mut distance = 0.0;
        let mut time_delta = 0.0;

        if let (Some(prev_lat), Some(prev_lng)) = (state.last_latitude, state.last_longitude) {
            distance = haversine(prev_lat, prev_lng, latitude, longitude);
            time_delta = (timestamp_ms - state.last_timestamp_ms) as f64 / 1000.0;
        }

        let computed_speed = if distance > 0.0 && time_delta > 0.0 {
            distance / time_delta
        } else {
            0.0
        };
        let effective_speed = if speed > 0.0 { speed } else { computed_speed };

        let mut effective_distance = tuning.distance_filter;
        if self.enable_adaptive_mode {
            let mut ctx = adaptive_context.unwrap_or_default();
            if ctx.speed <= 0.0 {
                ctx.speed = effective_speed;
            }
            let engine = AdaptiveSamplingEngine::new(tuning.distance_filter, self.elasticity_multiplier);
            effective_distance = engine.compute(ctx).effective_distance_filter;
        } else if !self.disable_elasticity && effective_speed > 0.0 {
            let multiplier = self.elasticity_multiplier.max(0.1);
            let speed_factor = (effective_speed / 10.0).clamp(1.0, 10.0);
            effective_distance = tuning.distance_filter * speed_factor * multiplier;
        }

        // The fix is merely too close to the last one to be worth storing —
        // nothing about it makes its speed less true (#332).
        if state.last_latitude.is_some() && distance < effective_distance {
            return LocationProcessorResult::filtered("DISTANCE_FILTER", effective_speed);
        }

        if tuning.tracking_accuracy_threshold > 0
            && accuracy > tuning.tracking_accuracy_threshold as f64
        {
            match self.filter_policy {
                2 => {
                    return LocationProcessorResult::error(
                        "ACCURACY_FILTER",
                        &format!(
                            "Location accuracy {}m exceeds threshold {}m",
                            accuracy, tuning.tracking_accuracy_threshold
                        ),
                        effective_speed,
                    )
                }
                // A coarse fix is a poor position but not a poor speedometer:
                // the platform's reading is Doppler-derived, independent of
                // horizontal accuracy (#332).
                1 => return LocationProcessorResult::filtered("ACCURACY_FILTER", effective_speed),
                _ => {
                    if state.last_latitude.is_some() {
                        return LocationProcessorResult::filtered(
                            "ACCURACY_FILTER",
                            effective_speed,
                        );
                    }
                }
            }
        }

        if tuning.max_implied_speed > 0 && state.last_latitude.is_some() && time_delta > 0.0 {
            let implied_speed = distance / time_delta;
            if implied_speed > tuning.max_implied_speed as f64 {
                // The jump between the two positions is what failed, so the
                // position-derived fallback in `effective_speed` *is* the
                // rejected quantity and must not be reported onward. The
                // platform's own reading is unaffected by the teleport, so pass
                // it when there is one and 0.0 when there is not (#332).
                let reported_speed = if speed > 0.0 { speed } else { 0.0 };
                return if self.filter_policy == 2 {
                    LocationProcessorResult::error(
                        "SPEED_FILTER",
                        &format!(
                            "Implied speed {:.1}m/s exceeds max {}m/s",
                            implied_speed, tuning.max_implied_speed
                        ),
                        reported_speed,
                    )
                } else {
                    LocationProcessorResult::filtered("SPEED_FILTER", reported_speed)
                };
            }
        }

        // The odometer keeps its own anchor, separate from the tracking anchor.
        //
        // A fix too coarse to trust must *defer* its distance, not delete it. The
        // anchor only advances on a fix that passes the accuracy gate, so the
        // next trustworthy fix measures the whole span it covered. Advancing
        // unconditionally — as this did before — silently dropped every segment
        // that happened to end on a coarse fix, which systematically
        // under-reported distance in exactly the conditions the gate exists for.
        // That under-reporting scales with how tight the gate is, so it bites
        // hardest on foot, where the gate is tightest.
        let passes_odometer_gate = tuning.odometer_accuracy_threshold <= 0
            || accuracy <= tuning.odometer_accuracy_threshold as f64;
        let odometer_delta = if passes_odometer_gate {
            match (state.odo_last_latitude, state.odo_last_longitude) {
                (Some(prev_lat), Some(prev_lng)) => {
                    haversine(prev_lat, prev_lng, latitude, longitude)
                }
                // First trustworthy fix: nothing to measure from yet.
                _ => 0.0,
            }
        } else {
            0.0
        };

        if self.enable_sparse_updates {
            if let (Some(s_lat), Some(s_lng)) = (state.sparse_last_lat, state.sparse_last_lng) {
                let sparse_dist = haversine(s_lat, s_lng, latitude, longitude);
                let sparse_elapsed = (timestamp_ms - state.sparse_last_timestamp_ms) as f64 / 1000.0;

                let within_distance = sparse_dist < self.sparse_distance_threshold;
                let within_time = self.sparse_max_idle_seconds == 0
                    || sparse_elapsed < self.sparse_max_idle_seconds as f64;

                if within_distance && within_time {
                    state.last_latitude = Some(latitude);
                    state.last_longitude = Some(longitude);
                    state.last_timestamp_ms = timestamp_ms;
                    state.last_effective_speed = effective_speed;
                    // This fix passed every quality gate and advanced the
                    // anchor; it is suppressed only to thin the stream, so its
                    // speed is as good as an accepted one's (#332).
                    return LocationProcessorResult::filtered("SPARSE_FILTER", effective_speed);
                }
            }
            state.sparse_last_lat = Some(latitude);
            state.sparse_last_lng = Some(longitude);
            state.sparse_last_timestamp_ms = timestamp_ms;
        }

        state.last_latitude = Some(latitude);
        state.last_longitude = Some(longitude);
        state.last_timestamp_ms = timestamp_ms;
        state.last_effective_speed = effective_speed;
        if passes_odometer_gate {
            state.odo_last_latitude = Some(latitude);
            state.odo_last_longitude = Some(longitude);
        }

        LocationProcessorResult::accept(effective_speed, odometer_delta, distance)
    }

    /// Clears the positional history. Leaves the active tuning in place — a
    /// reset is about forgetting where we were, not which mode we are in.
    pub fn reset(&self) {
        let mut state = self.state.lock().unwrap();
        state.last_latitude = None;
        state.last_longitude = None;
        state.last_timestamp_ms = 0;
        state.last_effective_speed = 0.0;
        state.sparse_last_lat = None;
        state.sparse_last_lng = None;
        state.sparse_last_timestamp_ms = 0;
        state.odo_last_latitude = None;
        state.odo_last_longitude = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const BASE_LAT: f64 = 52.0;
    const BASE_LNG: f64 = 13.0;
    /// Metres per degree of latitude — lets tests express offsets in metres.
    const M_PER_DEG_LAT: f64 = 111_320.0;

    /// A processor with elasticity off so `distance_filter` is exactly what the
    /// tuning says, which is what these tests are asserting about.
    fn processor(tuning: LocationTuning) -> LocationProcessor {
        LocationProcessor::new(
            tuning.distance_filter,
            true, // disable_elasticity
            1.0,
            false, // enable_adaptive_mode
            tuning.tracking_accuracy_threshold,
            0, // filter_policy: adjust
            tuning.max_implied_speed,
            tuning.odometer_accuracy_threshold,
            false,
            0,
            false,
            0.0,
            0,
        )
    }

    fn walking() -> LocationTuning {
        LocationTuning {
            distance_filter: 8.0,
            tracking_accuracy_threshold: 15,
            odometer_accuracy_threshold: 10,
            max_implied_speed: 4,
        }
    }

    fn vehicle() -> LocationTuning {
        LocationTuning {
            distance_filter: 30.0,
            tracking_accuracy_threshold: 50,
            odometer_accuracy_threshold: 30,
            max_implied_speed: 60,
        }
    }

    /// A fix `metres` north of the base point.
    fn fix_at(p: &LocationProcessor, metres: f64, accuracy: f64, ts_ms: i64) -> LocationProcessorResult {
        p.process(
            BASE_LAT + metres / M_PER_DEG_LAT,
            BASE_LNG,
            accuracy,
            0.0,
            ts_ms,
            false,
            None,
        )
    }

    #[test]
    fn retune_swaps_thresholds_without_dropping_the_anchor() {
        let p = processor(walking());
        // Seed the anchor.
        assert!(fix_at(&p, 0.0, 5.0, 1_000).accepted);

        p.retune(vehicle());

        // 20 m is past walking's 8 m filter but short of vehicle's 30 m, so the
        // new tuning is in force...
        assert!(!fix_at(&p, 20.0, 5.0, 3_000).accepted);
        // ...and the anchor survived, so a 40 m move still measures 40 m rather
        // than restarting from zero the way a rebuild would.
        let r = fix_at(&p, 40.0, 5.0, 5_000);
        assert!(r.accepted);
        assert!((r.distance - 40.0).abs() < 0.5, "distance was {}", r.distance);
        assert!((r.odometer_delta - 40.0).abs() < 0.5);
    }

    #[test]
    fn restore_base_tuning_undoes_a_retune() {
        let p = processor(walking());
        p.retune(vehicle());
        assert_eq!(p.current_tuning(), vehicle());

        p.restore_base_tuning();
        assert_eq!(p.current_tuning(), walking());

        // And the restored thresholds actually apply. Fixes are spaced at a
        // realistic 1 m/s so they clear walking's own implied-speed ceiling.
        assert!(fix_at(&p, 0.0, 5.0, 1_000).accepted);
        assert!(fix_at(&p, 10.0, 5.0, 11_000).accepted, "10 m clears walking's 8 m filter");
    }

    /// A host that switched distance filtering off entirely.
    fn no_distance_filter() -> LocationTuning {
        LocationTuning {
            distance_filter: 0.0,
            tracking_accuracy_threshold: 100,
            odometer_accuracy_threshold: 50,
            max_implied_speed: 80,
        }
    }

    /// `TransportMode::Still` — the widest non-vehicle distance gate in the
    /// table, and the one that produced #346 in the field.
    fn still() -> LocationTuning {
        LocationTuning {
            distance_filter: 25.0,
            tracking_accuracy_threshold: 15,
            odometer_accuracy_threshold: 10,
            max_implied_speed: 3,
        }
    }

    /// #346: auto-tuning must not impose a distance gate on a host that
    /// deliberately switched distance filtering off.
    ///
    /// The failure was total rather than partial: `Still` commits on a parked
    /// device, a parked device never travels 25 m, so *every* fix came back
    /// DISTANCE_FILTER and nothing was ever persisted or synced.
    #[test]
    fn retune_preserves_a_configured_zero_distance_filter() {
        let p = processor(no_distance_filter());
        p.retune(still());

        assert_eq!(
            p.current_tuning().distance_filter,
            0.0,
            "the host asked for every fix; the mode may not overrule that"
        );
    }

    /// The other three thresholds are about whether a fix is *trustworthy*,
    /// which the committed mode does know better — they must still tune.
    #[test]
    fn retune_still_applies_the_other_thresholds_when_distance_filtering_is_off() {
        let p = processor(no_distance_filter());
        p.retune(still());

        let t = p.current_tuning();
        assert_eq!(t.tracking_accuracy_threshold, 15);
        assert_eq!(t.odometer_accuracy_threshold, 10);
        assert_eq!(t.max_implied_speed, 3);
    }

    /// The behaviour that actually matters: consecutive fixes from a parked
    /// device keep being accepted instead of vanishing.
    #[test]
    fn a_parked_device_still_records_fixes_when_distance_filtering_is_off() {
        let p = processor(no_distance_filter());
        p.retune(still());

        assert!(fix_at(&p, 0.0, 2.6, 1_000).accepted);
        // Jitter-sized moves, nothing close to Still's 25 m gate.
        assert!(fix_at(&p, 1.0, 2.6, 11_000).accepted, "1 m must still be recorded");
        assert!(fix_at(&p, 1.5, 2.6, 21_000).accepted, "0.5 m must still be recorded");
    }

    /// The guard keys off the *configured* value, so a host that did ask for a
    /// distance filter still gets the mode's.
    #[test]
    fn retune_still_overrides_a_nonzero_configured_distance_filter() {
        let p = processor(walking());
        p.retune(still());

        assert_eq!(p.current_tuning().distance_filter, 25.0);
    }

    /// Reconfiguring *to* zero must take effect on the next retune too — the
    /// guard reads `base_tuning`, which `set_base_tuning` owns (#303).
    #[test]
    fn reconfiguring_to_zero_disables_the_gate_for_later_retunes() {
        let p = processor(walking());
        p.retune(still());
        assert_eq!(p.current_tuning().distance_filter, 25.0);

        p.set_base_tuning(no_distance_filter());
        p.retune(still());

        assert_eq!(p.current_tuning().distance_filter, 0.0);
    }

    /// #303: a host reconfiguration must reach the live thresholds when nothing
    /// is auto-tuned — previously the only route was a rebuild, which forfeits
    /// the anchor.
    fn cycling() -> LocationTuning {
        LocationTuning {
            distance_filter: 20.0,
            tracking_accuracy_threshold: 30,
            odometer_accuracy_threshold: 20,
            max_implied_speed: 20,
        }
    }

    #[test]
    fn set_base_tuning_applies_immediately_when_no_auto_tune_is_in_force() {
        let p = processor(walking());
        assert!(fix_at(&p, 0.0, 5.0, 1_000).accepted);

        p.set_base_tuning(cycling());
        assert_eq!(p.current_tuning(), cycling(), "live thresholds must move");

        // 12 m cleared walking's 8 m filter but is short of cycling's 20 m, so
        // the reconfiguration is genuinely in force...
        assert!(!fix_at(&p, 12.0, 5.0, 13_000).accepted);
        // ...and the anchor survived, unlike a rebuild.
        let r = fix_at(&p, 25.0, 5.0, 26_000);
        assert!(r.accepted);
        assert!((r.distance - 25.0).abs() < 0.5, "distance was {}", r.distance);
    }

    #[test]
    fn set_base_tuning_defers_to_an_active_auto_tune_but_updates_the_restore_target() {
        let p = processor(walking());
        p.retune(vehicle());
        assert_eq!(p.current_tuning(), vehicle());

        // Host reconfigures mid-drive. The committed mode keeps priority...
        p.set_base_tuning(cycling());
        assert_eq!(p.current_tuning(), vehicle(), "auto-tune must keep priority");

        // ...but the restore target is the NEW configuration, not the stale one
        // captured at construction. This is the #301 promise that was broken.
        p.restore_base_tuning();
        assert_eq!(p.current_tuning(), cycling());
    }

    #[test]
    fn set_base_tuning_survives_a_later_retune_restore_cycle() {
        let p = processor(walking());
        p.set_base_tuning(cycling());

        // A mode commits and then drops back to Unknown.
        p.retune(vehicle());
        p.restore_base_tuning();

        assert_eq!(
            p.current_tuning(),
            cycling(),
            "restore must land on the reconfigured base, never the constructor's"
        );
    }

    #[test]
    fn tightened_odometer_gate_excludes_coarse_fixes_from_distance() {
        // The reported bug: with a loose gate, a coarse fix contributes its full
        // delta to the odometer.
        // Both processors keep a wide tracking gate so the 40 m fix is recorded
        // either way; the odometer gate is the only difference under test.
        let loose = processor(LocationTuning {
            tracking_accuracy_threshold: 50,
            odometer_accuracy_threshold: 50, // the shipped default
            ..walking()
        });
        // 30 m over 30 s — a genuine walking pace, so only the accuracy gates
        // are under test here.
        assert!(fix_at(&loose, 0.0, 5.0, 1_000).accepted);
        let r = fix_at(&loose, 30.0, 40.0, 31_000);
        assert!(r.accepted);
        assert!(r.odometer_delta > 0.0, "loose gate lets a 40 m-accuracy fix count");

        // Walking's 10 m gate keeps recording the fix but stops it inflating
        // distance. Its 15 m tracking gate would reject a 40 m-accuracy fix, so
        // widen only that to isolate the odometer gate.
        let tight = processor(LocationTuning {
            tracking_accuracy_threshold: 50,
            ..walking()
        });
        assert!(fix_at(&tight, 0.0, 5.0, 1_000).accepted);
        let r = fix_at(&tight, 30.0, 40.0, 31_000);
        assert!(r.accepted, "still recorded for the map");
        assert_eq!(r.odometer_delta, 0.0, "but contributes no distance");
    }

    #[test]
    fn retuned_implied_speed_ceiling_rejects_teleport_spikes() {
        let p = processor(walking());
        assert!(fix_at(&p, 0.0, 5.0, 1_000).accepted);
        // 100 m in 2 s = 50 m/s, far past walking's 4 m/s ceiling.
        let r = fix_at(&p, 100.0, 5.0, 3_000);
        assert!(!r.accepted);
        assert_eq!(r.reason.as_deref(), Some("SPEED_FILTER"));

        // The same jump is legitimate in a vehicle.
        let p = processor(vehicle());
        assert!(fix_at(&p, 0.0, 5.0, 1_000).accepted);
        assert!(fix_at(&p, 100.0, 5.0, 3_000).accepted);
    }

    #[test]
    fn a_coarse_fix_defers_distance_rather_than_deleting_it() {
        // Walking's 10 m odometer gate with a wide tracking gate, so the coarse
        // fix is still recorded — only its contribution to distance is in doubt.
        let p = processor(LocationTuning {
            tracking_accuracy_threshold: 60,
            ..walking()
        });
        assert!(fix_at(&p, 0.0, 5.0, 1_000).accepted);

        // 20 m on, but too coarse to trust: contributes nothing yet.
        let coarse = fix_at(&p, 20.0, 40.0, 21_000);
        assert!(coarse.accepted, "still recorded for the map");
        assert_eq!(coarse.odometer_delta, 0.0);

        // 40 m on, trustworthy again. The odometer must now book the full 40 m
        // from the last *trusted* anchor — not just the 20 m since the coarse
        // fix. Advancing the anchor on the coarse fix would have lost 20 m
        // permanently, under-reporting by exactly the distance the gate was
        // supposed to be protecting.
        let good = fix_at(&p, 40.0, 5.0, 41_000);
        assert!(good.accepted);
        assert!(
            (good.odometer_delta - 40.0).abs() < 0.5,
            "expected the deferred 40 m, got {}",
            good.odometer_delta,
        );
    }

    #[test]
    fn a_run_of_coarse_fixes_does_not_accumulate_phantom_distance() {
        // The deferral must not double-count: total booked distance over a walk
        // interrupted by coarse fixes should match the straight-line span.
        let p = processor(LocationTuning {
            tracking_accuracy_threshold: 60,
            ..walking()
        });
        let mut total = 0.0;
        assert!(fix_at(&p, 0.0, 5.0, 1_000).accepted);
        for (i, metres) in [10.0, 20.0, 30.0, 40.0, 50.0].iter().enumerate() {
            // Every other fix is too coarse for the odometer.
            let accuracy = if i % 2 == 0 { 40.0 } else { 5.0 };
            let r = fix_at(&p, *metres, accuracy, 1_000 + (i as i64 + 1) * 10_000);
            total += r.odometer_delta;
        }
        assert!(
            (total - 40.0).abs() < 0.5,
            "booked {total} m over a 40 m span ending on a trusted fix",
        );
    }

    #[test]
    fn reset_clears_position_but_keeps_the_active_tuning() {
        let p = processor(walking());
        p.retune(vehicle());
        assert!(fix_at(&p, 0.0, 5.0, 1_000).accepted);

        p.reset();

        assert!(!p.has_last_location());
        assert_eq!(p.current_tuning(), vehicle(), "reset forgets where, not which mode");
    }

    // -- #332: a rejected fix must still report the speed it was travelling at --
    //
    // Both hosts feed `effective_speed` into the GPS-speed motion state machine
    // on every fix, accepted or not. A hardcoded 0.0 on the reject paths meant
    // most of a drive was reported to that machine as "stopped".

    /// A fix `metres` north of the base point, carrying a platform speed.
    fn fix_at_speed(
        p: &LocationProcessor,
        metres: f64,
        accuracy: f64,
        speed: f64,
        ts_ms: i64,
    ) -> LocationProcessorResult {
        p.process(
            BASE_LAT + metres / M_PER_DEG_LAT,
            BASE_LNG,
            accuracy,
            speed,
            ts_ms,
            false,
            None,
        )
    }

    #[test]
    fn distance_filtered_fix_reports_the_speed_it_was_travelling_at() {
        let p = processor(vehicle());
        assert!(fix_at_speed(&p, 0.0, 5.0, 10.0, 1_000).accepted);

        // 10 m of travel is inside the 30 m vehicle filter, so this is rejected
        // for storage — but the car is still doing 10 m/s.
        let r = fix_at_speed(&p, 10.0, 5.0, 10.0, 2_000);

        assert!(!r.accepted);
        assert_eq!(r.reason.as_deref(), Some("DISTANCE_FILTER"));
        assert_eq!(
            r.effective_speed, 10.0,
            "a fix too close to store is not a fix that stopped moving",
        );
    }

    #[test]
    fn a_drive_never_reports_a_fabricated_zero_speed() {
        // The reported failure: 30 m filter, ~1 Hz fixes at 10 m/s. Two of every
        // three fixes are distance-filtered, and each used to hand the motion
        // machine a 0.00 while the car was on a motorway.
        let p = processor(vehicle());
        assert!(fix_at_speed(&p, 0.0, 5.0, 10.0, 0).accepted);

        let mut rejected = 0;
        for second in 1..=30_i64 {
            let r = fix_at_speed(&p, 10.0 * second as f64, 5.0, 10.0, second * 1_000);
            if !r.accepted {
                rejected += 1;
            }
            assert_eq!(
                r.effective_speed, 10.0,
                "fix at t={second}s reported {} m/s while driving at 10 m/s",
                r.effective_speed,
            );
        }
        assert!(
            rejected > 0,
            "the scenario is only meaningful if fixes are actually being rejected",
        );
    }

    #[test]
    fn accuracy_filtered_fix_reports_the_speed_it_was_travelling_at() {
        let p = processor(vehicle());
        assert!(fix_at_speed(&p, 0.0, 5.0, 10.0, 1_000).accepted);

        // Past the distance filter but too coarse to store. A poor position is
        // not a poor speedometer — the platform reading is Doppler-derived.
        let r = fix_at_speed(&p, 100.0, 80.0, 10.0, 2_000);

        assert!(!r.accepted);
        assert_eq!(r.reason.as_deref(), Some("ACCURACY_FILTER"));
        assert_eq!(r.effective_speed, 10.0);
    }

    #[test]
    fn mock_rejection_reports_no_speed() {
        let p = LocationProcessor::new(
            30.0, true, 1.0, false, 50, 0, 60, 30, /* reject_mock */ true, 1, false, 0.0, 0,
        );

        let r = p.process(BASE_LAT, BASE_LNG, 5.0, 30.0, 1_000, true, None);

        assert!(!r.accepted);
        assert_eq!(r.reason.as_deref(), Some("MOCK_LOCATION"));
        assert_eq!(
            r.effective_speed, 0.0,
            "a spoofed fix is untrusted in full — its speed must not hold the \
             motion machine awake",
        );
    }

    #[test]
    fn speed_filter_does_not_propagate_the_rejected_implied_speed() {
        let p = processor(vehicle());
        assert!(fix_at_speed(&p, 0.0, 5.0, 10.0, 1_000).accepted);

        // A 5 km jump in one second: ~5000 m/s implied, far past the 60 m/s cap.
        // With no platform speed to fall back on, `effective_speed` *is* the
        // absurd derived value, which must not travel onward.
        let r = fix_at_speed(&p, 5_000.0, 5.0, 0.0, 2_000);

        assert!(!r.accepted);
        assert_eq!(r.reason.as_deref(), Some("SPEED_FILTER"));
        assert_eq!(r.effective_speed, 0.0);
    }

    #[test]
    fn speed_filter_keeps_a_valid_platform_reading() {
        let p = processor(vehicle());
        assert!(fix_at_speed(&p, 0.0, 5.0, 10.0, 1_000).accepted);

        // Same teleport, but the chip reported a plausible speed of its own.
        // The jump is what failed, not the speedometer.
        let r = fix_at_speed(&p, 5_000.0, 5.0, 12.0, 2_000);

        assert!(!r.accepted);
        assert_eq!(r.reason.as_deref(), Some("SPEED_FILTER"));
        assert_eq!(r.effective_speed, 12.0);
    }
}
