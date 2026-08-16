use std::sync::Mutex;

/// How far the measured drain must sit from the target before the engine calls
/// a window over- or under-budget at all (%/hr).
const ERROR_THRESHOLD: f64 = 0.5;

/// Consecutive conclusive windows in the same direction before the level moves.
///
/// One window is not evidence. A single over-budget reading used to be enough
/// to throttle, which is how a walk that had barely started arrived at a 100 m
/// accuracy tier: nothing had to persist, so nothing had to be true (#393).
const DWELL_WINDOWS: i32 = 2;

/// Shortest interval the engine will draw a drain figure from (seconds).
///
/// Battery level is quantized — iOS reports it in 5 % steps — so a short window
/// measures the reporting granularity rather than the drain. At the 5-minute
/// sample interval the hosts use, one step read as 60 %/hr, twenty times a
/// 3 %/hr budget, on a device that was draining normally (#393).
const MIN_MEASUREMENT_WINDOW_SEC: f64 = 900.0;

/// Longest a baseline may stand before it is abandoned as too old to be about
/// the current session's behaviour (seconds).
const MAX_MEASUREMENT_WINDOW_SEC: f64 = 4.0 * 3600.0;

/// Assumed battery-level reporting step (percentage points) when the host does
/// not say. iOS is the coarse one at 5 %; Android reports whole percents.
const DEFAULT_LEVEL_QUANTUM_PERCENT: f64 = 5.0;

/// Highest rung of the throttle ladder.
const MAX_THROTTLE_LEVEL: i32 = 4;

/// An event generated when the battery budget engine decides to throttle or modify tracking parameters.
///
/// The field set is deliberately unchanged from the pre-ladder engine: it
/// crosses the flutter_rust_bridge boundary as well as the uniffi one, and its
/// wire layout is baked into committed generated code. The ladder's own
/// vocabulary lives on [`BudgetThrottleState`], which native hosts read through
/// [`BatteryBudgetEngine::throttle_state`].
#[derive(uniffi::Record, Debug, Clone, Copy)]
pub struct BudgetAdjustmentEvent {
    pub current_battery_drain: f64,
    pub target_budget: f64,
    pub new_distance_filter: f64,
    pub new_desired_accuracy: i32,
    pub new_periodic_interval: Option<i32>,
}

/// Everything the ladder decided, for hosts to apply and for the bug report to
/// show.
///
/// This is an **overlay**, not a configuration. The host's own `distanceFilter`,
/// `desiredAccuracy` and `periodicLocationInterval` are left exactly where the
/// app put them; these values sit on top for as long as the throttle is in
/// force and evaporate when it lifts. The previous engine wrote its output back
/// into the live config, which destroyed the app's `distanceFilter: 0` opt-out
/// permanently and left `Tracelet.activeConfig` — and every bug report built
/// from it — describing a configuration the app had never asked for (#393).
#[derive(uniffi::Record, Debug, Clone, Copy)]
pub struct BudgetThrottleState {
    /// 0 = not throttled, 4 = most aggressive.
    pub level: i32,
    /// Distance filter to hand the *platform* (m). Never below the configured
    /// value, and never applied to the location processor's own gate: this
    /// thins how often the OS reports, it does not discard fixes already paid
    /// for.
    pub distance_filter: f64,
    /// Accuracy tier index to request from the platform (0 = best).
    pub desired_accuracy: i32,
    /// Periodic-mode interval (s), when the host is in periodic mode.
    pub periodic_interval: Option<i32>,
    /// What the host should multiply its own update cadence by.
    pub cadence_multiplier: f64,
    /// Floor to install under the tracking accuracy gate (m), so fixes the
    /// ladder has just made coarser are not then discarded for being coarse.
    /// `0` when the ladder has not touched accuracy.
    pub tracking_accuracy_floor: i32,
    /// Drain that produced the current level (%/hr), for reporting.
    pub last_drain: f64,
    /// Width of the window `last_drain` was measured over (s).
    pub last_measurement_seconds: f64,
    /// The %/hr that one quantization step represents over that window — the
    /// resolution of the measurement, and the amount by which a drain figure
    /// must beat the budget before it is believed.
    pub last_measurement_resolution: f64,
}

struct BatteryEngineState {
    level: i32,
    configured_distance_filter: f64,
    configured_accuracy_index: i32,
    configured_periodic_interval: Option<i32>,
    level_quantum_percent: f64,
    baseline_level: Option<f64>,
    baseline_time_ms: Option<i64>,
    over_budget_windows: i32,
    under_budget_windows: i32,
    last_drain: f64,
    last_measurement_seconds: f64,
    last_measurement_resolution: f64,
}

