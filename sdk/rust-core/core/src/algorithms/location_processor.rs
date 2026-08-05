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

    fn filtered(reason: &str) -> Self {
        Self {
            accepted: false,
            effective_speed: 0.0,
            odometer_delta: 0.0,
            distance: 0.0,
            reason: Some(reason.to_string()),
            error_message: None,
            is_error: false,
        }
    }

    fn error(reason: &str, message: &str) -> Self {
        Self {
            accepted: false,
            effective_speed: 0.0,
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
    pub fn retune(&self, tuning: LocationTuning) {
        self.state.lock().unwrap().tuning = tuning;
    }

    /// Restores the thresholds the processor was constructed with, undoing any
    /// [`Self::retune`]. Used when the classifier drops back to `Unknown` and
    /// the host's own configuration should take over again.
    pub fn restore_base_tuning(&self) {
        let mut state = self.state.lock().unwrap();
        state.tuning = state.base_tuning;
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

        if self.reject_mock_locations && is_mock {
            return if self.filter_policy == 2 {
                LocationProcessorResult::error(
                    "MOCK_LOCATION",
                    "Location rejected: flagged as mock/spoofed by the platform",
                )
            } else {
                LocationProcessorResult::filtered("MOCK_LOCATION")
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
                )
            } else {
                LocationProcessorResult::filtered("MOCK_LOCATION_TIMESTAMP")
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

        if state.last_latitude.is_some() && distance < effective_distance {
            return LocationProcessorResult::filtered("DISTANCE_FILTER");
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
                    )
                }
                1 => return LocationProcessorResult::filtered("ACCURACY_FILTER"),
                _ => {
                    if state.last_latitude.is_some() {
                        return LocationProcessorResult::filtered("ACCURACY_FILTER");
                    }
                }
            }
        }

        if tuning.max_implied_speed > 0 && state.last_latitude.is_some() && time_delta > 0.0 {
            let implied_speed = distance / time_delta;
            if implied_speed > tuning.max_implied_speed as f64 {
                return if self.filter_policy == 2 {
                    LocationProcessorResult::error(
                        "SPEED_FILTER",
                        &format!(
                            "Implied speed {:.1}m/s exceeds max {}m/s",
                            implied_speed, tuning.max_implied_speed
                        ),
                    )
                } else {
                    LocationProcessorResult::filtered("SPEED_FILTER")
                };
            }
        }

        let odometer_delta = if tuning.odometer_accuracy_threshold <= 0
            || accuracy <= tuning.odometer_accuracy_threshold as f64
        {
            distance
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
                    return LocationProcessorResult::filtered("SPARSE_FILTER");
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
    fn reset_clears_position_but_keeps_the_active_tuning() {
        let p = processor(walking());
        p.retune(vehicle());
        assert!(fix_at(&p, 0.0, 5.0, 1_000).accepted);

        p.reset();

        assert!(!p.has_last_location());
        assert_eq!(p.current_tuning(), vehicle(), "reset forgets where, not which mode");
    }
}
