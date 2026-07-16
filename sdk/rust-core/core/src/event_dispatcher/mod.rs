use crate::database::DatabaseManager;
use crate::state::engine_state::EngineState;
use std::sync::Arc;

#[derive(uniffi::Object)]
pub struct EventDispatcher {
    db: Arc<DatabaseManager>,
    state: Arc<EngineState>,
}

#[uniffi::export]
impl EventDispatcher {
    #[uniffi::constructor]
    pub fn new(db: Arc<DatabaseManager>, state: Arc<EngineState>) -> Self {
        Self { db, state }
    }

    /// Primary entry point for Native Shells (Android/iOS) to feed OS locations into the Rust Core.
    /// Returns true if the location was accepted and processed, false if discarded (e.g., due to accuracy filter).
    pub fn on_location_update(&self, uuid: Option<String>, lat: f64, lng: f64, accuracy: f64, speed: f64, heading: f64, altitude: f64, is_mock: bool, is_moving: bool, timestamp: Option<String>) -> bool {
        let config = self.state.get_config();
        crate::logger::info(&format!("[Rust Core] 📍 on_location_update received: ({}, {}), acc={:.1}m, speed={:.2}m/s, heading={:.1}°", lat, lng, accuracy, speed, heading));

        // 1. Basic Filtering
        if config.geo.desired_accuracy >= 0 && accuracy > 100.0 {
            crate::logger::warn(&format!("[Rust Core] ⚠️ Location discarded due to low accuracy ({}m > 100m limit)", accuracy));
            return false;
        }

        let activity = self.state.get_health().current_activity;
        let route_context = self.state.get_route_context();

        // 2. Persist to Database
        // HealthState tracks no activity confidence — unknown at this layer (#245).
        if let Err(e) = self.db.insert_location(uuid, lat, lng, accuracy, speed, heading, altitude, is_mock, is_moving, &activity, -1, route_context, timestamp, None, None, None) {
            crate::logger::error(&format!("[Rust Core] ❌ Failed to insert location into database: {}", e));
            return false;
        }
        crate::logger::info("[Rust Core] 💾 Location persisted to local SQLite database successfully.");

        true
    }
}
