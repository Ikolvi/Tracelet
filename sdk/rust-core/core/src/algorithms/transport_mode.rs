//! On-device transport-mode classifier (fused accelerometer + GPS speed).
//!
//! Augments the coarse, laggy platform Activity-Recognition signal with a
//! deterministic, explainable rule classifier over [`AccelWindow`] features
//! and GPS speed. Output is annotate-by-default (the platform value stays
//! authoritative unless the host opts in), with hysteresis so a mode must
//! persist before it commits — mirroring the moving/stationary coordinator.
//!
//! Rule-based and transparent on purpose: no opaque model weights, zero binary
//! bloat, fully unit-testable. A pluggable model can come later if needed.

use std::sync::Mutex;

use crate::algorithms::location_processor::LocationTuning;
use crate::algorithms::sensor_features::AccelWindow;

/// Detected travel mode. Distinct from the platform `ActivityType` so adding
/// `Cycling` here doesn't perturb existing activity plumbing.
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum TransportMode {
    Unknown,
    Still,
    Walking,
    Running,
    Cycling,
    Vehicle,
}

/// Classifier tuning.
#[derive(uniffi::Record, Clone, Copy, Debug)]
pub struct ClassifierConfig {
    /// A candidate mode must persist this long (ms) before it commits.
    pub mode_switch_dwell_ms: i64,
    /// Below this confidence the result is reported as `Unknown`.
    pub min_confidence: f64,
}

impl Default for ClassifierConfig {
    fn default() -> Self {
        Self {
            mode_switch_dwell_ms: 8000,
            min_confidence: 0.6,
        }
    }
}

/// Result of a classification step.
#[derive(uniffi::Record, Clone, Copy, Debug, PartialEq)]
pub struct ModeResult {
    pub mode: TransportMode,
    pub confidence: f64,
    /// True when this call committed a *change* from the previous committed mode.
    pub changed: bool,
}

struct ClassifierState {
    committed: TransportMode,
    candidate: TransportMode,
    candidate_since_ms: i64,
    has_candidate: bool,
}

/// Fuses accel features + speed into a transport mode with hysteresis.
#[derive(uniffi::Object)]
pub struct TransportModeClassifier {
    config: ClassifierConfig,
    state: Mutex<ClassifierState>,
}

/// Pure instantaneous classification (pre-hysteresis): returns the raw
/// candidate mode + confidence from one window + speed.
fn classify_instant(window: AccelWindow, speed_mps: f64) -> (TransportMode, f64) {
    let speed_kmh = speed_mps * 3.6;
    let cadence = window.dominant_cadence_hz;
    let variance = window.variance;

    // Vehicle: sustained higher speed with relatively steady acceleration.
    if speed_kmh >= 25.0 {
        let conf = if speed_kmh >= 45.0 { 0.95 } else { 0.8 };
        return (TransportMode::Vehicle, conf);
    }

    // Still: near-zero speed and little vibration.
    if speed_kmh < 2.0 && variance < 0.02 {
        return (TransportMode::Still, 0.85);
    }

    // Running: fast cadence, on-foot speed band.
    if (2.5..=3.6).contains(&cadence) && (6.0..=20.0).contains(&speed_kmh) {
        return (TransportMode::Running, 0.8);
    }

    // Walking: moderate cadence, pedestrian speed.
    if (1.3..=2.6).contains(&cadence) && (1.5..=9.0).contains(&speed_kmh) {
        return (TransportMode::Walking, 0.8);
    }

    // Cycling: mid speed band, low pedal cadence, moderate steadiness.
    if (8.0..25.0).contains(&speed_kmh) && cadence < 1.6 {
        return (TransportMode::Cycling, 0.7);
    }

    (TransportMode::Unknown, 0.0)
}

