use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// The central configuration struct for the Tracelet Engine.
/// This struct holds all tracking, network, and persistence parameters.
/// It acts as the single source of truth for the SDK's behavior across platforms.
#[derive(Debug, Clone, Serialize, Deserialize, uniffi::Record)]
#[serde(rename_all = "camelCase")]
pub struct EngineConfig {
    /// Geolocation tracking parameters (accuracy, filters, intervals).
    #[serde(default)]
    pub geo: GeoConfig,
    /// Motion detection and activity recognition parameters.
    #[serde(default)]
    pub motion: MotionConfig,
    /// HTTP synchronization and batching parameters for server communication.
    #[serde(default)]
    pub http: HttpConfig,
    /// Geofencing parameters for proximity alerts and tracking boundaries.
    #[serde(default)]
    pub geofence: GeofenceConfig,
    /// Local database persistence parameters for locations and events.
    #[serde(default)]
    pub persistence: PersistenceConfig,
    /// Security audit trail parameters for tracking data integrity.
    #[serde(default)]
    pub audit: AuditConfig,
    /// Core security parameters (e.g., database encryption).
    #[serde(default)]
    pub security: SecurityConfig,
    /// Device attestation and anti-spoofing parameters.
    #[serde(default)]
    pub attestation: AttestationConfig,
}

impl Default for EngineConfig {
    fn default() -> Self {
        Self {
            geo: GeoConfig::default(),
            motion: MotionConfig::default(),
            http: HttpConfig::default(),
            geofence: GeofenceConfig::default(),
            persistence: PersistenceConfig::default(),
            audit: AuditConfig::default(),
            security: SecurityConfig::default(),
            attestation: AttestationConfig::default(),
        }
    }
}

/// Configuration for geolocation tracking behavior.
#[derive(Debug, Clone, Serialize, Deserialize, uniffi::Record)]
#[serde(rename_all = "camelCase")]
pub struct GeoConfig {
    /// Desired accuracy for tracking (e.g., 0 = High, 1 = Medium).
    #[serde(default = "default_desired_accuracy")]
    pub desired_accuracy: i32,
    /// Minimum distance (in meters) the device must move before a location update is generated.
    #[serde(default = "default_distance_filter")]
    pub distance_filter: f64,
    /// Radius (in meters) around the stationary location to detect when movement resumes.
    #[serde(default = "default_stationary_radius")]
    pub stationary_radius: f64,
    /// Maximum time (in seconds) to wait for a location fix before falling back.
    #[serde(default = "default_location_timeout")]
    pub location_timeout: i32,
    /// If true, disables the dynamic adjustment of the distance filter based on speed.
    #[serde(default)]
    pub disable_elasticity: bool,
    /// Multiplier applied to speed to calculate the elastic distance filter.
    #[serde(default = "default_elasticity_multiplier")]
    pub elasticity_multiplier: f64,
    /// If true, enables battery-saving modes that dynamically degrade accuracy based on battery state.
    #[serde(default)]
    pub enable_adaptive_mode: bool,
    /// If true, includes OS-level timestamps as meta fields in location events.
    #[serde(default)]
    pub enable_timestamp_meta: bool,
    /// If true, locations that do not meet the distance threshold are still recorded if time elapsed exceeds max idle.
    #[serde(default)]
    pub enable_sparse_updates: bool,
    /// Distance threshold (in meters) used to calculate sparse update eligibility.
    #[serde(default = "default_sparse_distance_threshold")]
    pub sparse_distance_threshold: f64,
    /// Auto-stop tracking after this many minutes.
    #[serde(default = "default_stop_after_elapsed_minutes")]
    pub stop_after_elapsed_minutes: i32,
    /// Maximum monitored geofences.
    #[serde(default = "default_max_monitored_geofences")]
    pub max_monitored_geofences: i32,
    /// Periodic location interval.
    #[serde(default = "default_periodic_location_interval")]
    pub periodic_location_interval: i32,
    /// Periodic desired accuracy.
    #[serde(default = "default_periodic_desired_accuracy")]
    pub periodic_desired_accuracy: i32,
    /// Sparse max idle seconds.
    #[serde(default = "default_sparse_max_idle_seconds")]
    pub sparse_max_idle_seconds: i32,
    /// Battery budget per hour.
    #[serde(default)]
    pub battery_budget_per_hour: f64,
    /// Enable dead reckoning.
    #[serde(default)]
    pub enable_dead_reckoning: bool,
    /// Dead reckoning activation delay.
    #[serde(default)]
    pub dead_reckoning_activation_delay: i32,
    /// Dead reckoning max duration.
    #[serde(default)]
    pub dead_reckoning_max_duration: i32,
    /// Resolve address.
    #[serde(default)]
    pub resolve_address: bool,
}

