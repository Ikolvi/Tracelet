use rusqlite::{params, Connection};
use std::sync::{Mutex, RwLock};
use crate::error::TraceletError;
use chrono::Utc;
use aes_gcm::{
    aead::{Aead, KeyInit, generic_array::GenericArray},
    Aes256Gcm, Nonce
};
use rand::{RngCore, rngs::OsRng};

// Import spatial and geo structures to expose them directly through DatabaseManager
use crate::spatial::geofence_evaluator::CoreGeofence;
use crate::spatial::privacy_zone::CorePrivacyZone;
use crate::algorithms::geo_utils::Coordinate;

#[derive(uniffi::Object)]
/// Central database manager handling standard SQLite and secure AES-256 encrypted storage.
/// Coordinates reading and writing of geofences, privacy zones, location history, and audit trail records.
pub struct DatabaseManager {
    conn: Mutex<Connection>,
    encryption_key: RwLock<Option<[u8; 32]>>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct LocationQuery {
    pub start_time_ms: Option<i64>,
    pub end_time_ms: Option<i64>,
    pub limit: Option<i32>,
    pub offset: Option<i32>,
    pub order_descending: Option<bool>,
}

#[derive(Debug, Clone, uniffi::Record)]
/// Represents a serialized historical location record fetched from database.
pub struct DbLocationRecord {
    pub id: i64,
    pub uuid: Option<String>,
    pub timestamp: String,
    pub latitude: f64,
    pub longitude: f64,
    pub accuracy: f64,
    pub speed: f64,
    pub heading: f64,
    pub altitude: f64,
    pub is_mock: bool,
    pub is_moving: bool,
    pub activity: String,
    /// Confidence (0–100) of `activity`; -1 when unknown/unset (#245).
    pub activity_confidence: i32,
    pub route_context: Option<String>,
    /// Event type for this record: "location" (default) or "geofence" (#128).
    pub event_type: String,
    /// Optional JSON payload with event-specific data (e.g. geofence identifier
    /// and action). `None` for plain location records.
    pub event_payload: Option<String>,
    /// Optional reverse-geocoded address as a JSON object string (e.g.
    /// `{"street":..,"city":..,"state":..,"postalCode":..,"country":..}`).
    /// Populated when `resolveAddress` is enabled (#187). `None` otherwise.
    pub address: Option<String>,
}

#[derive(Debug, Clone, uniffi::Record)]
/// Represents a validated tamper-proof cryptographic audit trail record.
/// Used to verify chain integrity across native and core database sync layers.
pub struct DbAuditRecord {
    /// Unique identifier (UUID string) for this specific audit entry.
    pub uuid: String,
    /// Cryptographic SHA-256 hash of the block's content.
    pub audit_hash: String,
    /// The SHA-256 hash of the immediate previous block in the blockchain.
    pub audit_previous_hash: String,
    /// Ordered index representing position in the sequential audit ledger.
    pub audit_chain_index: i32,
    /// Unix timestamp in milliseconds when this audit entry was created.
    pub audit_created_at: i64,
}

#[derive(Debug, Clone, uniffi::Record)]
/// Represents a single log entry persisted in the database.
pub struct LogEntry {
    pub id: i64,
    pub level: String,
    pub message: String,
    pub timestamp: String,
    pub source: String,
}

#[derive(Debug, Clone, uniffi::Record)]
/// Represents a telematics event (crash, hard brake, etc.) persisted in the database.
pub struct DbTelematicsRecord {
    pub id: i64,
    pub event_type: String,
    pub severity: f64,
    pub latitude: f64,
    pub longitude: f64,
    pub timestamp: String,
    pub synced: bool,
}

#[uniffi::export]
impl DatabaseManager {
    /// Initializes a new database connection and creates tables if they don't exist.
    #[uniffi::constructor]
    pub fn new(db_path: &str) -> Result<Self, TraceletError> {
        let conn = Connection::open(db_path).map_err(|e| TraceletError::Database(e.to_string()))?;
        
        conn.execute(
            "CREATE TABLE IF NOT EXISTS location_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                uuid TEXT UNIQUE,
                timestamp TEXT NOT NULL,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                accuracy REAL NOT NULL,
                speed REAL NOT NULL,
                heading REAL NOT NULL,
                altitude REAL NOT NULL,
                is_mock INTEGER NOT NULL,
                is_moving INTEGER NOT NULL DEFAULT 0,
                activity TEXT NOT NULL,
                activity_confidence INTEGER NOT NULL DEFAULT -1,
                encrypted_payload BLOB,
                route_context TEXT,
                timestamp_ms INTEGER DEFAULT 0,
                address TEXT
            )",
            [],
        ).map_err(|e| TraceletError::Database(e.to_string()))?;

        conn.execute(
            "CREATE TABLE IF NOT EXISTS geofence_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                geofence_id TEXT NOT NULL,
                action TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL
            )",
            [],
        ).map_err(|e| TraceletError::Database(e.to_string()))?;