/// Location-filter thresholds appropriate to a detected [`TransportMode`].
///
/// Returns `None` for [`TransportMode::Unknown`], meaning "leave the host's own
/// configuration alone" — an unclassified stretch is not evidence for any
/// particular tuning, so the caller should keep whatever it already had.
///
/// The values are chosen for distance fidelity, which is the opposite tension
/// from [`crate::algorithms::location_processor::AdaptiveSamplingEngine`]: that
/// engine widens the distance filter for slow movers to spare the radio, while
/// this table *tightens* it, because walking is exactly where GPS noise is
/// largest relative to real displacement and where an over-wide odometer
/// accuracy gate inflates distance most.
///
/// `max_implied_speed` sits roughly 2x above each mode's realistic ceiling, so
/// it rejects teleport spikes without clipping genuine bursts.
#[uniffi::export]
pub fn tuning_for_transport_mode(mode: TransportMode) -> Option<LocationTuning> {
    let tuning = match mode {
        // Wide distance gate so GPS jitter around a parked device cannot
        // accumulate; the odometer gate stays tight for the same reason.
        TransportMode::Still => LocationTuning {
            distance_filter: 25.0,
            tracking_accuracy_threshold: 15,
            odometer_accuracy_threshold: 10,
            max_implied_speed: 3,
        },
        // ~1.4 m/s. The noise floor of a handset under tree cover is 5-8 m, so
        // a distance filter below that integrates noise as distance.
        TransportMode::Walking => LocationTuning {
            distance_filter: 8.0,
            tracking_accuracy_threshold: 15,
            odometer_accuracy_threshold: 10,
            max_implied_speed: 4,
        },
        // Covers jogging too — the classifier's Running band is 6-20 km/h.
        TransportMode::Running => LocationTuning {
            distance_filter: 12.0,
            tracking_accuracy_threshold: 25,
            odometer_accuracy_threshold: 15,
            max_implied_speed: 9,
        },
        TransportMode::Cycling => LocationTuning {
            distance_filter: 20.0,
            tracking_accuracy_threshold: 30,
            odometer_accuracy_threshold: 20,
            max_implied_speed: 20,
        },
        TransportMode::Vehicle => LocationTuning {
            distance_filter: 30.0,
            tracking_accuracy_threshold: 50,
            odometer_accuracy_threshold: 30,
            max_implied_speed: 60,
        },
        TransportMode::Unknown => return None,
    };
    Some(tuning)
}

#[uniffi::export]
impl TransportModeClassifier {
    /// Creates a classifier. Pass `None` for default tuning.
    #[uniffi::constructor]
    pub fn new(config: Option<ClassifierConfig>) -> Self {
        Self {
            config: config.unwrap_or_default(),
            state: Mutex::new(ClassifierState {
                committed: TransportMode::Unknown,
                candidate: TransportMode::Unknown,
                candidate_since_ms: 0,
                has_candidate: false,
            }),
        }
    }

    /// Classifies one window + speed, applying confidence gating and dwell
    /// hysteresis. Returns the currently committed mode.
    pub fn classify(
        &self,
        window: AccelWindow,
        speed_mps: f64,
        now_ms: i64,
    ) -> ModeResult {
        let (raw_mode, raw_conf) = classify_instant(window, speed_mps);
        let mode = if raw_conf < self.config.min_confidence {
            TransportMode::Unknown
        } else {
            raw_mode
        };

        let mut st = self.state.lock().unwrap();

        // Track how long the latest instantaneous mode has persisted.
        if !st.has_candidate || st.candidate != mode {
            st.candidate = mode;
            st.candidate_since_ms = now_ms;
            st.has_candidate = true;
        }

        let mut changed = false;
        if mode != st.committed
            && now_ms - st.candidate_since_ms >= self.config.mode_switch_dwell_ms
        {
            st.committed = mode;
            changed = true;
        }

        ModeResult {
            mode: st.committed,
            confidence: raw_conf,
            changed,
        }
    }

    /// Currently committed mode.
    pub fn current_mode(&self) -> TransportMode {
        self.state.lock().unwrap().committed
    }