/// Keeps a tracking session inside a battery budget by stepping through a
/// bounded ladder of sampling costs.
///
/// The ladder replaces an unbounded multiplication. The previous engine
/// multiplied the distance filter by 1.5 and coarsened the accuracy tier on
/// every over-budget sample, with no dwell, no ceiling relative to the app's
/// configuration, and a recovery factor too weak to undo either — so a session
/// that throttled once kept throttling until it recorded nothing at all, which
/// is a worse outcome for the app than the drain it was avoiding (#396).
///
/// Three rules shape it:
///
/// 1. **Cadence before fidelity.** Rungs 1 and 2 only ask the platform to report
///    less often. Accuracy — the knob that decides whether a fix is usable —
///    is touched at rung 3 and beyond, and only together with a matching floor
///    under the tracking accuracy gate, so the SDK never spends power producing
///    positions its own filter will discard.
/// 2. **Evidence before action.** A level moves after [`DWELL_WINDOWS`]
///    consecutive conclusive windows, where a window is conclusive only if the
///    drain beats the budget by more than the measurement's own resolution.
/// 3. **Symmetry.** The ladder comes back down on the same evidence it went up
///    on, and drops to zero the moment the device is on a charger.
#[derive(uniffi::Object)]
pub struct BatteryBudgetEngine {
    target_budget_per_hour: f64,
    state: Mutex<BatteryEngineState>,
}

#[uniffi::export]
impl BatteryBudgetEngine {
    /// Initializes the engine with the app's configured tracking parameters.
    ///
    /// The parameters are remembered as the *floor* of the ladder rather than as
    /// a starting point to multiply: every rung is expressed relative to them,
    /// so throttling can never take a session below what the app asked for and
    /// `restore`-ing to level 0 always lands back on the app's own values.
    #[uniffi::constructor]
    pub fn new(
        target_budget_per_hour: f64,
        initial_distance_filter: f64,
        initial_accuracy_index: i32,
        initial_periodic_interval: Option<i32>,
    ) -> Self {
        Self {
            target_budget_per_hour,
            state: Mutex::new(BatteryEngineState {
                level: 0,
                configured_distance_filter: initial_distance_filter,
                configured_accuracy_index: initial_accuracy_index.clamp(0, 4),
                configured_periodic_interval: initial_periodic_interval,
                level_quantum_percent: DEFAULT_LEVEL_QUANTUM_PERCENT,
                baseline_level: None,
                baseline_time_ms: None,
                over_budget_windows: 0,
                under_budget_windows: 0,
                last_drain: 0.0,
                last_measurement_seconds: 0.0,
                last_measurement_resolution: 0.0,
            }),
        }
    }

    /// Tells the engine how coarsely this platform reports battery level, in
    /// percentage points.
    ///
    /// Sets the resolution of every drain figure the engine computes: a window
    /// can only resolve drain to within one step per elapsed hour. iOS steps in
    /// 5 %, Android in 1 %, and getting this wrong in the optimistic direction
    /// is what made a normal discharge look like 60 %/hr (#393).
    pub fn set_level_quantum_percent(&self, quantum: f64) {
        let mut state = self.state.lock().unwrap();
        state.level_quantum_percent = if quantum > 0.0 {
            quantum
        } else {
            DEFAULT_LEVEL_QUANTUM_PERCENT
        };
    }

    /// Re-reads the app's configured parameters, e.g. after `setConfig`.
    ///
    /// The overlay is recomputed from the new values immediately, so a config
    /// change during an active throttle takes effect without waiting for the
    /// ladder to move.
    pub fn set_configured(
        &self,
        distance_filter: f64,
        accuracy_index: i32,
        periodic_interval: Option<i32>,
    ) {
        let mut state = self.state.lock().unwrap();
        state.configured_distance_filter = distance_filter;
        state.configured_accuracy_index = accuracy_index.clamp(0, 4);
        state.configured_periodic_interval = periodic_interval;
    }