fn default_desired_accuracy() -> i32 { 0 } // High
fn default_distance_filter() -> f64 { 10.0 }
fn default_stationary_radius() -> f64 { 25.0 }
fn default_location_timeout() -> i32 { 60 }
fn default_elasticity_multiplier() -> f64 { 1.0 }
fn default_sparse_distance_threshold() -> f64 { 50.0 }
fn default_stop_after_elapsed_minutes() -> i32 { -1 }
fn default_max_monitored_geofences() -> i32 { -1 }
fn default_periodic_location_interval() -> i32 { 900 }
fn default_periodic_desired_accuracy() -> i32 { 1 }
fn default_sparse_max_idle_seconds() -> i32 { 300 }

impl Default for GeoConfig {
    fn default() -> Self {
        Self {
            desired_accuracy: default_desired_accuracy(),
            distance_filter: default_distance_filter(),
            stationary_radius: default_stationary_radius(),
            location_timeout: default_location_timeout(),
            disable_elasticity: false,
            elasticity_multiplier: default_elasticity_multiplier(),
            enable_adaptive_mode: false,
            enable_timestamp_meta: false,
            enable_sparse_updates: false,
            sparse_distance_threshold: default_sparse_distance_threshold(),
            stop_after_elapsed_minutes: default_stop_after_elapsed_minutes(),
            max_monitored_geofences: default_max_monitored_geofences(),
            periodic_location_interval: default_periodic_location_interval(),
            periodic_desired_accuracy: default_periodic_desired_accuracy(),
            sparse_max_idle_seconds: default_sparse_max_idle_seconds(),
            battery_budget_per_hour: 0.0,
            enable_dead_reckoning: false,
            dead_reckoning_activation_delay: 0,
            dead_reckoning_max_duration: 0,
            resolve_address: false,
        }
    }
}

/// Configuration for motion and activity detection.
#[derive(Debug, Clone, Serialize, Deserialize, uniffi::Record)]
#[serde(rename_all = "camelCase")]
pub struct MotionConfig {
    /// Number of consecutive minutes a device must remain still to trigger a stationary event.
    #[serde(default = "default_stop_timeout")]
    pub stop_timeout: i32,
    /// Delay (in seconds) before a motion event is officially registered.
    #[serde(default = "default_motion_trigger_delay")]
    pub motion_trigger_delay: i32,
    /// If true, stops the OS activity recognition updates to save battery (relies only on speed/geofences).
    #[serde(default)]
    pub disable_motion_activity_updates: bool,
    /// If true, bypasses stop detection completely (device is considered always moving).
    #[serde(default)]
    pub disable_stop_detection: bool,
    /// Accelerometer threshold (G-force) required to wake the device from a stationary state.
    #[serde(default = "default_shake_threshold")]
    pub shake_threshold: f64,
    /// Is currently moving.
    #[serde(default)]
    pub is_moving: bool,
    /// Activity recognition interval.
    #[serde(default = "default_activity_recognition_interval")]
    pub activity_recognition_interval: i32,
    /// Minimum confidence for activity.
    #[serde(default = "default_min_activity_confidence")]
    pub minimum_activity_recognition_confidence: i32,
    /// Delay before stop detection.
    #[serde(default)]
    pub stop_detection_delay: i32,
    /// Stop on stationary.
    #[serde(default)]
    pub stop_on_stationary: bool,
    /// Stationary radius.
    #[serde(default = "default_stationary_radius")]
    pub stationary_radius: f64,
    /// Use significant changes only.
    #[serde(default)]
    pub use_significant_changes_only: bool,
    /// Still threshold.
    #[serde(default = "default_still_threshold")]
    pub still_threshold: f64,
    /// Still sample count.
    #[serde(default = "default_still_sample_count")]
    pub still_sample_count: i32,
    /// Motion detection mode.
    #[serde(default)]
    pub motion_detection_mode: i32,
    /// Speed moving threshold.
    #[serde(default = "default_speed_moving_threshold")]
    pub speed_moving_threshold: f64,
    /// Speed stationary delay.
    #[serde(default = "default_speed_stationary_delay")]
    pub speed_stationary_delay: i32,
    /// Stationary tracking mode.
    #[serde(default)]
    pub stationary_tracking_mode: i32,
    /// Stationary periodic interval.
    #[serde(default = "default_stationary_periodic_interval")]
    pub stationary_periodic_interval: i32,
    /// Stationary periodic accuracy.
    #[serde(default)]
    pub stationary_periodic_accuracy: i32,
    /// Speed wake confirm count.
    #[serde(default = "default_speed_wake_confirm_count")]
    pub speed_wake_confirm_count: i32,
}