    /// Resets to `Unknown`.
    pub fn reset(&self) {
        let mut st = self.state.lock().unwrap();
        st.committed = TransportMode::Unknown;
        st.candidate = TransportMode::Unknown;
        st.has_candidate = false;
        st.candidate_since_ms = 0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::algorithms::sensor_features::AccelWindow;

    fn win(variance: f64, cadence: f64, peak: f64) -> AccelWindow {
        AccelWindow {
            mean_g: 0.0,
            variance,
            peak_g: peak,
            dominant_cadence_hz: cadence,
            sample_count: 10,
            duration_ms: 1000,
        }
    }

    #[test]
    fn vehicle_from_high_speed() {
        let (m, c) = classify_instant(win(0.05, 0.5, 0.2), 60.0 / 3.6);
        assert_eq!(m, TransportMode::Vehicle);
        assert!(c >= 0.9);
    }

    #[test]
    fn still_from_low_speed_low_variance() {
        let (m, _) = classify_instant(win(0.005, 0.0, 0.02), 0.0);
        assert_eq!(m, TransportMode::Still);
    }

    #[test]
    fn walking_and_running_separated_by_cadence() {
        let (walk, _) = classify_instant(win(0.3, 2.0, 0.4), 5.0 / 3.6);
        assert_eq!(walk, TransportMode::Walking);
        let (run, _) = classify_instant(win(0.8, 3.0, 0.9), 12.0 / 3.6);
        assert_eq!(run, TransportMode::Running);
    }

    #[test]
    fn cycling_band() {
        let (m, _) = classify_instant(win(0.2, 1.2, 0.3), 18.0 / 3.6);
        assert_eq!(m, TransportMode::Cycling);
    }

    #[test]
    fn hysteresis_requires_dwell_before_commit() {
        let c = TransportModeClassifier::new(Some(ClassifierConfig {
            mode_switch_dwell_ms: 8000,
            min_confidence: 0.6,
        }));
        let w = win(0.3, 2.0, 0.4);
        let speed = 5.0 / 3.6;
        // First observation at t=0: candidate Walking, not yet committed.
        let r0 = c.classify(w, speed, 0);
        assert_eq!(r0.mode, TransportMode::Unknown);
        assert!(!r0.changed);
        // Still Walking at t=4 s — under dwell.
        assert_eq!(c.classify(w, speed, 4000).mode, TransportMode::Unknown);
        // At t=8 s — commits.
        let r = c.classify(w, speed, 8000);
        assert_eq!(r.mode, TransportMode::Walking);
        assert!(r.changed);
    }

    #[test]
    fn brief_blip_does_not_commit() {
        let c = TransportModeClassifier::new(None); // dwell 8 s
        let walk = win(0.3, 2.0, 0.4);
        let veh = win(0.05, 0.5, 0.2);
        c.classify(walk, 5.0 / 3.6, 0);
        c.classify(walk, 5.0 / 3.6, 8000); // commit Walking
        assert_eq!(c.current_mode(), TransportMode::Walking);
        // A single vehicle window then back to walking — must not flip.
        c.classify(veh, 60.0 / 3.6, 9000);
        c.classify(walk, 5.0 / 3.6, 10000);
        assert_eq!(c.current_mode(), TransportMode::Walking);
    }

    #[test]
    fn unknown_mode_yields_no_tuning() {
        // Callers must keep the host's own config rather than guessing.
        assert!(tuning_for_transport_mode(TransportMode::Unknown).is_none());
    }

    #[test]
    fn on_foot_modes_tighten_the_distance_filter_relative_to_vehicle() {
        let walk = tuning_for_transport_mode(TransportMode::Walking).unwrap();
        let run = tuning_for_transport_mode(TransportMode::Running).unwrap();
        let vehicle = tuning_for_transport_mode(TransportMode::Vehicle).unwrap();
        // The inversion this table exists to correct: on foot must be tighter
        // than in a vehicle, not looser.
        assert!(walk.distance_filter < run.distance_filter);
        assert!(run.distance_filter < vehicle.distance_filter);
    }

    #[test]
    fn odometer_gate_is_always_at_least_as_strict_as_the_tracking_gate() {
        for mode in [
            TransportMode::Still,
            TransportMode::Walking,
            TransportMode::Running,
            TransportMode::Cycling,
            TransportMode::Vehicle,
        ] {
            let t = tuning_for_transport_mode(mode).unwrap();
            // A fix too coarse to record must never be good enough to count
            // toward distance.
            assert!(
                t.odometer_accuracy_threshold <= t.tracking_accuracy_threshold,
                "{mode:?} lets un-recordable fixes reach the odometer",
            );
            assert!(t.odometer_accuracy_threshold > 0, "{mode:?} disables the odometer gate");
            assert!(t.max_implied_speed > 0, "{mode:?} disables the speed gate");
        }
    }

    #[test]
    fn implied_speed_ceiling_clears_each_modes_realistic_pace() {
        // Sanity-check the ceilings against plausible upper paces (m/s), so a
        // future edit cannot silently start clipping genuine movement.
        let cases = [
            (TransportMode::Walking, 2.2),  // brisk walk
            (TransportMode::Running, 5.5),  // ~3:00/km
            (TransportMode::Cycling, 13.0), // ~47 km/h
            (TransportMode::Vehicle, 33.0), // ~120 km/h
        ];
        for (mode, realistic_max) in cases {
            let t = tuning_for_transport_mode(mode).unwrap();
            assert!(
                (t.max_implied_speed as f64) > realistic_max,
                "{mode:?} ceiling {} m/s would clip a genuine {realistic_max} m/s",
                t.max_implied_speed,
            );
        }
    }

    #[test]
    fn low_confidence_reported_unknown() {
        // Ambiguous: mid speed, no matching cadence rule.
        let (m, _) = classify_instant(win(0.5, 0.9, 0.3), 22.0 / 3.6);
        // 22 km/h, cadence 0.9 < 1.6 ⇒ Cycling actually matches; pick a true gap:
        let _ = m;
        let (m2, c2) = classify_instant(win(0.5, 2.2, 0.3), 22.0 / 3.6);
        // 22 km/h with cadence 2.2: no vehicle (<25), no walk (speed>9), no run
        // (speed>20), cycling needs cadence<1.6 ⇒ Unknown.
        assert_eq!(m2, TransportMode::Unknown);
        assert_eq!(c2, 0.0);
    }
}