    /// Processes a new battery sample, returning an adjustment when the ladder
    /// moves.
    ///
    /// Returns `None` — with no state change beyond the accumulating baseline —
    /// whenever the evidence is not there yet, which is the overwhelming
    /// majority of samples.
    pub fn process_sample(&self, battery_level: f64, now_ms: i64) -> Option<BudgetAdjustmentEvent> {
        let mut state = self.state.lock().unwrap();

        let (baseline_level, baseline_time) =
            match (state.baseline_level, state.baseline_time_ms) {
                (Some(l), Some(t)) => (l, t),
                _ => {
                    state.baseline_level = Some(battery_level);
                    state.baseline_time_ms = Some(now_ms);
                    return None;
                }
            };

        let elapsed_sec = (now_ms - baseline_time) as f64 / 1000.0;

        // A baseline from the future, or from a clock that moved backwards, is
        // not a measurement. Restart from here.
        if elapsed_sec <= 0.0 {
            state.baseline_level = Some(battery_level);
            state.baseline_time_ms = Some(now_ms);
            return None;
        }

        // Too soon to tell drain from quantization. Hold the baseline rather
        // than resetting it — the window widening is exactly what eventually
        // makes the measurement conclusive.
        if elapsed_sec < MIN_MEASUREMENT_WINDOW_SEC {
            return None;
        }

        let hours = elapsed_sec / 3600.0;
        let drain_per_hour = (baseline_level - battery_level) * 100.0 / hours;
        // One reporting step, expressed as a rate over this window. Any drain
        // figure is only meaningful to within this much.
        let resolution = state.level_quantum_percent / hours;

        state.last_drain = drain_per_hour;
        state.last_measurement_seconds = elapsed_sec;
        state.last_measurement_resolution = resolution;

        // Charging, or a level that moved the wrong way: not a drain window.
        if drain_per_hour <= 0.0 {
            state.baseline_level = Some(battery_level);
            state.baseline_time_ms = Some(now_ms);
            state.over_budget_windows = 0;
            return self.step_down(&mut state, now_ms, battery_level, "under-budget");
        }

        let target = self.target_budget_per_hour;
        // The drain must beat the budget by more than the measurement can
        // resolve. Below that the reading is indistinguishable from the
        // reporting step, and acting on it is acting on noise.
        let confidently_over = drain_per_hour - resolution > target + ERROR_THRESHOLD;
        let confidently_under = drain_per_hour + resolution < target - ERROR_THRESHOLD;

        if !confidently_over && !confidently_under {
            // Inconclusive. Keep the baseline so the window — and with it the
            // resolution — improves, up to the point where the baseline is too
            // old to describe the session any more.
            state.over_budget_windows = 0;
            state.under_budget_windows = 0;
            if elapsed_sec >= MAX_MEASUREMENT_WINDOW_SEC {
                state.baseline_level = Some(battery_level);
                state.baseline_time_ms = Some(now_ms);
            }
            return None;
        }

        state.baseline_level = Some(battery_level);
        state.baseline_time_ms = Some(now_ms);

        if confidently_over {
            state.under_budget_windows = 0;
            state.over_budget_windows += 1;
            if state.over_budget_windows < DWELL_WINDOWS || state.level >= MAX_THROTTLE_LEVEL {
                return None;
            }
            state.over_budget_windows = 0;
            state.level += 1;
            return Some(Self::event_for(&state, drain_per_hour, target));
        }

        state.over_budget_windows = 0;
        self.step_down(&mut state, now_ms, battery_level, "under-budget")
    }

    /// Drops the ladder straight to level 0 because the device is on external
    /// power, returning an event when that changed anything.
    ///
    /// Hosts call this instead of skipping the sample outright: a charging
    /// device has no reason to carry a throttle, and the pre-ladder engine left
    /// one in force for the rest of the session because it simply returned
    /// early.
    pub fn note_charging(&self, now_ms: i64) -> Option<BudgetAdjustmentEvent> {
        let mut state = self.state.lock().unwrap();
        state.baseline_level = None;
        state.baseline_time_ms = Some(now_ms);
        state.over_budget_windows = 0;
        state.under_budget_windows = 0;
        if state.level == 0 {
            return None;
        }
        state.level = 0;
        let drain = state.last_drain;
        Some(Self::event_for(&state, drain, self.target_budget_per_hour))
    }

    /// Discards all historical battery samples and resets the baseline for budget calculations.
    ///
    /// Leaves the ladder where it is: a `stop()`/`start()` pair does not make a
    /// device that was draining fast start draining slowly, and re-deciding from
    /// scratch is how the old engine's ratchet kept finding new ground.
    pub fn reset(&self) {
        let mut state = self.state.lock().unwrap();
        state.baseline_level = None;
        state.baseline_time_ms = None;
        state.over_budget_windows = 0;
        state.under_budget_windows = 0;
    }