        conn.execute(
            "CREATE TABLE IF NOT EXISTS geofences (
                identifier TEXT PRIMARY KEY,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                radius REAL NOT NULL,
                notify_on_entry INTEGER DEFAULT 1,
                notify_on_exit INTEGER DEFAULT 1,
                notify_on_dwell INTEGER DEFAULT 0,
                loitering_delay INTEGER DEFAULT 0,
                gf_extras TEXT,
                vertices TEXT
            )",
            [],
        ).map_err(|e| TraceletError::Database(e.to_string()))?;

        conn.execute(
            "CREATE TABLE IF NOT EXISTS audit_trail (
                uuid TEXT PRIMARY KEY,
                audit_hash TEXT NOT NULL,
                audit_previous_hash TEXT NOT NULL,
                audit_chain_index INTEGER NOT NULL UNIQUE,
                audit_created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
            )",
            [],
        ).map_err(|e| TraceletError::Database(e.to_string()))?;

        conn.execute(
            "CREATE TABLE IF NOT EXISTS privacy_zones (
                identifier TEXT PRIMARY KEY,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                radius REAL NOT NULL,
                pz_action INTEGER NOT NULL DEFAULT 0,
                pz_degraded_accuracy REAL DEFAULT 1000.0
            )",
            [],
        ).map_err(|e| TraceletError::Database(e.to_string()))?;

        conn.execute(
            "CREATE TABLE IF NOT EXISTS logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                level TEXT NOT NULL,
                message TEXT NOT NULL,
                timestamp TEXT DEFAULT (datetime('now')),
                source TEXT DEFAULT 'plugin'
            )",
            [],
        ).map_err(|e| TraceletError::Database(e.to_string()))?;

        conn.execute(
            "CREATE TABLE IF NOT EXISTS tracelet_telematics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                event_type TEXT NOT NULL,
                severity REAL NOT NULL,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                timestamp TEXT DEFAULT (datetime('now')),
                synced INTEGER DEFAULT 0
            )",
            [],
        ).map_err(|e| TraceletError::Database(e.to_string()))?;

        // Add encrypted_payload column if it doesn't exist (for seamless migration)
        let _ = conn.execute("ALTER TABLE location_events ADD COLUMN uuid TEXT", []);
        let _ = conn.execute("ALTER TABLE location_events ADD COLUMN is_moving INTEGER NOT NULL DEFAULT 0", []);
        let _ = conn.execute("ALTER TABLE location_events ADD COLUMN activity_confidence INTEGER NOT NULL DEFAULT -1", []);
        let _ = conn.execute("ALTER TABLE location_events ADD COLUMN encrypted_payload BLOB", []);
        let _ = conn.execute("ALTER TABLE location_events ADD COLUMN route_context TEXT", []);
        let _ = conn.execute("ALTER TABLE geofences ADD COLUMN encrypted_payload BLOB", []);
        let _ = conn.execute("ALTER TABLE privacy_zones ADD COLUMN encrypted_payload BLOB", []);
        let _ = conn.execute("ALTER TABLE audit_trail ADD COLUMN encrypted_payload BLOB", []);
        
        // Migrate newer columns
        let _ = conn.execute("ALTER TABLE geofences ADD COLUMN gf_extras TEXT", []);
        let _ = conn.execute("ALTER TABLE geofences ADD COLUMN vertices TEXT", []);
        let _ = conn.execute("ALTER TABLE privacy_zones ADD COLUMN pz_action INTEGER NOT NULL DEFAULT 0", []);
        let _ = conn.execute("ALTER TABLE privacy_zones ADD COLUMN pz_degraded_accuracy REAL DEFAULT 1000.0", []);

        // Migrate and backfill timestamp_ms
        let _ = conn.execute("ALTER TABLE location_events ADD COLUMN timestamp_ms INTEGER DEFAULT 0", []);
        let _ = conn.execute("UPDATE location_events SET timestamp_ms = CAST((julianday(timestamp) - 2440587.5) * 86400000 AS INTEGER) WHERE timestamp_ms IS NULL OR timestamp_ms = 0", []);
        let _ = conn.execute("CREATE INDEX IF NOT EXISTS idx_location_events_timestamp_ms ON location_events(timestamp_ms)", []);

        // Issue #128: generic event envelope so non-location events (geofence
        // crossings today; motionchange/heartbeat later) can be persisted in the
        // offline queue and surfaced to sync builders tagged by type.
        let _ = conn.execute("ALTER TABLE location_events ADD COLUMN event_type TEXT DEFAULT 'location'", []);
        let _ = conn.execute("ALTER TABLE location_events ADD COLUMN event_payload TEXT", []);
        // #187: persist reverse-geocoded address (JSON) so it survives into the
        // DB-sourced sync payload, not just the live onLocation event.
        let _ = conn.execute("ALTER TABLE location_events ADD COLUMN address TEXT", []);

        Ok(Self {
            conn: Mutex::new(conn),
            encryption_key: RwLock::new(None),
        })
    }

    /// Sets the encryption key (32 bytes max). If the string is empty or invalid, encryption is disabled.
    pub fn set_encryption_key(&self, key: &str) {
        let mut w = self.encryption_key.write().unwrap();
        if key.is_empty() {
            *w = None;
            return;
        }
        
        use sha2::{Sha256, Digest};
        let mut hasher = Sha256::new();
        hasher.update(key.as_bytes());
        let result = hasher.finalize();
        
        let mut key_bytes = [0u8; 32];
        key_bytes.copy_from_slice(&result);
        *w = Some(key_bytes);
    }

    // Helper to encrypt
    fn encrypt_payload(&self, plaintext: &[u8]) -> Option<Vec<u8>> {
        let key = *self.encryption_key.read().unwrap();
        if let Some(k) = key {
            let cipher = Aes256Gcm::new(GenericArray::from_slice(&k));
            let mut nonce_bytes = [0u8; 12];
            OsRng.fill_bytes(&mut nonce_bytes);
            let nonce = Nonce::from_slice(&nonce_bytes);
            
            if let Ok(mut ciphertext) = cipher.encrypt(nonce, plaintext) {
                let mut result = Vec::with_capacity(1 + 12 + ciphertext.len());
                result.push(0x01);
                result.extend_from_slice(&nonce_bytes);
                result.append(&mut ciphertext);
                return Some(result);
            }
        }
        None
    }

    fn decrypt_payload(&self, payload: &[u8]) -> Option<Vec<u8>> {
        if payload.is_empty() { return None; }
        let magic = payload[0];
        
        if magic == 0x01 {
            if payload.len() < 13 { return None; }
            let key = *self.encryption_key.read().unwrap();
            if let Some(k) = key {
                let cipher = Aes256Gcm::new(GenericArray::from_slice(&k));
                let nonce = Nonce::from_slice(&payload[1..13]);
                if let Ok(plaintext) = cipher.decrypt(nonce, &payload[13..]) {
                    return Some(plaintext);
                }
            }
        }
        None
    }

    /// Inserts a new location record into the database.
    pub fn insert_location(&self, uuid: Option<String>, lat: f64, lng: f64, acc: f64, speed: f64, heading: f64, altitude: f64, is_mock: bool, is_moving: bool, activity: &str, activity_confidence: i32, route_context: Option<String>, timestamp_override: Option<String>, event_type: Option<String>, event_payload: Option<String>, address: Option<String>) -> Result<i64, TraceletError> {
        let conn = self.conn.lock().unwrap();

        let (timestamp, timestamp_ms) = if let Some(override_ts) = timestamp_override {
            let parsed_ms = match chrono::DateTime::parse_from_rfc3339(&override_ts) {
                Ok(dt) => dt.timestamp_millis(),
                Err(_) => Utc::now().timestamp_millis(), // Fallback if invalid string
            };
            (override_ts, parsed_ms)
        } else {
            let now = Utc::now();
            (now.to_rfc3339(), now.timestamp_millis())
        };

        // Issue #128: event_type/event_payload are stored as plaintext columns
        // even under encryption — event_type must remain queryable, and the
        // geofence payload (identifier/action) is not coordinate-level PII.
        let event_type = event_type.unwrap_or_else(|| "location".to_string());

        let is_encrypted = self.encryption_key.read().unwrap().is_some();
        if is_encrypted {
            let record = serde_json::json!({
                "lat": lat,
                "lng": lng,
                "acc": acc,
                "speed": speed,
                "heading": heading,
                "altitude": altitude,
                "is_mock": is_mock,
                "is_moving": is_moving,
                "activity": activity,
                "activity_confidence": activity_confidence,
                "route_context": route_context,
                "address": address
            });
            if let Some(payload) = self.encrypt_payload(record.to_string().as_bytes()) {
                // address is coordinate-level PII — under encryption it lives only
                // inside the encrypted payload, so the plaintext column stays NULL.
                // activity_confidence follows activity: zeroed-out plaintext column
                // (-1 = unset), real value inside the encrypted payload (#245).
                conn.execute(
                    "INSERT INTO location_events (uuid, timestamp, latitude, longitude, accuracy, speed, heading, altitude, is_mock, is_moving, activity, activity_confidence, encrypted_payload, route_context, timestamp_ms, event_type, event_payload, address)
                     VALUES (?1, ?2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, 0, '', -1, ?3, ?4, ?5, ?6, ?7, NULL)",
                    params![uuid, timestamp, payload, route_context, timestamp_ms, event_type, event_payload],
                ).map_err(|e| TraceletError::Database(e.to_string()))?;
                return Ok(conn.last_insert_rowid());
            }
        }

        // Fallback or unencrypted
        conn.execute(
            "INSERT INTO location_events (uuid, timestamp, latitude, longitude, accuracy, speed, heading, altitude, is_mock, is_moving, activity, activity_confidence, encrypted_payload, route_context, timestamp_ms, event_type, event_payload, address)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, NULL, ?13, ?14, ?15, ?16, ?17)",
            params![uuid, timestamp, lat, lng, acc, speed, heading, altitude, if is_mock { 1 } else { 0 }, if is_moving { 1 } else { 0 }, activity, activity_confidence, route_context, timestamp_ms, event_type, event_payload, address],
        ).map_err(|e| TraceletError::Database(e.to_string()))?;

        Ok(conn.last_insert_rowid())
    }

    /// Retrieves a batch of location records, with optional filtering.
    pub fn get_locations_batch(&self, query: Option<LocationQuery>) -> Result<Vec<DbLocationRecord>, TraceletError> {
        use rusqlite::types::Value;
        let conn = self.conn.lock().unwrap();
        
        let mut sql = "SELECT id, uuid, timestamp, latitude, longitude, accuracy, speed, heading, altitude, is_mock, is_moving, activity, encrypted_payload, route_context, event_type, event_payload, address, activity_confidence FROM location_events WHERE 1=1".to_string();
        let mut params: Vec<Value> = Vec::new();
        
        // No limit specified → return ALL matching rows (-1 = no LIMIT, handled
        // below). Previously this defaulted to 1000, silently capping manual
        // reads like getLocations() / getCarbonReport() (Issue #139). Callers
        // that want a cap (e.g. sync batching) always pass an explicit limit.
        let limit = query.as_ref().and_then(|q| q.limit).unwrap_or(-1);
        let offset = query.as_ref().and_then(|q| q.offset).unwrap_or(0);
        let is_desc = query.as_ref().and_then(|q| q.order_descending).unwrap_or(false);
        
        if let Some(q) = &query {
            if let Some(start_ms) = q.start_time_ms {
                sql.push_str(" AND timestamp_ms >= ?");
                params.push(Value::Integer(start_ms));
            }
            if let Some(end_ms) = q.end_time_ms {
                sql.push_str(" AND timestamp_ms <= ?");
                params.push(Value::Integer(end_ms));
            }
        }
        
        if is_desc {
            sql.push_str(" ORDER BY id DESC");
        } else {
            sql.push_str(" ORDER BY id ASC");
        }
        
        if limit >= 0 {
            sql.push_str(" LIMIT ?");
            params.push(Value::Integer(limit as i64));
        } else if offset > 0 {
            // SQLite requires LIMIT to use OFFSET. -1 means no limit.
            sql.push_str(" LIMIT -1");
        }
        
        if offset > 0 {
            sql.push_str(" OFFSET ?");
            params.push(Value::Integer(offset as i64));
        }
        
        let mut stmt = conn.prepare(&sql).map_err(|e| TraceletError::Database(e.to_string()))?;
        
        let iter = stmt.query_map(rusqlite::params_from_iter(params), |row| {
            let mut lat: f64 = row.get(3)?;
            let mut lng: f64 = row.get(4)?;
            let mut acc: f64 = row.get(5)?;
            let mut speed: f64 = row.get(6)?;
            let mut heading: f64 = row.get(7)?;
            let mut altitude: f64 = row.get(8)?;
            let mut is_mock_val: i32 = row.get(9)?;
            let mut is_moving_val: i32 = row.get(10)?;
            let mut activity_val: String = row.get(11)?;
            let mut activity_confidence_val: i32 = row.get(17).unwrap_or(-1);
            
            let encrypted_payload: Option<Vec<u8>> = row.get(12).unwrap_or(None);
            let mut route_context: Option<String> = row.get(13).unwrap_or(None);
            let event_type: String = row.get::<_, Option<String>>(14).unwrap_or(None).unwrap_or_else(|| "location".to_string());
            let event_payload: Option<String> = row.get(15).unwrap_or(None);
            let mut address: Option<String> = row.get(16).unwrap_or(None);

            if let Some(payload_bytes) = encrypted_payload {
                if let Some(plaintext) = self.decrypt_payload(&payload_bytes) {
                    if let Ok(json) = serde_json::from_slice::<serde_json::Value>(&plaintext) {
                        lat = json["lat"].as_f64().unwrap_or(0.0);
                        lng = json["lng"].as_f64().unwrap_or(0.0);
                        acc = json["acc"].as_f64().unwrap_or(0.0);
                        speed = json["speed"].as_f64().unwrap_or(0.0);
                        heading = json["heading"].as_f64().unwrap_or(0.0);
                        altitude = json["altitude"].as_f64().unwrap_or(0.0);
                        if let Some(is_mock) = json.get("is_mock").and_then(|v| v.as_bool()) { is_mock_val = if is_mock { 1 } else { 0 }; }
                        if let Some(is_moving) = json.get("is_moving").and_then(|v| v.as_bool()) { is_moving_val = if is_moving { 1 } else { 0 }; }
                        if let Some(activity) = json.get("activity").and_then(|v| v.as_str()) { activity_val = activity.to_string(); }
                        if let Some(conf) = json.get("activity_confidence").and_then(|v| v.as_i64()) { activity_confidence_val = conf as i32; }
                        if let Some(rc) = json.get("route_context").and_then(|v| v.as_str()) { route_context = Some(rc.to_string()); }
                        // address lives in the encrypted payload (PII); plaintext column is NULL.
                        if let Some(a) = json.get("address").and_then(|v| v.as_str()) { address = Some(a.to_string()); }
                    }
                }
            }

            Ok(DbLocationRecord {
                id: row.get(0)?,
                uuid: row.get(1).unwrap_or(None),
                timestamp: row.get(2)?,
                latitude: lat,
                longitude: lng,
                accuracy: acc,
                speed,
                heading,
                altitude,
                is_mock: is_mock_val != 0,
                is_moving: is_moving_val != 0,
                activity: activity_val,
                activity_confidence: activity_confidence_val,
                route_context,
                event_type,
                event_payload,
                address,
            })
        }).map_err(|e| TraceletError::Database(e.to_string()))?;

        let mut records = Vec::new();
        for r in iter {
            if let Ok(record) = r {
                records.push(record);
            }
        }
        Ok(records)
    }

    /// Deletes records up to the given max ID (used after successful sync).
    pub fn clear_locations_up_to(&self, max_id: i64) -> Result<(), TraceletError> {
        let conn = self.conn.lock().unwrap();
        conn.execute("DELETE FROM audit_trail WHERE uuid IN (SELECT uuid FROM location_events WHERE id <= ?1 AND uuid IS NOT NULL)", params![max_id]).map_err(|e| TraceletError::Database(e.to_string()))?;
        conn.execute("DELETE FROM location_events WHERE id <= ?1", params![max_id]).map_err(|e| TraceletError::Database(e.to_string()))?;
        Ok(())
    }

    /// Gets the total count of locations persisted in the database.
    pub fn is_empty(&self) -> Result<bool, TraceletError> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare("SELECT COUNT(*) FROM location_events").map_err(|e| TraceletError::Database(e.to_string()))?;
        let count: i64 = stmt.query_row([], |row| row.get(0)).unwrap_or(0);
        Ok(count == 0)
    }

    /// Gets the total count of locations persisted in the database.
    pub fn get_location_for_audit(&self, uuid: &str) -> Result<Option<DbLocationRecord>, TraceletError> {
        let conn = self.conn.lock().unwrap();
        let sql = "SELECT id, uuid, timestamp, latitude, longitude, accuracy, speed, heading, altitude, is_mock, is_moving, activity, encrypted_payload, route_context, event_type, event_payload, address, activity_confidence FROM location_events WHERE uuid = ?1 LIMIT 1";
        
        let mut stmt = conn.prepare(sql).map_err(|e| TraceletError::Database(e.to_string()))?;
        
        let mut iter = stmt.query_map([uuid], |row| {
            let mut lat: f64 = row.get(3)?;
            let mut lng: f64 = row.get(4)?;
            let mut acc: f64 = row.get(5)?;
            let mut speed: f64 = row.get(6)?;
            let mut heading: f64 = row.get(7)?;
            let mut altitude: f64 = row.get(8)?;
            let mut is_mock_val: i32 = row.get(9)?;
            let mut is_moving_val: i32 = row.get(10)?;
            let mut activity_val: String = row.get(11)?;
            let mut activity_confidence_val: i32 = row.get(17).unwrap_or(-1);
            
            let encrypted_payload: Option<Vec<u8>> = row.get(12).unwrap_or(None);
            let mut route_context: Option<String> = row.get(13).unwrap_or(None);
            let event_type: String = row.get::<_, Option<String>>(14).unwrap_or(None).unwrap_or_else(|| "location".to_string());
            let event_payload: Option<String> = row.get(15).unwrap_or(None);
            let mut address: Option<String> = row.get(16).unwrap_or(None);

            if let Some(payload_bytes) = encrypted_payload {
                if let Some(plaintext) = self.decrypt_payload(&payload_bytes) {
                    if let Ok(json) = serde_json::from_slice::<serde_json::Value>(&plaintext) {
                        lat = json["lat"].as_f64().unwrap_or(0.0);
                        lng = json["lng"].as_f64().unwrap_or(0.0);
                        acc = json["acc"].as_f64().unwrap_or(0.0);
                        speed = json["speed"].as_f64().unwrap_or(0.0);
                        heading = json["heading"].as_f64().unwrap_or(0.0);
                        altitude = json["altitude"].as_f64().unwrap_or(0.0);
                        if let Some(is_mock) = json.get("is_mock").and_then(|v| v.as_bool()) { is_mock_val = if is_mock { 1 } else { 0 }; }
                        if let Some(is_moving) = json.get("is_moving").and_then(|v| v.as_bool()) { is_moving_val = if is_moving { 1 } else { 0 }; }
                        if let Some(activity) = json.get("activity").and_then(|v| v.as_str()) { activity_val = activity.to_string(); }
                        if let Some(conf) = json.get("activity_confidence").and_then(|v| v.as_i64()) { activity_confidence_val = conf as i32; }
                        if let Some(rc) = json.get("route_context").and_then(|v| v.as_str()) { route_context = Some(rc.to_string()); }
                        if let Some(a) = json.get("address").and_then(|v| v.as_str()) { address = Some(a.to_string()); }
                    }
                }
            }

            Ok(DbLocationRecord {
                id: row.get(0)?,
                uuid: row.get(1).unwrap_or(None),
                timestamp: row.get(2)?,
                latitude: lat,
                longitude: lng,
                accuracy: acc,
                speed,
                heading,
                altitude,
                is_mock: is_mock_val != 0,
                is_moving: is_moving_val != 0,
                activity: activity_val,
                activity_confidence: activity_confidence_val,
                route_context,
                event_type,
                event_payload,
                address,
            })
        }).map_err(|e| TraceletError::Database(e.to_string()))?;

        if let Some(result) = iter.next() {
            return match result {
                Ok(r) => Ok(Some(r)),
                Err(e) => Err(TraceletError::Database(e.to_string())),
            };
        }
        
        Ok(None)
    }

    pub fn get_locations_count(&self) -> Result<i32, TraceletError> {
        let conn = self.conn.lock().unwrap();
        let count: i32 = conn.query_row("SELECT COUNT(*) FROM location_events", [], |row| row.get(0))
            .map_err(|e| TraceletError::Database(e.to_string()))?;
        Ok(count)
    }

    /// Deletes all location records in the database.
    pub fn destroy_locations(&self) -> Result<(), TraceletError> {
        let conn = self.conn.lock().unwrap();
        conn.execute("DELETE FROM location_events", [])
            .map_err(|e| TraceletError::Database(e.to_string()))?;
        Ok(())
    }

    /// Deletes a specific location by ID.
    pub fn destroy_location(&self, id: i64) -> Result<(), TraceletError> {
        let conn = self.conn.lock().unwrap();
        conn.execute("DELETE FROM location_events WHERE id = ?1", params![id])
            .map_err(|e| TraceletError::Database(e.to_string()))?;
        Ok(())
    }

    // --- Geofences ---
    
    pub fn insert_geofence(
        &self, 
        identifier: &str, 
        lat: f64, 
        lng: f64, 
        radius: f64,
        vertices: Option<Vec<Coordinate>>,
        extras: Option<String>
    ) -> Result<(), TraceletError> {
        let conn = self.conn.lock().unwrap();
        let vertices_json = match vertices {
            Some(v) if !v.is_empty() => {
                let json_vec: Vec<Vec<f64>> = v.iter().map(|c| vec![c.lat, c.lng]).collect();
                Some(serde_json::to_string(&json_vec).unwrap_or_default())
            },
            _ => None,
        };
        conn.execute(
            "INSERT OR REPLACE INTO geofences (identifier, latitude, longitude, radius, vertices, gf_extras) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![identifier, lat, lng, radius, vertices_json, extras]
        ).map_err(|e| TraceletError::Database(e.to_string()))?;
        Ok(())
    }
    
    pub fn delete_geofence(&self, identifier: &str) -> Result<(), TraceletError> {
        let conn = self.conn.lock().unwrap();
        conn.execute("DELETE FROM geofences WHERE identifier = ?1", params![identifier])
            .map_err(|e| TraceletError::Database(e.to_string()))?;
        Ok(())
    }
    
    pub fn clear_geofences(&self) -> Result<(), TraceletError> {
        let conn = self.conn.lock().unwrap();
        conn.execute("DELETE FROM geofences", [])
            .map_err(|e| TraceletError::Database(e.to_string()))?;
        Ok(())
    }

    // --- Privacy Zones ---
    
    /// Inserts or replaces a privacy zone record in the database.
    ///
    /// # Arguments
    /// * `identifier` - A unique string identifying this privacy zone.
    /// * `lat` - Center latitude in decimal degrees.
    /// * `lng` - Center longitude in decimal degrees.
    /// * `radius` - Radius of the privacy zone in meters.
    /// * `action` - Integer indicating the privacy action to apply:
    ///   - 0: EXCLUDE (drop locations completely)
    ///   - 1: DEGRADE (snap coordinates to a coarse accuracy grid)
    ///   - 2: EVENT_ONLY (dispatch real-time updates to listeners but do not persist)
    /// * `degraded_accuracy` - Precision grid size in meters for DEGRADE actions (defaults to 1000.0).
    pub fn insert_privacy_zone(&self, identifier: &str, lat: f64, lng: f64, radius: f64, action: i32, degraded_accuracy: f64) -> Result<(), TraceletError> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT OR REPLACE INTO privacy_zones (identifier, latitude, longitude, radius, pz_action, pz_degraded_accuracy) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![identifier, lat, lng, radius, action, degraded_accuracy]
        ).map_err(|e| TraceletError::Database(e.to_string()))?;
        Ok(())
    }
    
    /// Deletes a specific privacy zone from the database by its unique identifier.
    pub fn delete_privacy_zone(&self, identifier: &str) -> Result<(), TraceletError> {
        let conn = self.conn.lock().unwrap();
        conn.execute("DELETE FROM privacy_zones WHERE identifier = ?1", params![identifier])
            .map_err(|e| TraceletError::Database(e.to_string()))?;
        Ok(())
    }
    
    /// Removes all stored privacy zones from the database.
    pub fn clear_privacy_zones(&self) -> Result<(), TraceletError> {
        let conn = self.conn.lock().unwrap();
        conn.execute("DELETE FROM privacy_zones", [])
            .map_err(|e| TraceletError::Database(e.to_string()))?;
        Ok(())
    }

    /// Retrieves all privacy zones registered in the local database.
    /// Used by native managers to query geofenced privacy control zones.
    pub fn get_privacy_zones(&self) -> Result<Vec<CorePrivacyZone>, TraceletError> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare("SELECT identifier, latitude, longitude, radius, pz_action, pz_degraded_accuracy FROM privacy_zones")
            .map_err(|e| TraceletError::Database(e.to_string()))?;
        
        let iter = stmt.query_map([], |row| {
            Ok(CorePrivacyZone {
                identifier: row.get(0)?,
                latitude: row.get(1)?,
                longitude: row.get(2)?,
                radius: row.get(3)?,
                action: row.get(4)?,
                degraded_accuracy_meters: row.get(5)?,
            })
        }).map_err(|e| TraceletError::Database(e.to_string()))?;

        let mut zones = Vec::new();
        for z in iter {
            if let Ok(zone) = z {
                zones.push(zone);
            }
        }
        Ok(zones)
    }

    // --- Geofences ---

    /// Retrieves all registered geofences from the database, parsing JSON-serialized vertices.
    /// Resolves polygon geofences containing multiple coordinate vertices as well as circular ones.
    pub fn get_geofences(&self) -> Result<Vec<CoreGeofence>, TraceletError> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare("SELECT identifier, latitude, longitude, radius, vertices, gf_extras FROM geofences")
            .map_err(|e| TraceletError::Database(e.to_string()))?;

        let iter = stmt.query_map([], |row| {
            let identifier: String = row.get(0)?;
            let latitude: f64 = row.get(1)?;
            let longitude: f64 = row.get(2)?;
            let radius: f64 = row.get(3)?;
            let vertices_str: Option<String> = row.get(4)?;
            let extras: Option<String> = row.get(5)?;

            let mut vertices = Vec::new();
            if let Some(s) = vertices_str {
                if !s.is_empty() {
                    // Vertices are stored in SQLite as JSON-serialized coordinate arrays: [[lat, lng], [lat, lng], ...]
                    if let Ok(raw_vertices) = serde_json::from_str::<Vec<Vec<f64>>>(&s) {
                        for item in raw_vertices {
                            if item.len() >= 2 {
                                vertices.push(Coordinate {
                                    lat: item[0],
                                    lng: item[1],
                                });
                            }
                        }
                    }
                }
            }

            Ok(CoreGeofence {
                identifier,
                latitude,
                longitude,
                radius,
                vertices,
                extras,
            })
        }).map_err(|e| TraceletError::Database(e.to_string()))?;

        let mut geofences = Vec::new();
        for gf in iter {
            if let Ok(gf_val) = gf {
                geofences.push(gf_val);
            }
        }
        Ok(geofences)
    }

    // --- Audit Trail ---
    
    /// Inserts or replaces a validated tamper-proof cryptographic audit trail record.
    pub fn insert_audit_trail(&self, uuid: &str, hash: &str, prev_hash: &str, index: i32) -> Result<(), TraceletError> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT OR REPLACE INTO audit_trail (uuid, audit_hash, audit_previous_hash, audit_chain_index) VALUES (?1, ?2, ?3, ?4)",
            params![uuid, hash, prev_hash, index]
        ).map_err(|e| TraceletError::Database(e.to_string()))?;
        Ok(())
    }

    /// Deletes all audit trail records from the database.
    /// Used when the hashing logic changes and old chain data must be discarded.
    pub fn clear_audit_trail(&self) -> Result<(), TraceletError> {
        let conn = self.conn.lock().unwrap();
        conn.execute("DELETE FROM audit_trail", [])
            .map_err(|e| TraceletError::Database(e.to_string()))?;
        Ok(())
    }

    /// Retrieves all audit trail records, ordered sequentially by their chain index.
    pub fn get_audit_trail(&self) -> Result<Vec<DbAuditRecord>, TraceletError> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare("SELECT uuid, audit_hash, audit_previous_hash, audit_chain_index, audit_created_at FROM audit_trail ORDER BY audit_chain_index ASC")
            .map_err(|e| TraceletError::Database(e.to_string()))?;

        let iter = stmt.query_map([], |row| {
            Ok(DbAuditRecord {
                uuid: row.get(0)?,
                audit_hash: row.get(1)?,
                audit_previous_hash: row.get(2)?,
                audit_chain_index: row.get(3)?,
                audit_created_at: row.get(4)?,
            })
        }).map_err(|e| TraceletError::Database(e.to_string()))?;

        let mut records = Vec::new();
        for r in iter {
            if let Ok(record) = r {
                records.push(record);
            }
        }
        Ok(records)
    }

    // --- Logs ---

    /// Inserts a log entry into the database.
    pub fn insert_log(&self, level: &str, message: &str, source: &str) -> Result<(), TraceletError> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT INTO logs (level, message, source) VALUES (?1, ?2, ?3)",
            params![level, message, source]
        ).map_err(|e| TraceletError::Database(e.to_string()))?;
        Ok(())
    }

    /// Retrieves a batch of log entries, up to `limit`.
    pub fn get_logs(&self, limit: i32) -> Result<Vec<LogEntry>, TraceletError> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare("SELECT id, level, message, timestamp, source FROM logs ORDER BY id DESC LIMIT ?1")
            .map_err(|e| TraceletError::Database(e.to_string()))?;

        let iter = stmt.query_map([limit], |row| {
            Ok(LogEntry {
                id: row.get(0)?,
                level: row.get(1)?,
                message: row.get(2)?,
                timestamp: row.get(3)?,
                source: row.get(4)?,
            })
        }).map_err(|e| TraceletError::Database(e.to_string()))?;

        let mut records = Vec::new();
        for r in iter {
            if let Ok(record) = r {
                records.push(record);
            }
        }
        Ok(records)
    }

    /// Prunes the logs to retain only the specified limit of latest entries.
    pub fn prune_logs(&self, limit: i32) -> Result<(), TraceletError> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "DELETE FROM logs WHERE id NOT IN (SELECT id FROM logs ORDER BY id DESC LIMIT ?1)",
            params![limit]
        ).map_err(|e| TraceletError::Database(e.to_string()))?;
        Ok(())
    }

    /// Deletes log rows older than `max_days` (#304).
    ///
    /// `logMaxDays` was a documented retention window that nothing implemented:
    /// both platforms pruned only by a row count derived from `logLevel`, so the
    /// configured number of days was accepted and discarded. Row-count pruning
    /// alone cannot express "keep two weeks", because how many rows that is
    /// depends entirely on how chatty the session was.
    ///
    /// `max_days <= 0` is a no-op rather than an error, so callers can pass the
    /// config value straight through to mean "no age-based retention" and keep
    /// relying on the count cap alone.
    ///
    /// `timestamp` is stored as `datetime('now')` (UTC, `YYYY-MM-DD HH:MM:SS`),
    /// so it compares correctly as text against SQLite's own modifier output.
    pub fn prune_logs_older_than(&self, max_days: i32) -> Result<(), TraceletError> {
        if max_days <= 0 {
            return Ok(());
        }
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "DELETE FROM logs WHERE timestamp < datetime('now', ?1)",
            params![format!("-{} days", max_days)],
        )
        .map_err(|e| TraceletError::Database(e.to_string()))?;
        Ok(())
    }

    /// Clears all log entries from the database.
    pub fn clear_logs(&self) -> Result<(), TraceletError> {
        let conn = self.conn.lock().unwrap();
        conn.execute("DELETE FROM logs", [])
            .map_err(|e| TraceletError::Database(e.to_string()))?;
        Ok(())
    }

    // --- Telematics ---

    /// Inserts a telematics event into the database.
    pub fn insert_telematics_event(&self, event_type: &str, severity: f64, lat: f64, lng: f64) -> Result<i64, TraceletError> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT INTO tracelet_telematics (event_type, severity, latitude, longitude) VALUES (?1, ?2, ?3, ?4)",
            params![event_type, severity, lat, lng]
        ).map_err(|e| TraceletError::Database(e.to_string()))?;
        Ok(conn.last_insert_rowid())
    }

    /// Retrieves a batch of unsynced telematics events.
    pub fn get_telematics_events(&self, limit: i32) -> Result<Vec<DbTelematicsRecord>, TraceletError> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare("SELECT id, event_type, severity, latitude, longitude, timestamp, synced FROM tracelet_telematics WHERE synced = 0 ORDER BY id ASC LIMIT ?1")
            .map_err(|e| TraceletError::Database(e.to_string()))?;

        let iter = stmt.query_map([limit], |row| {
            let synced_int: i32 = row.get(6)?;
            Ok(DbTelematicsRecord {
                id: row.get(0)?,
                event_type: row.get(1)?,
                severity: row.get(2)?,
                latitude: row.get(3)?,
                longitude: row.get(4)?,
                timestamp: row.get(5)?,
                synced: synced_int != 0,
            })
        }).map_err(|e| TraceletError::Database(e.to_string()))?;

        let mut records = Vec::new();
        for r in iter {
            if let Ok(record) = r {
                records.push(record);
            }
        }
        Ok(records)
    }

    /// Marks telematics events up to max_id as synced.
    pub fn mark_telematics_synced(&self, max_id: i64) -> Result<(), TraceletError> {
        let conn = self.conn.lock().unwrap();
        conn.execute("UPDATE tracelet_telematics SET synced = 1 WHERE id <= ?1", params![max_id])
            .map_err(|e| TraceletError::Database(e.to_string()))?;
        Ok(())
    }

    /// Clears all telematics events from the database.
    pub fn clear_telematics_events(&self) -> Result<(), TraceletError> {
        let conn = self.conn.lock().unwrap();
        conn.execute("DELETE FROM tracelet_telematics", [])
            .map_err(|e| TraceletError::Database(e.to_string()))?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_unencrypted_insert_and_read() {
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");
        // Ensure no key is set
        db.set_encryption_key("");
        
        db.insert_location(None, 37.7749, -122.4194, 10.0, 1.5, 90.0, 15.0, false, false, "walking", -1, None, None, None, None, None).unwrap();
        
        let locations = db.get_locations_batch(None).unwrap();
        assert_eq!(locations.len(), 1);
        let loc = &locations[0];
        assert_eq!(loc.latitude, 37.7749);
        assert_eq!(loc.longitude, -122.4194);
        assert_eq!(loc.activity, "walking");
    }

    #[test]
    fn test_encrypted_insert_and_read() {
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");
        
        // Set an encryption key
        let test_key = "my_super_secret_encryption_key_!";
        db.set_encryption_key(test_key);
        
        db.insert_location(None, 40.7128, -74.0060, 5.0, 0.0, 0.0, 10.0, true, true, "running", -1, None, None, None, None, None).unwrap();
        
        let locations = db.get_locations_batch(None).unwrap();
        assert_eq!(locations.len(), 1);
        let loc = &locations[0];
        assert_eq!(loc.latitude, 40.7128);
        assert_eq!(loc.longitude, -74.0060);
        assert_eq!(loc.activity, "running");
        assert_eq!(loc.is_mock, true);
    }

    #[test]
    fn test_activity_confidence_round_trips() {
        // #245: activity.confidence must survive persistence — it was never
        // stored, so DB-sourced reads hardcoded 100 on both platforms.
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");
        db.set_encryption_key("");
        db.insert_location(Some("conf-1".into()), 1.0, 2.0, 5.0, 0.0, 0.0, 0.0, false, true, "in_vehicle", 87, None, None, None, None, None).unwrap();

        let rows = db.get_locations_batch(None).unwrap();
        let r = rows.iter().find(|r| r.uuid.as_deref() == Some("conf-1")).expect("row");
        assert_eq!(r.activity, "in_vehicle");
        assert_eq!(r.activity_confidence, 87, "confidence must round-trip");

        // Unset confidence reads back as -1 (also the migration default for
        // rows persisted before the column existed).
        db.insert_location(Some("conf-2".into()), 1.0, 2.0, 5.0, 0.0, 0.0, 0.0, false, true, "walking", -1, None, None, None, None, None).unwrap();
        let rows = db.get_locations_batch(None).unwrap();
        let r2 = rows.iter().find(|r| r.uuid.as_deref() == Some("conf-2")).unwrap();
        assert_eq!(r2.activity_confidence, -1);
    }

    #[test]
    fn test_activity_confidence_round_trips_under_encryption() {
        // #245: under encryption the confidence lives in the encrypted payload
        // (the plaintext column is zeroed to -1 like activity is to '').
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");
        db.set_encryption_key("confidence_encryption_key_32b!!!");
        db.insert_location(Some("conf-enc".into()), 1.0, 2.0, 5.0, 0.0, 0.0, 0.0, false, true, "on_bicycle", 62, None, None, None, None, None).unwrap();

        let rows = db.get_locations_batch(None).unwrap();
        let r = rows.iter().find(|r| r.uuid.as_deref() == Some("conf-enc")).expect("row");
        assert_eq!(r.activity, "on_bicycle");
        assert_eq!(r.activity_confidence, 62, "confidence must survive encryption");

        // Audit read path decrypts it too.
        let audit = db.get_location_for_audit("conf-enc").unwrap().expect("record");
        assert_eq!(audit.activity_confidence, 62);
    }

    #[test]
    fn test_graceful_reading_mixed_records() {
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");
        
        // Insert unencrypted
        db.set_encryption_key("");
        db.insert_location(None, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, false, false, "unencrypted", -1, None, None, None, None, None).unwrap();
        
        // Turn encryption ON
        let test_key = "another_secret_key_1234567890!!!";
        db.set_encryption_key(test_key);
        db.insert_location(None, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, false, false, "encrypted", -1, None, None, None, None, None).unwrap();
        
        let locations = db.get_locations_batch(Some(LocationQuery {
            start_time_ms: None,
            end_time_ms: None,
            limit: Some(10),
            offset: None,
            order_descending: None,
        })).unwrap();
        assert_eq!(locations.len(), 2);
        
        // Both should be readable!
        assert_eq!(locations[0].latitude, 1.0);
        assert_eq!(locations[0].activity, "unencrypted");
        
        assert_eq!(locations[1].latitude, 2.0);
        assert_eq!(locations[1].activity, "encrypted");
    }

    #[test]
    fn test_timestamp_ms_query() {
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");
        
        let t1 = Utc::now().timestamp_millis() - 10000;
        let t2 = Utc::now().timestamp_millis();
        let t3 = Utc::now().timestamp_millis() + 10000;

        // Directly insert via raw SQL to override timestamp_ms for rigorous testing
        let conn = db.conn.lock().unwrap();
        conn.execute("INSERT INTO location_events (timestamp, latitude, longitude, accuracy, speed, heading, altitude, is_mock, activity, timestamp_ms) VALUES ('', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, 't1', ?1)", params![t1]).unwrap();
        conn.execute("INSERT INTO location_events (timestamp, latitude, longitude, accuracy, speed, heading, altitude, is_mock, activity, timestamp_ms) VALUES ('', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, 't2', ?1)", params![t2]).unwrap();
        conn.execute("INSERT INTO location_events (timestamp, latitude, longitude, accuracy, speed, heading, altitude, is_mock, activity, timestamp_ms) VALUES ('', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, 't3', ?1)", params![t3]).unwrap();
        drop(conn);

        let locations = db.get_locations_batch(Some(LocationQuery {
            start_time_ms: Some(t2 - 100),
            end_time_ms: Some(t2 + 100),
            limit: None,
            offset: None,
            order_descending: None,
        })).unwrap();

        assert_eq!(locations.len(), 1);
        assert_eq!(locations[0].activity, "t2");
    }

    #[test]
    fn test_geofence_crud() {
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");
        
        // Insert a circular geofence
        db.insert_geofence("home_zone", 37.0, -122.0, 150.0, None, None).unwrap();
        
        let count: i32 = db.conn.lock().unwrap().query_row("SELECT COUNT(*) FROM geofences", [], |r| r.get(0)).unwrap();
        assert_eq!(count, 1);

        // Test inserting a polygon geofence with extras
        let vertices = vec![
            Coordinate { lat: 37.0, lng: -122.0 },
            Coordinate { lat: 37.1, lng: -122.1 },
            Coordinate { lat: 37.2, lng: -122.2 }
        ];
        let extras = Some("{\"type\":\"polygon\",\"color\":\"blue\"}".to_string());
        db.insert_geofence("home_zone", 37.0, -122.0, 150.0, Some(vertices), extras).unwrap();

        // Verify retrieval of geofences and parsing of vertices and extras
        let geofences = db.get_geofences().unwrap();
        assert_eq!(geofences.len(), 1);
        assert_eq!(geofences[0].identifier, "home_zone");
        assert_eq!(geofences[0].vertices.len(), 3);
        assert_eq!(geofences[0].vertices[0].lat, 37.0);
        assert_eq!(geofences[0].vertices[2].lng, -122.2);
        assert_eq!(geofences[0].extras.as_ref().unwrap(), "{\"type\":\"polygon\",\"color\":\"blue\"}");
        
        // Delete the geofence
        db.delete_geofence("home_zone").unwrap();
        let count_after_delete: i32 = db.conn.lock().unwrap().query_row("SELECT COUNT(*) FROM geofences", [], |r| r.get(0)).unwrap();
        assert_eq!(count_after_delete, 0);
        
        // Batch inserting and clearing multiple
        db.insert_geofence("work", 38.0, -121.0, 50.0, None, None).unwrap();
        db.insert_geofence("gym", 39.0, -120.0, 100.0, None, None).unwrap();
        db.clear_geofences().unwrap();
        let count_after_clear: i32 = db.conn.lock().unwrap().query_row("SELECT COUNT(*) FROM geofences", [], |r| r.get(0)).unwrap();
        assert_eq!(count_after_clear, 0);
    }

    #[test]
    fn test_privacy_zone_crud() {
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");
        
        // Insert a privacy zone with custom action (DEGRADE = 1) and precision grid accuracy (500m)
        db.insert_privacy_zone("private_home", 45.0, -90.0, 500.0, 1, 500.0).unwrap();
        
        let count: i32 = db.conn.lock().unwrap().query_row("SELECT COUNT(*) FROM privacy_zones", [], |r| r.get(0)).unwrap();
        assert_eq!(count, 1);

        // Verify retrieving privacy zones matches the inserted properties
        let zones = db.get_privacy_zones().unwrap();
        assert_eq!(zones.len(), 1);
        assert_eq!(zones[0].identifier, "private_home");
        assert_eq!(zones[0].action, 1);
        assert_eq!(zones[0].degraded_accuracy_meters, 500.0);
        
        db.delete_privacy_zone("private_home").unwrap();
        let count_after: i32 = db.conn.lock().unwrap().query_row("SELECT COUNT(*) FROM privacy_zones", [], |r| r.get(0)).unwrap();
        assert_eq!(count_after, 0);
    }

    #[test]
    fn test_audit_trail_crud() {
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");
        
        db.insert_audit_trail("uuid-1234", "hash1", "hash0", 1).unwrap();
        
        let count: i32 = db.conn.lock().unwrap().query_row("SELECT COUNT(*) FROM audit_trail", [], |r| r.get(0)).unwrap();
        assert_eq!(count, 1);

        // Verify fetching audit trail sequential list
        let records = db.get_audit_trail().unwrap();
        assert_eq!(records.len(), 1);
        assert_eq!(records[0].uuid, "uuid-1234");
        assert_eq!(records[0].audit_hash, "hash1");
        assert_eq!(records[0].audit_chain_index, 1);
        
        // Verify upsert (REPLACE) works for same UUID
        db.insert_audit_trail("uuid-1234", "hash1-updated", "hash0", 1).unwrap();
        let count_after_upsert: i32 = db.conn.lock().unwrap().query_row("SELECT COUNT(*) FROM audit_trail", [], |r| r.get(0)).unwrap();
        assert_eq!(count_after_upsert, 1); // Should overwrite, not add another row
        
        let hash: String = db.conn.lock().unwrap().query_row("SELECT audit_hash FROM audit_trail WHERE uuid = 'uuid-1234'", [], |r| r.get(0)).unwrap();
        assert_eq!(hash, "hash1-updated");
    }

    #[test]
    /// #304: `logMaxDays` must actually delete by age. Row-count pruning alone
    /// cannot express a retention window.
    #[test]
    fn test_prune_logs_older_than_deletes_only_aged_rows() {
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");

        db.insert_log("INFO", "fresh", "plugin").unwrap();
        db.insert_log("INFO", "stale", "plugin").unwrap();
        // Backdate the second row well past any retention window under test.
        db.conn
            .lock()
            .unwrap()
            .execute(
                "UPDATE logs SET timestamp = datetime('now', '-30 days') WHERE message = 'stale'",
                [],
            )
            .unwrap();

        db.prune_logs_older_than(7).unwrap();

        let logs = db.get_logs(10).unwrap();
        assert_eq!(logs.len(), 1, "only the aged row should be pruned");
        assert_eq!(logs[0].message, "fresh");
    }

    /// A non-positive window means "no age-based retention", not "delete all" —
    /// callers pass the config value straight through.
    #[test]
    fn test_prune_logs_older_than_is_a_no_op_for_non_positive_windows() {
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");
        db.insert_log("INFO", "keep me", "plugin").unwrap();
        db.conn
            .lock()
            .unwrap()
            .execute("UPDATE logs SET timestamp = datetime('now', '-999 days')", [])
            .unwrap();

        db.prune_logs_older_than(0).unwrap();
        db.prune_logs_older_than(-1).unwrap();

        assert_eq!(db.get_logs(10).unwrap().len(), 1);
    }

    #[test]
    fn test_logs_crud() {
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");
        
        db.insert_log("INFO", "Test log message 1", "plugin").unwrap();
        db.insert_log("ERROR", "Test log message 2", "dart").unwrap();
        
        let count: i32 = db.conn.lock().unwrap().query_row("SELECT COUNT(*) FROM logs", [], |r| r.get(0)).unwrap();
        assert_eq!(count, 2);

        // Fetch logs (should be ordered DESC by id)
        let logs = db.get_logs(10).unwrap();
        assert_eq!(logs.len(), 2);
        assert_eq!(logs[0].level, "ERROR");
        assert_eq!(logs[0].message, "Test log message 2");
        assert_eq!(logs[0].source, "dart");
        
        assert_eq!(logs[1].level, "INFO");
        
        // Clear logs
        db.clear_logs().unwrap();
        let count_after_clear: i32 = db.conn.lock().unwrap().query_row("SELECT COUNT(*) FROM logs", [], |r| r.get(0)).unwrap();
        assert_eq!(count_after_clear, 0);
    }

    #[test]
    fn test_insert_location_returns_id() {
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");
        let id1 = db.insert_location(None, 1.0, 1.0, 10.0, 1.5, 90.0, 15.0, false, false, "walking", -1, None, None, None, None, None).unwrap();
        let id2 = db.insert_location(None, 2.0, 2.0, 10.0, 1.5, 90.0, 15.0, false, false, "walking", -1, None, None, None, None, None).unwrap();
        assert_eq!(id1, 1);
        assert_eq!(id2, 2);
    }

    #[test]
    fn test_location_query_with_timestamp_filtering() {
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");
        
        use chrono::TimeZone;
        let t1 = chrono::Utc.timestamp_millis_opt(1704103200000).unwrap().to_rfc3339();
        let t2 = chrono::Utc.timestamp_millis_opt(1704106800000).unwrap().to_rfc3339();
        let t3 = chrono::Utc.timestamp_millis_opt(1704110400000).unwrap().to_rfc3339();
        
        db.insert_location(None, 1.0, 1.0, 10.0, 1.5, 90.0, 15.0, false, false, "walking", -1, None, Some(t1.clone()), None, None, None).unwrap();
        db.insert_location(None, 2.0, 2.0, 10.0, 1.5, 90.0, 15.0, false, false, "walking", -1, None, Some(t2.clone()), None, None, None).unwrap();
        db.insert_location(None, 3.0, 3.0, 10.0, 1.5, 90.0, 15.0, false, false, "walking", -1, None, Some(t3.clone()), None, None, None).unwrap();

        // Query between t2 and t3
        let query = LocationQuery {
            start_time_ms: Some(1704106800000), // t2
            end_time_ms: Some(1704110400000),   // t3
            limit: None,
            offset: None,
            order_descending: None,
        };
        
        let locations = db.get_locations_batch(Some(query)).unwrap();
        assert_eq!(locations.len(), 2);
        assert_eq!(locations[0].timestamp, t2);
        assert_eq!(locations[1].timestamp, t3);
    }

    #[test]
    fn test_location_query_limit_offset() {
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");
        
        for i in 1..=5 {
            db.insert_location(None, i as f64, i as f64, 10.0, 1.5, 90.0, 15.0, false, false, "walking", -1, None, None, None, None, None).unwrap();
        }

        // Test limit and offset
        let query1 = LocationQuery {
            start_time_ms: None,
            end_time_ms: None,
            limit: Some(2),
            offset: Some(1),
            order_descending: Some(true),
        };
        let locations1 = db.get_locations_batch(Some(query1)).unwrap();
        assert_eq!(locations1.len(), 2);
        assert_eq!(locations1[0].id, 4); // DESC: 5, 4, 3, 2, 1 -> offset 1 -> 4, 3
        assert_eq!(locations1[1].id, 3);

        // Test limit -1 (default missing limit) with offset
        let query2 = LocationQuery {
            start_time_ms: None,
            end_time_ms: None,
            limit: Some(-1),
            offset: Some(2),
            order_descending: Some(false),
        };
        let locations2 = db.get_locations_batch(Some(query2)).unwrap();
        assert_eq!(locations2.len(), 3); // ASC: 1, 2, 3, 4, 5 -> offset 2 -> 3, 4, 5
        assert_eq!(locations2[0].id, 3);
        assert_eq!(locations2[2].id, 5);
    }

    #[test]
    fn test_unbounded_query_returns_all_rows_past_legacy_1000_cap() {
        // Regression for Issue #139: an unspecified limit must return EVERY row,
        // not silently cap at the legacy 1000. Insert > 1000 and read with no
        // query (limit = None) and with an explicit None-limit query.
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");
        for i in 1..=1500 {
            db.insert_location(None, i as f64, i as f64, 10.0, 1.5, 90.0, 15.0, false, false, "walking", -1, None, None, None, None, None).unwrap();
        }

        // No query at all.
        assert_eq!(db.get_locations_batch(None).unwrap().len(), 1500);

        // Query present but limit unset → still unbounded.
        let unbounded = LocationQuery {
            start_time_ms: None,
            end_time_ms: None,
            limit: None,
            offset: None,
            order_descending: None,
        };
        assert_eq!(db.get_locations_batch(Some(unbounded)).unwrap().len(), 1500);

        // An explicit limit is still honored.
        let capped = LocationQuery {
            start_time_ms: None,
            end_time_ms: None,
            limit: Some(250),
            offset: None,
            order_descending: None,
        };
        assert_eq!(db.get_locations_batch(Some(capped)).unwrap().len(), 250);
    }

    #[test]
    fn test_delete_locations() {
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");
        
        let id1 = db.insert_location(None, 1.0, 1.0, 10.0, 1.5, 90.0, 15.0, false, false, "walking", -1, None, None, None, None, None).unwrap();
        db.insert_location(None, 2.0, 2.0, 10.0, 1.5, 90.0, 15.0, false, false, "walking", -1, None, None, None, None, None).unwrap();
        
        assert_eq!(db.get_locations_count().unwrap(), 2);
        
        db.destroy_location(id1).unwrap();
        assert_eq!(db.get_locations_count().unwrap(), 1);
        
        db.destroy_locations().unwrap();
        assert_eq!(db.get_locations_count().unwrap(), 0);
    }

    /// Regression for #251: the public location identifier is a UUID string, not
    /// the numeric row id. The native SDKs resolve that UUID to its id via
    /// `get_location_for_audit(uuid)` and then call `destroy_location(id)`.
    /// This verifies that end-to-end flow with a real UUID.
    #[test]
    fn test_destroy_location_resolved_by_uuid() {
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");

        let uuid = "36ef46cf-b797-460e-afba-b6687af0f5bb";
        db.insert_location(Some(uuid.to_string()), 1.0, 1.0, 10.0, 1.5, 90.0, 15.0, false, false, "walking", -1, None, None, None, None, None).unwrap();
        db.insert_location(Some("other-uuid".to_string()), 2.0, 2.0, 10.0, 1.5, 90.0, 15.0, false, false, "walking", -1, None, None, None, None, None).unwrap();
        assert_eq!(db.get_locations_count().unwrap(), 2);

        // A real UUID is not a numeric row id — deleting requires resolving it.
        assert!(uuid.parse::<i64>().is_err());

        let record = db
            .get_location_for_audit(uuid)
            .unwrap()
            .expect("location should be resolvable by uuid");
        assert_eq!(record.uuid.as_deref(), Some(uuid));

        db.destroy_location(record.id).unwrap();

        assert_eq!(db.get_locations_count().unwrap(), 1);
        assert!(
            db.get_location_for_audit(uuid).unwrap().is_none(),
            "the location addressed by uuid must be gone"
        );
    }

    #[test]
    fn test_delete_synced_locations() {
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");
        
        db.insert_location(None, 1.0, 1.0, 10.0, 1.5, 90.0, 15.0, false, false, "walking", -1, None, None, None, None, None).unwrap();
        let id2 = db.insert_location(None, 2.0, 2.0, 10.0, 1.5, 90.0, 15.0, false, false, "walking", -1, None, None, None, None, None).unwrap();
        let id3 = db.insert_location(None, 3.0, 3.0, 10.0, 1.5, 90.0, 15.0, false, false, "walking", -1, None, None, None, None, None).unwrap();
        
        assert_eq!(db.get_locations_count().unwrap(), 3);
        
        // Sync clears up to max ID
        db.clear_locations_up_to(id2).unwrap();
        
        assert_eq!(db.get_locations_count().unwrap(), 1);
        let remaining = db.get_locations_batch(None).unwrap();
        assert_eq!(remaining[0].id, id3);
    }

    #[test]
    fn geofence_event_roundtrips_with_type_and_payload() {
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");
        let payload = r#"{"identifier":"home","action":"ENTER"}"#.to_string();
        db.insert_location(Some("gf-1".into()), 1.0, 2.0, 10.0, 0.0, 0.0, 0.0, false, false, "still",
                           -1, None, None, Some("geofence".into()), Some(payload.clone()), None).unwrap();
        let rows = db.get_locations_batch(None).unwrap();
        let gf = rows.iter().find(|r| r.uuid.as_deref() == Some("gf-1")).expect("row");
        assert_eq!(gf.event_type, "geofence");
        assert_eq!(gf.event_payload.as_deref(), Some(payload.as_str()));

        // A default location insert still reads back as 'location'.
        db.insert_location(Some("loc-1".into()), 1.0, 2.0, 5.0, 0.0, 0.0, 0.0, false, true, "walking",
                           -1, None, None, None, None, None).unwrap();
        let loc = db.get_locations_batch(None).unwrap();
        let l = loc.iter().find(|r| r.uuid.as_deref() == Some("loc-1")).unwrap();
        assert_eq!(l.event_type, "location");
    }

    #[test]
    fn test_address_round_trips_through_insert_and_read() {
        // #187: a resolved address must survive persistence into the DB-sourced
        // sync payload, not just the live onLocation event.
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");
        let address = "{\"city\":\"Palakkad\",\"state\":\"Kerala\",\"country\":\"India\"}";
        db.insert_location(Some("addr-1".into()), 10.78, 76.68, 20.0, 0.1, 0.0, 11.0,
            false, false, "unknown", -1, None, None, None, None, Some(address.to_string())).unwrap();

        let rows = db.get_locations_batch(None).unwrap();
        let r = rows.iter().find(|r| r.uuid.as_deref() == Some("addr-1")).expect("row");
        assert_eq!(r.address.as_deref(), Some(address), "address must round-trip");

        // A location inserted without an address reads back as None.
        db.insert_location(Some("addr-2".into()), 10.78, 76.68, 20.0, 0.1, 0.0, 11.0,
            false, false, "unknown", -1, None, None, None, None, None).unwrap();
        let r2 = db.get_locations_batch(None).unwrap();
        let l2 = r2.iter().find(|r| r.uuid.as_deref() == Some("addr-2")).unwrap();
        assert_eq!(l2.address, None, "no address → None");
    }

    #[test]
    fn test_address_round_trips_under_encryption() {
        // Under encryption the address lives in the encrypted payload (PII), and
        // must still decrypt back on read.
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");
        db.set_encryption_key("test-key-187");
        let address = "{\"city\":\"Palakkad\"}";
        db.insert_location(Some("enc-addr".into()), 10.78, 76.68, 20.0, 0.0, 0.0, 0.0,
            false, false, "unknown", -1, None, None, None, None, Some(address.to_string())).unwrap();

        let rows = db.get_locations_batch(None).unwrap();
        let r = rows.iter().find(|r| r.uuid.as_deref() == Some("enc-addr")).expect("row");
        assert_eq!(r.address.as_deref(), Some(address), "encrypted address must round-trip");
    }
}