fn default_stop_timeout() -> i32 { 5 }
fn default_motion_trigger_delay() -> i32 { 0 }
fn default_shake_threshold() -> f64 { 2.5 }
fn default_activity_recognition_interval() -> i32 { 1000 }
fn default_min_activity_confidence() -> i32 { 75 }
fn default_still_threshold() -> f64 { 0.4 }
fn default_still_sample_count() -> i32 { 25 }
fn default_speed_moving_threshold() -> f64 { 1.5 }
fn default_speed_stationary_delay() -> i32 { 180 }
fn default_stationary_periodic_interval() -> i32 { 120 }
fn default_speed_wake_confirm_count() -> i32 { 1 }

impl Default for MotionConfig {
    fn default() -> Self {
        Self {
            stop_timeout: default_stop_timeout(),
            motion_trigger_delay: default_motion_trigger_delay(),
            disable_motion_activity_updates: false,
            disable_stop_detection: false,
            shake_threshold: default_shake_threshold(),
            is_moving: false,
            activity_recognition_interval: default_activity_recognition_interval(),
            minimum_activity_recognition_confidence: default_min_activity_confidence(),
            stop_detection_delay: 0,
            stop_on_stationary: false,
            stationary_radius: default_stationary_radius(),
            use_significant_changes_only: false,
            still_threshold: default_still_threshold(),
            still_sample_count: default_still_sample_count(),
            motion_detection_mode: 0,
            speed_moving_threshold: default_speed_moving_threshold(),
            speed_stationary_delay: default_speed_stationary_delay(),
            stationary_tracking_mode: 0,
            stationary_periodic_interval: default_stationary_periodic_interval(),
            stationary_periodic_accuracy: 0,
            speed_wake_confirm_count: default_speed_wake_confirm_count(),
        }
    }
}

/// Configuration for syncing location and event data to a remote server.
#[derive(Debug, Clone, Serialize, Deserialize, Default, uniffi::Record)]
#[serde(rename_all = "camelCase")]
pub struct HttpConfig {
    /// Remote URL endpoint for HTTP sync. If None, auto-sync is disabled.
    pub url: Option<String>,
    /// HTTP Method (0 = POST, 1 = PUT).
    #[serde(default)]
    pub method: i32,
    /// Custom HTTP headers attached to synchronization requests.
    #[serde(default)]
    pub headers: HashMap<String, String>,
    /// If true, sends locations in a JSON array rather than individually.
    #[serde(default)]
    pub batch_sync: bool,
    /// Maximum number of records to send in a single batch.
    #[serde(default = "default_max_batch_size")]
    pub max_batch_size: i32,
    /// If true, automatically triggers HTTP sync operations based on internal thresholds.
    #[serde(default = "default_true")]
    pub auto_sync: bool,
    /// Maximum number of retries for a failed sync request.
    #[serde(default = "default_max_retries")]
    pub max_retries: i32,
    /// Base backoff time in milliseconds for exponential retry.
    #[serde(default = "default_retry_backoff_base")]
    pub retry_backoff_base: i32,
    /// Maximum backoff time in milliseconds for exponential retry.
    #[serde(default = "default_retry_backoff_cap")]
    pub retry_backoff_cap: i32,
    /// Delay in milliseconds before batching rapid location syncs (debounce time).
    #[serde(default = "default_auto_sync_delay")]
    pub auto_sync_delay: i32,
    /// Optional list of PEM or DER encoded certificates for SSL pinning.
    #[serde(default)]
    pub ssl_pinning_certificates: Option<Vec<String>>,
    /// Optional list of SHA-256 fingerprints (hex encoded) for SSL pinning.
    #[serde(default)]
    pub ssl_pinning_fingerprints: Option<Vec<String>>,
    /// Custom root property for the HTTP sync payload.
    #[serde(default)]
    pub http_root_property: Option<String>,
    /// Custom query parameters.
    #[serde(default)]
    pub params: Option<HashMap<String, String>>,
    /// Custom JSON fields to inject at the root of the sync payload.
    #[serde(default)]
    pub extras: Option<HashMap<String, String>>,
    /// Disable auto-syncing when on a cellular data network (syncs only on Wi-Fi).
    #[serde(default)]
    pub disable_auto_sync_on_cellular: bool,
    /// Enable delta-encoding compression for batch sync payloads.
    #[serde(default)]
    pub enable_delta_compression: bool,
    /// Coordinate decimal precision for delta compression.
    #[serde(default = "default_delta_coordinate_precision")]
    pub delta_coordinate_precision: i32,
    /// The chronological sort order for synced locations.
    #[serde(default)]
    pub locations_order_direction: i32,
    /// Auto sync threshold.
    #[serde(default)]
    pub auto_sync_threshold: i32,
    /// HTTP timeout in milliseconds.
    #[serde(default = "default_http_timeout")]
    pub http_timeout: i32,
    /// Sync interval in milliseconds.
    #[serde(default = "default_sync_interval")]
    pub sync_interval: i32,
    /// Enable syncing of telematics data.
    #[serde(default)]
    pub sync_telematics: bool,
    /// URL to sync telematics data to.
    #[serde(default)]
    pub telematics_url: Option<String>,
}