    /// Returns the ladder to level 0 and forgets the measurement history.
    pub fn clear_throttle(&self) {
        let mut state = self.state.lock().unwrap();
        state.level = 0;
        state.baseline_level = None;
        state.baseline_time_ms = None;
        state.over_budget_windows = 0;
        state.under_budget_windows = 0;
    }

    /// The current rung, 0 (untouched) to 4 (most aggressive).
    pub fn throttle_level(&self) -> i32 {
        self.state.lock().unwrap().level
    }

    /// Everything the ladder currently imposes — see [`BudgetThrottleState`].
    pub fn throttle_state(&self) -> BudgetThrottleState {
        let state = self.state.lock().unwrap();
        Self::overlay(&state)
    }

    /// Returns the currently enforced distance filter (in meters).
    pub fn distance_filter(&self) -> f64 {
        let state = self.state.lock().unwrap();
        Self::overlay(&state).distance_filter
    }

    /// Returns the currently enforced accuracy index (0 = highest).
    pub fn accuracy_index(&self) -> i32 {
        let state = self.state.lock().unwrap();
        Self::overlay(&state).desired_accuracy
    }

    /// Returns the currently enforced periodic interval (if any).
    pub fn periodic_interval(&self) -> Option<i32> {
        let state = self.state.lock().unwrap();
        Self::overlay(&state).periodic_interval
    }
}

impl BatteryBudgetEngine {
    /// One rung down, if there is one and the evidence has accumulated.
    fn step_down(
        &self,
        state: &mut BatteryEngineState,
        now_ms: i64,
        battery_level: f64,
        _reason: &str,
    ) -> Option<BudgetAdjustmentEvent> {
        state.baseline_level = Some(battery_level);
        state.baseline_time_ms = Some(now_ms);
        state.under_budget_windows += 1;
        if state.under_budget_windows < DWELL_WINDOWS || state.level == 0 {
            return None;
        }
        state.under_budget_windows = 0;
        state.level -= 1;
        let drain = state.last_drain;
        Some(Self::event_for(state, drain, self.target_budget_per_hour))
    }

    fn event_for(
        state: &BatteryEngineState,
        drain_per_hour: f64,
        target: f64,
    ) -> BudgetAdjustmentEvent {
        let overlay = Self::overlay(state);
        BudgetAdjustmentEvent {
            current_battery_drain: drain_per_hour,
            target_budget: target,
            new_distance_filter: overlay.distance_filter,
            new_desired_accuracy: overlay.desired_accuracy,
            new_periodic_interval: overlay.periodic_interval,
        }
    }

    /// The ladder itself.
    ///
    /// | level | platform distance filter | accuracy tier | cadence | accuracy gate floor |
    /// |---|---|---|---|---|
    /// | 0 | configured | configured | ×1 | none |
    /// | 1 | ≥ 10 m | configured | ×1.5 | none |
    /// | 2 | ≥ 25 m | configured | ×2 | none |
    /// | 3 | ≥ 50 m | ≥ index 1 | ×3 | matches the tier |
    /// | 4 | ≥ 100 m | ≥ index 2 | ×4 | matches the tier |
    ///
    /// Levels 1 and 2 leave accuracy alone deliberately. On iOS the tier below
    /// `kCLLocationAccuracyBest` is `kCLLocationAccuracyHundredMeters` — a
    /// hundredfold degradation in a single step, and the step the old engine
    /// took first. Against a Walking auto-tune's 15 m tracking gate that
    /// guaranteed every subsequent fix would be rejected, which is how a
    /// throttle intended to save battery ended up recording nothing at all.
    fn overlay(state: &BatteryEngineState) -> BudgetThrottleState {
        let level = state.level.clamp(0, MAX_THROTTLE_LEVEL);
        let (floor_distance, accuracy_bump, cadence) = match level {
            0 => (0.0, 0, 1.0),
            1 => (10.0, 0, 1.5),
            2 => (25.0, 0, 2.0),
            3 => (50.0, 1, 3.0),
            _ => (100.0, 2, 4.0),
        };

        let distance_filter = state.configured_distance_filter.max(floor_distance);
        let desired_accuracy = state
            .configured_accuracy_index
            .max(accuracy_bump)
            .clamp(0, 4);
        let periodic_interval = state.configured_periodic_interval.map(|interval| {
            ((interval as f64 * cadence) as i32).clamp(60, 43_200)
        });
        // Only claim a floor when the ladder actually coarsened the request. A
        // floor at level 0-2 would silently loosen a gate the app chose.
        let tracking_accuracy_floor = if desired_accuracy > state.configured_accuracy_index {
            Self::accuracy_tier_metres(desired_accuracy)
        } else {
            0
        };

        BudgetThrottleState {
            level,
            distance_filter,
            desired_accuracy,
            periodic_interval,
            cadence_multiplier: cadence,
            tracking_accuracy_floor,
            last_drain: state.last_drain,
            last_measurement_seconds: state.last_measurement_seconds,
            last_measurement_resolution: state.last_measurement_resolution,
        }
    }

