use crate::state::battery_budget::{BatteryBudgetEngine as NativeEngine, BudgetAdjustmentEvent};

/// Engine responsible for auto-adjusting tracking parameters to meet battery constraints.
pub struct BatteryBudgetEngineDart {
    inner: std::sync::Mutex<NativeEngine>,
    interval_ms: std::sync::Mutex<i64>,
    throttled: std::sync::Mutex<bool>,
    is_charging: std::sync::Mutex<bool>,
}

impl BatteryBudgetEngineDart {
    /// Creates a new BatteryBudgetEngine.
    #[flutter_rust_bridge::frb(sync)]
    pub fn new(
        target_budget_per_hour: f64,
        initial_distance_filter: f64,
        initial_accuracy_index: i32,
        initial_periodic_interval: Option<i32>,
    ) -> Self {
        Self {
            inner: std::sync::Mutex::new(NativeEngine::new(
                target_budget_per_hour,
                initial_distance_filter,
                initial_accuracy_index,
                initial_periodic_interval,
            )),
            interval_ms: std::sync::Mutex::new(0),
            throttled: std::sync::Mutex::new(false),
            is_charging: std::sync::Mutex::new(false),
        }
    }

    /// Feeds a new battery sample into the engine and returns an adjustment event if parameters changed.
    #[flutter_rust_bridge::frb(sync)]
    pub fn process_sample(&self, level: f64, is_charging: bool, timestamp_ms: i64) -> Option<BudgetAdjustmentEvent> {
        let inner = self.inner.lock().unwrap();
        let mut charging_state = self.is_charging.lock().unwrap();
        *charging_state = is_charging;
        
        // A charging device carries no throttle. The engine drops to level 0 and
        // says so, rather than the sample being skipped and a throttle from an
        // earlier discharge standing for the rest of the session (#396).
        let adjustment = if is_charging {
            inner.note_charging(timestamp_ms)
        } else {
            inner.process_sample(level, timestamp_ms)
        };
        if let Some(adj) = adjustment {
            if let Some(interval) = adj.new_periodic_interval {
                *self.interval_ms.lock().unwrap() = (interval as i64) * 1000;
            }
            // The ladder's own vocabulary, not a distance guessed back into a
            // level: rungs 3 and 4 are the ones that trade fidelity for power.
            *self.throttled.lock().unwrap() = inner.throttle_level() >= 3;
        }
        adjustment
    }

    /// Resets the engine, dropping historical battery samples.
    #[flutter_rust_bridge::frb(sync)]
    pub fn reset(&self) {
        let inner = self.inner.lock().unwrap();
        inner.reset();
        
        // We probably don't reset interval/throttled state here as they represent configuration,
        // but resetting the engine drops the baseline.
    }

    /// Returns the recommended tracking interval based on the latest battery adjustments.
    #[flutter_rust_bridge::frb(sync)]
    pub fn get_recommended_interval_ms(&self, default_interval_ms: i64) -> i64 {
        let interval = *self.interval_ms.lock().unwrap();
        if interval > 0 {
            interval
        } else {
            default_interval_ms
        }
    }

    /// Returns true if location tracking should be heavily throttled due to low battery budget.
    #[flutter_rust_bridge::frb(sync)]
    pub fn should_throttle_location(&self) -> bool {
        *self.throttled.lock().unwrap()
    }

    /// Returns true if the device is currently charging.
    #[flutter_rust_bridge::frb(sync)]
    pub fn is_charging(&self) -> bool {
        *self.is_charging.lock().unwrap()
    }

    /// Returns the active distance filter (in meters) calculated by the engine.
    #[flutter_rust_bridge::frb(sync)]
    pub fn get_distance_filter(&self) -> f64 {
        let inner = self.inner.lock().unwrap();
        inner.distance_filter()
    }

    /// Returns the active accuracy index (0 = highest) calculated by the engine.
    #[flutter_rust_bridge::frb(sync)]
    pub fn get_accuracy_index(&self) -> i32 {
        let inner = self.inner.lock().unwrap();
        inner.accuracy_index()
    }

    /// Returns the current periodic interval (if any) recommended by the engine.
    #[flutter_rust_bridge::frb(sync)]
    pub fn get_periodic_interval(&self) -> Option<i32> {
        let inner = self.inner.lock().unwrap();
        inner.periodic_interval()
    }
}