fn default_delta_coordinate_precision() -> i32 { 5 }

fn default_max_batch_size() -> i32 { 250 }
fn default_true() -> bool { true }
fn default_max_retries() -> i32 { 3 }
fn default_retry_backoff_base() -> i32 { 1000 }
fn default_retry_backoff_cap() -> i32 { 10000 }
fn default_auto_sync_delay() -> i32 { 10000 }
fn default_http_timeout() -> i32 { 60000 }
fn default_sync_interval() -> i32 { 900000 }

/// Configuration for monitoring geographic boundaries.
#[derive(Debug, Clone, Serialize, Deserialize, uniffi::Record)]
#[serde(rename_all = "camelCase")]
pub struct GeofenceConfig {
    /// Enable initial trigger evaluation for geofences on registration.
    #[serde(default = "default_true")]
    pub geofence_initial_trigger: bool,
    /// If true, fires an entry trigger immediately if the device is already inside the geofence when registered.
    #[serde(default = "default_true")]
    pub geofence_initial_trigger_entry: bool,
    /// The radius (in meters) for loading geofences from the database into the active monitoring queue.
    #[serde(default = "default_geofence_proximity_radius")]
    pub geofence_proximity_radius: i32,
}

fn default_geofence_proximity_radius() -> i32 { 1000 }

impl Default for GeofenceConfig {
    fn default() -> Self {
        Self {
            geofence_initial_trigger: true,
            geofence_initial_trigger_entry: true,
            geofence_proximity_radius: default_geofence_proximity_radius(),
        }
    }
}

/// Configuration for local SQLite database retention policies.
#[derive(Debug, Clone, Serialize, Deserialize, uniffi::Record)]
#[serde(rename_all = "camelCase")]
pub struct PersistenceConfig {
    /// Maximum number of days to retain tracking records before pruning. (-1 for infinite)
    #[serde(default = "default_max_days_to_persist")]
    pub max_days_to_persist: i32,
    /// Maximum number of absolute location records to keep. (-1 for infinite)
    #[serde(default = "default_max_records_to_persist")]
    pub max_records_to_persist: i32,
}

/// Kept in step with Dart's `PersistenceConfig.maxDaysToPersist` default. Was
/// `1` while the window was enforced by nothing; widened with #361, which made
/// it real, because a one-day window is too tight to switch on unannounced.
fn default_max_days_to_persist() -> i32 { 3 }
fn default_max_records_to_persist() -> i32 { -1 }

impl Default for PersistenceConfig {
    fn default() -> Self {
        Self {
            max_days_to_persist: default_max_days_to_persist(),
            max_records_to_persist: default_max_records_to_persist(),
        }
    }
}

/// Security feature configuration for generating tamper-evident cryptographic trails.
#[derive(Debug, Clone, Serialize, Deserialize, Default, uniffi::Record)]
#[serde(rename_all = "camelCase")]
pub struct AuditConfig {
    /// If true, location events are hashed to provide an audit trail.
    #[serde(default)]
    pub enabled: bool,
}

/// Core security and encryption configuration.
#[derive(Debug, Clone, Serialize, Deserialize, Default, uniffi::Record)]
#[serde(rename_all = "camelCase")]
pub struct SecurityConfig {
    /// If true, local SQLite databases are encrypted at rest (e.g., using SQLCipher).
    #[serde(default)]
    pub encrypt_database: bool,
}

/// Anti-spoofing and device validation configuration.
#[derive(Debug, Clone, Serialize, Deserialize, Default, uniffi::Record)]
#[serde(rename_all = "camelCase")]
pub struct AttestationConfig {
    /// If true, attestation tokens (Play Integrity/DeviceCheck) are gathered.
    #[serde(default)]
    pub enabled: bool,
}

impl EngineConfig {
    /// Deserializes a raw JSON string (usually originating from Dart `Config.toMap()`) 
    /// into a strongly-typed `EngineConfig` struct.
    pub fn from_json(json: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(json)
    }
}