    /// Roughly what each accuracy tier delivers, in metres.
    ///
    /// Used as the floor under the tracking accuracy gate so a coarsened request
    /// cannot produce fixes the filter then throws away. The values follow the
    /// hosts' own tier mapping (`kCLLocationAccuracyBest`,
    /// `…HundredMeters`, `…Kilometer`, `…ThreeKilometers`, reduced).
    fn accuracy_tier_metres(index: i32) -> i32 {
        match index {
            0 => 0,
            1 => 100,
            2 => 1_000,
            3 => 3_000,
            _ => 5_000,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const MINUTE_MS: i64 = 60_000;

    fn engine(budget: f64) -> BatteryBudgetEngine {
        let e = BatteryBudgetEngine::new(budget, 0.0, 0, Some(300));
        e.set_level_quantum_percent(5.0);
        e
    }

    /// The field failure: two samples five minutes apart, one 5 % reporting
    /// step between them, read as 60 %/hr against a 3 %/hr budget (#393).
    #[test]
    fn a_single_quantization_step_does_not_throttle() {
        let e = engine(3.0);
        assert!(e.process_sample(0.25, 0).is_none());
        assert!(e.process_sample(0.20, 5 * MINUTE_MS).is_none());
        assert_eq!(e.throttle_level(), 0, "throttled on one reporting step");
    }

    /// The same step, given long enough to be a real measurement, still is not
    /// enough on its own: 5 % over an hour is 5 %/hr against a 5 %/hr
    /// resolution, so it cannot beat the budget by more than it can resolve.
    #[test]
    fn a_quantization_step_over_an_hour_is_still_inconclusive() {
        let e = engine(3.0);
        assert!(e.process_sample(0.50, 0).is_none());
        assert!(e.process_sample(0.45, 60 * MINUTE_MS).is_none());
        assert_eq!(e.throttle_level(), 0);
    }

    #[test]
    fn sustained_heavy_drain_climbs_one_rung_at_a_time() {
        let e = engine(3.0);
        // 30 %/hr: 15 % over 30 minutes, comfortably past the 10 %/hr
        // resolution such a window affords.
        assert!(e.process_sample(0.90, 0).is_none());
        assert!(
            e.process_sample(0.75, 30 * MINUTE_MS).is_none(),
            "one conclusive window is not a dwell"
        );
        assert_eq!(e.throttle_level(), 0);

        let event = e.process_sample(0.60, 60 * MINUTE_MS);
        assert!(event.is_some(), "second conclusive window moves the ladder");
        assert_eq!(e.throttle_level(), 1);

        assert!(e.process_sample(0.45, 90 * MINUTE_MS).is_none());
        assert!(e.process_sample(0.30, 120 * MINUTE_MS).is_some());
        assert_eq!(e.throttle_level(), 2, "one rung per dwell, never two");
    }

    /// The opt-out `retune` protects must survive the budget engine too — the
    /// old one clamped it up to 10 m and wrote that into the app's config
    /// (#393).
    #[test]
    fn a_configured_distance_filter_of_zero_survives_level_zero() {
        let e = engine(3.0);
        assert_eq!(e.throttle_state().distance_filter, 0.0);
        assert_eq!(e.throttle_state().level, 0);
    }

    #[test]
    fn the_ladder_never_goes_below_the_configured_values() {
        let e = BatteryBudgetEngine::new(3.0, 250.0, 2, Some(600));
        e.set_level_quantum_percent(5.0);
        e.process_sample(0.90, 0);
        e.process_sample(0.75, 30 * MINUTE_MS);
        e.process_sample(0.60, 60 * MINUTE_MS);
        assert_eq!(e.throttle_level(), 1);
        let overlay = e.throttle_state();
        assert_eq!(
            overlay.distance_filter, 250.0,
            "a configured filter wider than the rung stands"
        );
        assert_eq!(
            overlay.desired_accuracy, 2,
            "a configured tier coarser than the rung stands"
        );
    }

    #[test]
    fn accuracy_is_untouched_until_rung_three_and_then_carries_a_gate_floor() {
        let e = engine(3.0);
        for rung in 1..=4 {
            // Two conclusive 30-minute windows per rung.
            let base = (rung as i64 - 1) * 60 * MINUTE_MS;
            e.process_sample(0.90, base);
            e.process_sample(0.75, base + 30 * MINUTE_MS);
            e.process_sample(0.60, base + 60 * MINUTE_MS);
            let overlay = e.throttle_state();
            assert_eq!(overlay.level, rung.min(4));
            match overlay.level {
                1 | 2 => {
                    assert_eq!(overlay.desired_accuracy, 0, "cadence first, fidelity later");
                    assert_eq!(overlay.tracking_accuracy_floor, 0);
                }
                _ => {
                    assert!(overlay.desired_accuracy >= 1);
                    assert!(
                        overlay.tracking_accuracy_floor >= 100,
                        "a coarsened request must relax the gate it will be judged by"
                    );
                }
            }
        }
    }

    #[test]
    fn the_ladder_comes_back_down_when_the_drain_does() {
        let e = engine(3.0);
        e.process_sample(0.90, 0);
        e.process_sample(0.75, 30 * MINUTE_MS);
        e.process_sample(0.60, 60 * MINUTE_MS);
        assert_eq!(e.throttle_level(), 1);

        // 1 %/hr over two hours: resolution is 2.5 %/hr, so 1 + 2.5 < 3 - 0.5
        // is false — deliberately not conclusive. Four hours resolves it.
        e.process_sample(0.60, 60 * MINUTE_MS + 240 * MINUTE_MS);
        e.process_sample(0.56, 60 * MINUTE_MS + 480 * MINUTE_MS);
        assert_eq!(e.throttle_level(), 0, "recovery uses the same evidence bar");
    }

    #[test]
    fn charging_lifts_the_throttle_immediately() {
        let e = engine(3.0);
        e.process_sample(0.90, 0);
        e.process_sample(0.75, 30 * MINUTE_MS);
        e.process_sample(0.60, 60 * MINUTE_MS);
        assert_eq!(e.throttle_level(), 1);

        let event = e.note_charging(61 * MINUTE_MS);
        assert!(event.is_some());
        assert_eq!(e.throttle_level(), 0);
        assert!(
            e.note_charging(62 * MINUTE_MS).is_none(),
            "no event when there was nothing to lift"
        );
    }

    /// An inconclusive window must not throw its baseline away: holding it is
    /// what lets the window widen, and a wider window resolves a smaller drain.
    /// Resetting on every sample would pin the resolution at whatever a single
    /// sample interval affords — 20 %/hr at the hosts' five minutes — and no
    /// ordinary drain could ever clear that bar.
    #[test]
    fn an_inconclusive_window_widens_instead_of_resetting() {
        let e = engine(3.0);
        e.process_sample(0.50, 0);

        // 20 minutes at 3 %/hr: on budget, and the window can only resolve
        // 15 %/hr anyway.
        assert!(e.process_sample(0.49, 20 * MINUTE_MS).is_none());

        // Measured from t=0 rather than from the inconclusive sample.
        assert!(e.process_sample(0.44, 240 * MINUTE_MS).is_none());
        let state = e.throttle_state();
        assert_eq!(
            state.last_measurement_seconds, 14_400.0,
            "the baseline was reset by an inconclusive window"
        );
        assert!(
            (state.last_measurement_resolution - 1.25).abs() < 1e-9,
            "a four-hour window resolves 1.25 %/hr, not 15"
        );
    }

    /// Two conclusive windows still have to be *consecutive*: an inconclusive
    /// one in between means the drain did not persist.
    #[test]
    fn an_inconclusive_window_breaks_the_dwell() {
        let e = engine(3.0);
        e.process_sample(0.90, 0);
        assert!(e.process_sample(0.75, 30 * MINUTE_MS).is_none());

        // 3 %/hr over the next half hour — on budget, and inconclusive.
        assert!(e.process_sample(0.735, 60 * MINUTE_MS).is_none());

        // Heavy again, but this is window one of a new streak.
        assert!(e.process_sample(0.60, 90 * MINUTE_MS).is_none());
        assert_eq!(e.throttle_level(), 0);
        assert!(e.process_sample(0.45, 120 * MINUTE_MS).is_some());
        assert_eq!(e.throttle_level(), 1);
    }
}
