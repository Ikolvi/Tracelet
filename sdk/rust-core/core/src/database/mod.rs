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
    /// The trip every subsequent insert is stamped with (#402), or `None`
    /// between trips.
    ///
    /// Held here rather than threaded through `insert_location` /
    /// `insert_telematics_event` so that *every* write path picks it up —
    /// including the ones that never touch the trip manager, such as the
    /// periodic-fix worker, the geofence writer, and the four native telematics
    /// call sites. A parameter would have to be remembered at each of them and
    /// silently produces a NULL when it is not.
    active_trip_id: RwLock<Option<String>>,
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
    /// The trip this row was written during (#402), or `None` if no trip was
    /// active. Stamped at INSERT and never rewritten, so a row uploaded hours
    /// later still carries the trip it actually belongs to.
    pub trip_id: Option<String>,
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
    /// Speed at the event (m/s) — 0.0 for rows written before #367.
    pub speed: f64,
    /// The measured magnitude that triggered it: g for harsh events, km/h over
    /// the limit for speeding. 0.0 for rows written before #367.
    pub value: f64,
    pub latitude: f64,
    pub longitude: f64,
    pub timestamp: String,
    pub synced: bool,
    /// The trip this event occurred during (#402), or `None` outside a trip.
    pub trip_id: Option<String>,
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
                speed REAL NOT NULL DEFAULT 0.0,
                event_value REAL NOT NULL DEFAULT 0.0,
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

        // #367: the driving-event magnitudes. `DrivingEvent` has always carried
        // `speed` and `value` and always delivered them to `onDrivingEvent`, but
        // the table had nowhere to put them, so stored history and every synced
        // payload lost them. Rows written before this migration read back as 0.0.
        let _ = conn.execute("ALTER TABLE tracelet_telematics ADD COLUMN speed REAL NOT NULL DEFAULT 0.0", []);
        let _ = conn.execute("ALTER TABLE tracelet_telematics ADD COLUMN event_value REAL NOT NULL DEFAULT 0.0", []);

        // #402: the trip correlation key. Stamped at INSERT from the active
        // trip, so it records the trip a row was *written* under rather than
        // whatever happens to be running when it finally uploads — the
        // distinction that makes an offline queue correct. Stays a plaintext
        // column under encryption for the same reason `route_context` does:
        // it has to be queryable to correlate, and an opaque random id is not
        // coordinate-level PII. Rows written before this migration read NULL.
        let _ = conn.execute("ALTER TABLE location_events ADD COLUMN trip_id TEXT", []);
        let _ = conn.execute("ALTER TABLE tracelet_telematics ADD COLUMN trip_id TEXT", []);
        let _ = conn.execute("CREATE INDEX IF NOT EXISTS idx_location_events_trip_id ON location_events(trip_id)", []);
        let _ = conn.execute("CREATE INDEX IF NOT EXISTS idx_tracelet_telematics_trip_id ON tracelet_telematics(trip_id)", []);

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
            active_trip_id: RwLock::new(None),
        })
    }

    /// Sets the trip that subsequent inserts are stamped with (#402).
    ///
    /// Called with the id minted by the trip manager at trip start, and with
    /// `None` at trip end. Records written outside a trip carry no trip id;
    /// they are not retroactively assigned one when the next trip begins,
    /// because the value records the state at the moment of the write.
    pub fn set_active_trip_id(&self, trip_id: Option<String>) {
        *self.active_trip_id.write().unwrap() = trip_id.filter(|t| !t.is_empty());
    }

    /// The trip subsequent inserts will be stamped with, if any (#402).
    pub fn active_trip_id(&self) -> Option<String> {
        self.active_trip_id.read().unwrap().clone()
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

        // #402: the trip in force at this instant. Read here, at the write, so
        // the row is stamped with the trip it was recorded under.
        let trip_id = self.active_trip_id.read().unwrap().clone();

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
                    "INSERT INTO location_events (uuid, timestamp, latitude, longitude, accuracy, speed, heading, altitude, is_mock, is_moving, activity, activity_confidence, encrypted_payload, route_context, timestamp_ms, event_type, event_payload, address, trip_id)
                     VALUES (?1, ?2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, 0, '', -1, ?3, ?4, ?5, ?6, ?7, NULL, ?8)",
                    params![uuid, timestamp, payload, route_context, timestamp_ms, event_type, event_payload, trip_id],
                ).map_err(|e| TraceletError::Database(e.to_string()))?;
                return Ok(conn.last_insert_rowid());
            }
        }

        // Fallback or unencrypted
        conn.execute(
            "INSERT INTO location_events (uuid, timestamp, latitude, longitude, accuracy, speed, heading, altitude, is_mock, is_moving, activity, activity_confidence, encrypted_payload, route_context, timestamp_ms, event_type, event_payload, address, trip_id)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, NULL, ?13, ?14, ?15, ?16, ?17, ?18)",
            params![uuid, timestamp, lat, lng, acc, speed, heading, altitude, if is_mock { 1 } else { 0 }, if is_moving { 1 } else { 0 }, activity, activity_confidence, route_context, timestamp_ms, event_type, event_payload, address, trip_id],
        ).map_err(|e| TraceletError::Database(e.to_string()))?;

        Ok(conn.last_insert_rowid())
    }

    /// Retrieves a batch of location records, with optional filtering.
    pub fn get_locations_batch(&self, query: Option<LocationQuery>) -> Result<Vec<DbLocationRecord>, TraceletError> {
        use rusqlite::types::Value;
        let conn = self.conn.lock().unwrap();
        
        let mut sql = "SELECT id, uuid, timestamp, latitude, longitude, accuracy, speed, heading, altitude, is_mock, is_moving, activity, encrypted_payload, route_context, event_type, event_payload, address, activity_confidence, trip_id FROM location_events WHERE 1=1".to_string();
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
            // #402: plaintext column in both storage modes — see the migration.
            let trip_id: Option<String> = row.get(18).unwrap_or(None);

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
                trip_id,
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
        let sql = "SELECT id, uuid, timestamp, latitude, longitude, accuracy, speed, heading, altitude, is_mock, is_moving, activity, encrypted_payload, route_context, event_type, event_payload, address, activity_confidence, trip_id FROM location_events WHERE uuid = ?1 LIMIT 1";
        
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
            // #402: plaintext column in both storage modes — see the migration.
            let trip_id: Option<String> = row.get(18).unwrap_or(None);

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
                trip_id,
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

    /// Deletes location rows older than `max_days`, reporting how many went
    /// (#361).
    ///
    /// `maxDaysToPersist` was enforced up to 3.0 by `pruneOldLocations` in the
    /// platform-native `TraceletDatabase` classes. The 3.1.0 migration onto this
    /// shared core replaced the whole persist body with a sink fan-out and took
    /// the retention calls with it; no equivalent was ever added here, so the
    /// documented 1-day default and every explicit override silently did nothing
    /// while the local queue grew without bound.
    ///
    /// `max_days <= 0` is a no-op rather than an error, so callers can pass the
    /// config value straight through to mean "no age-based retention" — matching
    /// [`prune_logs_older_than`](Self::prune_logs_older_than) and the `-1`
    /// unlimited sentinel the public config documents.
    ///
    /// Age is taken from `timestamp_ms`, which is indexed and which
    /// [`insert_location`](Self::insert_location) always populates. Rows written
    /// before that column existed default to `0`; they are aged off the TEXT
    /// `timestamp` instead rather than being read as epoch-old and destroyed on
    /// the first prune. A row whose `timestamp` SQLite cannot parse yields NULL,
    /// compares false, and is kept — retention must never be the reason data
    /// disappears on a guess. Those rows are still bounded by
    /// [`enforce_max_location_records`](Self::enforce_max_location_records),
    /// which orders by `id` and so needs no timestamp at all.
    pub fn prune_locations_older_than(&self, max_days: i32) -> Result<u32, TraceletError> {
        if max_days <= 0 {
            return Ok(0);
        }
        let cutoff_ms = (Utc::now() - chrono::Duration::days(i64::from(max_days))).timestamp_millis();
        let conn = self.conn.lock().unwrap();
        // Split rather than OR'd so the common case stays a range scan on
        // idx_location_events_timestamp_ms; the strftime branch cannot use an
        // index and only ever matches pre-`timestamp_ms` rows.
        let mut removed = Self::delete_locations_where(
            &conn,
            "timestamp_ms > 0 AND timestamp_ms < ?1",
            cutoff_ms,
        )?;
        removed += Self::delete_locations_where(
            &conn,
            "timestamp_ms <= 0 AND CAST(strftime('%s', timestamp) AS INTEGER) * 1000 < ?1",
            cutoff_ms,
        )?;
        Ok(removed)
    }

    /// Caps `location_events` at `max_records` rows, deleting the oldest first
    /// and reporting how many went (#361).
    ///
    /// The count companion to
    /// [`prune_locations_older_than`](Self::prune_locations_older_than), and the
    /// bound that actually holds during a long offline stretch: an age window
    /// alone cannot express "never queue more than N", because how many rows a
    /// day is depends entirely on the sampling cadence in force.
    ///
    /// `max_records <= 0` is a no-op, carrying the `-1` unlimited sentinel.
    ///
    /// Oldest is decided by `id`, not by any timestamp: `id` is the insertion
    /// order the sync batcher already uploads and acknowledges in, and it stays
    /// correct when fixes arrive out of order or carry a spoofed clock — a
    /// timestamp-ordered cap would let one bogus future fix pin itself in the
    /// queue and evict every real record around it.
    pub fn enforce_max_location_records(&self, max_records: i32) -> Result<u32, TraceletError> {
        if max_records <= 0 {
            return Ok(0);
        }
        let conn = self.conn.lock().unwrap();
        Self::delete_locations_where(
            &conn,
            "id NOT IN (SELECT id FROM location_events ORDER BY id DESC LIMIT ?1)",
            i64::from(max_records),
        )
    }

    // --- Geofences ---
    
    pub fn insert_geofence(
        &self, 
        identifier: &str, 
        lat: f64, 
        lng: f64, 
        radius: f64,
        vertices: Option<Vec<Coordinate>>,
        extras: Option<String>,
        notify_on_entry: bool,
        notify_on_exit: bool,
        notify_on_dwell: bool,
        loitering_delay: i32,
    ) -> Result<(), TraceletError> {
        let conn = self.conn.lock().unwrap();
        let vertices_json = match vertices {
            Some(v) if !v.is_empty() => {
                let json_vec: Vec<Vec<f64>> = v.iter().map(|c| vec![c.lat, c.lng]).collect();
                Some(serde_json::to_string(&json_vec).unwrap_or_default())
            },
            _ => None,
        };
        // The four notify_* columns already existed but were never written, so
        // every fence fell back to the column defaults on read — which is how
        // DWELL silently stopped working after a restore (#355).
        conn.execute(
            "INSERT OR REPLACE INTO geofences (identifier, latitude, longitude, radius, vertices, gf_extras, notify_on_entry, notify_on_exit, notify_on_dwell, loitering_delay) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
            params![identifier, lat, lng, radius, vertices_json, extras,
                    notify_on_entry as i32, notify_on_exit as i32,
                    notify_on_dwell as i32, loitering_delay]
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
        let mut stmt = conn.prepare("SELECT identifier, latitude, longitude, radius, vertices, gf_extras, notify_on_entry, notify_on_exit, notify_on_dwell, loitering_delay FROM geofences")
            .map_err(|e| TraceletError::Database(e.to_string()))?;

        let iter = stmt.query_map([], |row| {
            let identifier: String = row.get(0)?;
            let latitude: f64 = row.get(1)?;
            let longitude: f64 = row.get(2)?;
            let radius: f64 = row.get(3)?;
            let vertices_str: Option<String> = row.get(4)?;
            let extras: Option<String> = row.get(5)?;
            // Rows written before these were persisted carry the column
            // defaults (1/1/0/0), which is the historical behaviour.
            let notify_on_entry: i32 = row.get(6).unwrap_or(1);
            let notify_on_exit: i32 = row.get(7).unwrap_or(1);
            let notify_on_dwell: i32 = row.get(8).unwrap_or(0);
            let loitering_delay: i32 = row.get(9).unwrap_or(0);

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
                notify_on_entry: notify_on_entry != 0,
                notify_on_exit: notify_on_exit != 0,
                notify_on_dwell: notify_on_dwell != 0,
                loitering_delay,
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
    ///
    /// `speed` (m/s) and `value` (g, or km/h over the limit for speeding) are the
    /// magnitudes carried by `DrivingEvent`. They used to be dropped here, which
    /// left stored history and every synced payload with a normalized `severity`
    /// flag and no physical quantity behind it (#367).
    pub fn insert_telematics_event(&self, event_type: &str, severity: f64, speed: f64, value: f64, lat: f64, lng: f64) -> Result<i64, TraceletError> {
        let conn = self.conn.lock().unwrap();
        // #402: stamped from the active trip at write time, exactly as
        // locations are, so a driving event correlates with the locations
        // recorded around it.
        let trip_id = self.active_trip_id.read().unwrap().clone();
        conn.execute(
            "INSERT INTO tracelet_telematics (event_type, severity, speed, event_value, latitude, longitude, trip_id) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![event_type, severity, speed, value, lat, lng, trip_id]
        ).map_err(|e| TraceletError::Database(e.to_string()))?;
        Ok(conn.last_insert_rowid())
    }

    /// Retrieves a batch of **unsynced** telematics events, oldest first.
    ///
    /// This is the *sync* view: the batcher uploads them in id order and then
    /// calls [`mark_telematics_synced`](Self::mark_telematics_synced) with the
    /// highest id it sent, so already-uploaded events must be excluded and the
    /// order must be ascending. Use
    /// [`get_telematics_history`](Self::get_telematics_history) for anything
    /// user-facing (#313).
    pub fn get_telematics_events(&self, limit: i32) -> Result<Vec<DbTelematicsRecord>, TraceletError> {
        self.query_telematics(
            "SELECT id, event_type, severity, latitude, longitude, timestamp, synced, speed, event_value, trip_id FROM tracelet_telematics WHERE synced = 0 ORDER BY id ASC LIMIT ?1",
            limit,
        )
    }

    /// Retrieves the most recent telematics events — **newest first, regardless
    /// of sync state** (#313).
    ///
    /// This is the *history* view behind `Tracelet.getTelematicsEvents()` and the
    /// Doctor bug report. It deliberately does not filter on `synced`: the sync
    /// flag records whether an event was uploaded, which says nothing about
    /// whether the user should still see it. Sharing the sync query meant an app
    /// with `syncTelematics` enabled watched its own local history empty out, and
    /// that `ORDER BY id ASC LIMIT n` returned the *oldest* n rather than the
    /// most recent n it documented.
    pub fn get_telematics_history(&self, limit: i32) -> Result<Vec<DbTelematicsRecord>, TraceletError> {
        self.query_telematics(
            "SELECT id, event_type, severity, latitude, longitude, timestamp, synced, speed, event_value, trip_id FROM tracelet_telematics ORDER BY id DESC LIMIT ?1",
            limit,
        )
    }

    /// Marks telematics events up to max_id as synced.
    pub fn mark_telematics_synced(&self, max_id: i64) -> Result<(), TraceletError> {
        let conn = self.conn.lock().unwrap();
        conn.execute("UPDATE tracelet_telematics SET synced = 1 WHERE id <= ?1", params![max_id])
            .map_err(|e| TraceletError::Database(e.to_string()))?;
        Ok(())
    }

    /// Deletes **synced** telematics rows beyond the newest `keep` of them, and
    /// reports how many went (#366).
    ///
    /// Sync marks rows instead of deleting them, because #313 established that
    /// uploading an event must not remove it from the app's own history. That
    /// leaves the table growing for the lifetime of the install, so the synced
    /// tail is trimmed here. Unsynced rows are never touched — they are still
    /// owed to the server, and losing them is the bug this accompanies.
    pub fn prune_synced_telematics(&self, keep: i32) -> Result<u64, TraceletError> {
        if keep <= 0 {
            return Ok(0);
        }
        let conn = self.conn.lock().unwrap();
        let removed = conn.execute(
            "DELETE FROM tracelet_telematics WHERE synced = 1 AND id NOT IN (
                 SELECT id FROM tracelet_telematics WHERE synced = 1 ORDER BY id DESC LIMIT ?1
             )",
            params![keep],
        ).map_err(|e| TraceletError::Database(e.to_string()))?;
        Ok(removed as u64)
    }

    /// Clears all telematics events from the database.
    pub fn clear_telematics_events(&self) -> Result<(), TraceletError> {
        let conn = self.conn.lock().unwrap();
        conn.execute("DELETE FROM tracelet_telematics", [])
            .map_err(|e| TraceletError::Database(e.to_string()))?;
        Ok(())
    }
}

/// Internal helpers.
///
/// Deliberately a separate, **non-exported** impl block: `#[uniffi::export]`
/// exports every method in its block regardless of visibility, so putting a
/// SQL-taking helper there would hand hosts an arbitrary-query FFI entry point.
impl DatabaseManager {
    /// Runs a telematics `SELECT` taking a single `LIMIT` parameter and whose
    /// columns are `id, event_type, severity, latitude, longitude, timestamp,
    /// synced` in that order.
    fn query_telematics(&self, sql: &str, limit: i32) -> Result<Vec<DbTelematicsRecord>, TraceletError> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(sql)
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
                // #367: appended after `synced` so both callers' SELECT lists stay
                // aligned with the pre-existing column order.
                speed: row.get(7)?,
                value: row.get(8)?,
                // #402: appended last for the same reason — the SELECT lists of
                // both readers stay aligned with the existing column order.
                trip_id: row.get(9).unwrap_or(None),
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

    /// Deletes the `location_events` rows matching `predicate` — a `WHERE`
    /// fragment binding exactly one `?1` — and reports how many went (#361).
    ///
    /// Takes the audit-chain rows with them, the way
    /// [`clear_locations_up_to`](Self::clear_locations_up_to) does on the sync
    /// path. Retention that dropped locations but left `audit_trail` behind
    /// would just move the unbounded growth into a table with no cap of its own
    /// and no way to reach the orphans, since that table is keyed by a `uuid`
    /// which no longer resolves.
    ///
    /// Both statements bind the same value, so the caller passes it once. Takes
    /// the already-locked `conn` rather than re-locking, which lets a caller run
    /// several predicates inside one critical section.
    fn delete_locations_where(
        conn: &Connection,
        predicate: &str,
        bind: i64,
    ) -> Result<u32, TraceletError> {
        conn.execute(
            &format!(
                "DELETE FROM audit_trail WHERE uuid IN \
                 (SELECT uuid FROM location_events WHERE ({predicate}) AND uuid IS NOT NULL)"
            ),
            params![bind],
        )
        .map_err(|e| TraceletError::Database(e.to_string()))?;

        let removed = conn
            .execute(
                &format!("DELETE FROM location_events WHERE {predicate}"),
                params![bind],
            )
            .map_err(|e| TraceletError::Database(e.to_string()))?;
        Ok(removed as u32)
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
        db.insert_geofence("home_zone", 37.0, -122.0, 150.0, None, None, true, true, false, 0).unwrap();
        
        let count: i32 = db.conn.lock().unwrap().query_row("SELECT COUNT(*) FROM geofences", [], |r| r.get(0)).unwrap();
        assert_eq!(count, 1);

        // Test inserting a polygon geofence with extras
        let vertices = vec![
            Coordinate { lat: 37.0, lng: -122.0 },
            Coordinate { lat: 37.1, lng: -122.1 },
            Coordinate { lat: 37.2, lng: -122.2 }
        ];
        let extras = Some("{\"type\":\"polygon\",\"color\":\"blue\"}".to_string());
        db.insert_geofence("home_zone", 37.0, -122.0, 150.0, Some(vertices), extras, true, true, true, 30000).unwrap();

        // Verify retrieval of geofences and parsing of vertices and extras
        let geofences = db.get_geofences().unwrap();
        assert_eq!(geofences.len(), 1);
        assert_eq!(geofences[0].identifier, "home_zone");
        assert_eq!(geofences[0].vertices.len(), 3);
        assert_eq!(geofences[0].vertices[0].lat, 37.0);
        assert_eq!(geofences[0].vertices[2].lng, -122.2);
        assert_eq!(geofences[0].extras.as_ref().unwrap(), "{\"type\":\"polygon\",\"color\":\"blue\"}");
        // #355: the notify_* flags and loitering delay must round-trip. They
        // were never written, so a restored fence lost DWELL for good.
        assert!(geofences[0].notify_on_dwell, "notify_on_dwell must round-trip");
        assert_eq!(geofences[0].loitering_delay, 30000, "loitering_delay must round-trip");
        assert!(geofences[0].notify_on_entry);
        assert!(geofences[0].notify_on_exit);
        
        // Delete the geofence
        db.delete_geofence("home_zone").unwrap();
        let count_after_delete: i32 = db.conn.lock().unwrap().query_row("SELECT COUNT(*) FROM geofences", [], |r| r.get(0)).unwrap();
        assert_eq!(count_after_delete, 0);
        
        // Batch inserting and clearing multiple
        db.insert_geofence("work", 38.0, -121.0, 50.0, None, None, true, true, false, 0).unwrap();
        db.insert_geofence("gym", 39.0, -120.0, 100.0, None, None, true, true, false, 0).unwrap();
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

    /// Inserts a location whose fix time is `days_ago` days in the past.
    fn insert_location_aged(db: &DatabaseManager, activity: &str, days_ago: i64) {
        let ts = (Utc::now() - chrono::Duration::days(days_ago)).to_rfc3339();
        db.insert_location(
            Some(format!("uuid-{activity}")), 1.0, 2.0, 5.0, 0.0, 0.0, 0.0, false, false,
            activity, -1, None, Some(ts), None, None, None,
        )
        .unwrap();
    }

    fn activities(db: &DatabaseManager) -> Vec<String> {
        db.get_locations_batch(None)
            .unwrap()
            .into_iter()
            .map(|r| r.activity)
            .collect()
    }

    /// The reporter's `maxDaysToPersist` case: a fixture two days old must not
    /// survive a one-day window, and today's fix must (#361).
    #[test]
    fn test_prune_locations_older_than_deletes_only_aged_rows() {
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");
        insert_location_aged(&db, "fresh", 0);
        insert_location_aged(&db, "stale", 2);

        assert_eq!(db.prune_locations_older_than(1).unwrap(), 1);

        assert_eq!(activities(&db), vec!["fresh".to_string()]);
    }

    /// A non-positive window means "no age-based retention", not "delete all" —
    /// `-1` is the documented unlimited sentinel and is passed through verbatim.
    #[test]
    fn test_prune_locations_older_than_is_a_no_op_for_non_positive_windows() {
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");
        insert_location_aged(&db, "ancient", 999);

        assert_eq!(db.prune_locations_older_than(0).unwrap(), 0);
        assert_eq!(db.prune_locations_older_than(-1).unwrap(), 0);

        assert_eq!(db.get_locations_count().unwrap(), 1);
    }

    /// Rows predating the `timestamp_ms` column carry the `0` default and must
    /// age off the TEXT `timestamp` instead of reading as epoch-old — otherwise
    /// the first prune after an upgrade wipes the queue. Also pins that the
    /// bundled SQLite parses what `to_rfc3339()` writes (offset plus a
    /// nanosecond fraction), since the fallback is a text parse.
    #[test]
    fn test_prune_locations_older_than_ages_legacy_rows_off_the_text_timestamp() {
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");
        let stale = (Utc::now() - chrono::Duration::days(30)).to_rfc3339();
        let fresh = Utc::now().to_rfc3339();
        for (activity, ts) in [("legacy-stale", &stale), ("legacy-fresh", &fresh)] {
            db.conn.lock().unwrap().execute(
                "INSERT INTO location_events (timestamp, latitude, longitude, accuracy, speed, heading, altitude, is_mock, activity)
                 VALUES (?1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, ?2)",
                params![ts, activity],
            ).unwrap();
        }

        assert_eq!(db.prune_locations_older_than(7).unwrap(), 1);

        assert_eq!(activities(&db), vec!["legacy-fresh".to_string()]);
    }

    /// An unusable timestamp is kept, not guessed at: retention must never be
    /// the reason a record disappears. The count cap still bounds these.
    #[test]
    fn test_prune_locations_older_than_keeps_rows_it_cannot_date() {
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");
        db.conn.lock().unwrap().execute(
            "INSERT INTO location_events (timestamp, latitude, longitude, accuracy, speed, heading, altitude, is_mock, activity)
             VALUES ('not a date', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, 'undateable')",
            [],
        ).unwrap();

        assert_eq!(db.prune_locations_older_than(1).unwrap(), 0);

        assert_eq!(db.get_locations_count().unwrap(), 1);
    }

    /// The reporter's `maxRecordsToPersist: 3` case: the queue is capped and the
    /// oldest go first, whatever the fixes claim their time is (#361).
    #[test]
    fn test_enforce_max_location_records_keeps_the_newest_by_insertion_order() {
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");
        // Deliberately descending fix times: the newest row by id claims to be
        // the oldest, so an ORDER BY timestamp cap would evict the wrong rows.
        for (i, activity) in ["first", "second", "third", "fourth", "fifth"].iter().enumerate() {
            insert_location_aged(&db, activity, i as i64);
        }

        assert_eq!(db.enforce_max_location_records(3).unwrap(), 2);

        assert_eq!(db.get_locations_count().unwrap(), 3);
        let kept = activities(&db);
        assert!(!kept.contains(&"first".to_string()));
        assert!(!kept.contains(&"second".to_string()));
        assert!(kept.contains(&"fifth".to_string()));
    }

    #[test]
    fn test_enforce_max_location_records_is_a_no_op_for_non_positive_caps() {
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");
        insert_location_aged(&db, "keep", 0);

        assert_eq!(db.enforce_max_location_records(0).unwrap(), 0);
        assert_eq!(db.enforce_max_location_records(-1).unwrap(), 0);

        assert_eq!(db.get_locations_count().unwrap(), 1);
    }

    /// Both caps must take the audit-chain rows with them. Leaving them behind
    /// moves the unbounded growth into a table with no cap of its own, whose
    /// orphans nothing can reach — they are keyed by a `uuid` that no longer
    /// resolves to a location.
    #[test]
    fn test_retention_takes_the_audit_chain_with_the_locations() {
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");
        for (index, (activity, days_ago)) in
            [("aged", 5), ("mid", 0), ("newest", 0)].iter().enumerate()
        {
            insert_location_aged(&db, activity, *days_ago);
            db.insert_audit_trail(&format!("uuid-{activity}"), "hash", "prev", index as i32)
                .unwrap();
        }
        assert_eq!(db.get_audit_trail().unwrap().len(), 3);

        // Age path: only the aged row's chain entry goes.
        db.prune_locations_older_than(1).unwrap();
        let chain = db.get_audit_trail().unwrap();
        assert_eq!(chain.len(), 2);
        assert!(chain.iter().all(|r| r.uuid != "uuid-aged"));

        // A no-op cap must leave the chain alone.
        db.enforce_max_location_records(-1).unwrap();
        assert_eq!(db.get_audit_trail().unwrap().len(), 2);

        // Count path: capping to the newest row drops the other chain entry too.
        db.enforce_max_location_records(1).unwrap();
        assert_eq!(db.get_locations_count().unwrap(), 1);
        let chain = db.get_audit_trail().unwrap();
        assert_eq!(chain.len(), 1);
        assert_eq!(chain[0].uuid, "uuid-newest");
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

    // ── #313: history view vs sync view ──

    fn telematics_db() -> DatabaseManager {
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");
        db.set_encryption_key("");
        for kind in ["harsh_braking", "harsh_cornering", "speeding", "crash"] {
            db.insert_telematics_event(kind, 0.5, 18.4, 0.47, 1.0, 2.0).unwrap();
        }
        db
    }

    #[test]
    fn telematics_history_is_newest_first() {
        let db = telematics_db();
        let history = db.get_telematics_history(2).unwrap();
        assert_eq!(history.len(), 2);
        // `crash` was inserted last, so it must lead a "most recent" listing.
        assert_eq!(history[0].event_type, "crash");
        assert_eq!(history[1].event_type, "speeding");
    }

    #[test]
    fn telematics_history_survives_sync() {
        // The sync flag records whether an event was uploaded — it must not
        // decide whether the user can still see it. Sharing the sync query meant
        // an app with syncTelematics on watched its own history empty out.
        let db = telematics_db();
        let batch = db.get_telematics_events(10).unwrap();
        let max_id = batch.iter().map(|e| e.id).max().unwrap();
        db.mark_telematics_synced(max_id).unwrap();

        assert!(
            db.get_telematics_events(10).unwrap().is_empty(),
            "sync view must be drained once everything is marked synced"
        );
        assert_eq!(
            db.get_telematics_history(10).unwrap().len(),
            4,
            "history must still show every event after a sync"
        );
    }

    #[test]
    fn telematics_sync_view_stays_oldest_first_and_unsynced_only() {
        // The batcher uploads in id order then marks synced up to a max id, so
        // this view must keep its ascending, unsynced-only contract.
        let db = telematics_db();
        let first_two = db.get_telematics_events(2).unwrap();
        assert_eq!(first_two[0].event_type, "harsh_braking");
        assert_eq!(first_two[1].event_type, "harsh_cornering");

        db.mark_telematics_synced(first_two[1].id).unwrap();
        let rest = db.get_telematics_events(10).unwrap();
        assert_eq!(rest.len(), 2, "already-synced events must not be re-sent");
        assert_eq!(rest[0].event_type, "speeding");
    }

    // ── #367: the driving-event magnitudes ──

    #[test]
    fn telematics_speed_and_value_round_trip_through_both_views() {
        // `severity` is a normalized 0–1 flag; `value` is the measurement that
        // triggered the event and `speed` the context that makes it readable.
        // Dropping them at insert left every stored and synced event with no
        // physical quantity behind it.
        let db = telematics_db();

        let synced_view = db.get_telematics_events(1).unwrap();
        assert_eq!(synced_view[0].speed, 18.4);
        assert_eq!(synced_view[0].value, 0.47);

        let history = db.get_telematics_history(1).unwrap();
        assert_eq!(history[0].speed, 18.4, "history must carry the magnitudes too");
        assert_eq!(history[0].value, 0.47);
    }

    #[test]
    fn telematics_rows_predating_the_magnitude_columns_read_back_as_zero() {
        // Upgrades run ALTER TABLE over a table that already has rows. Those rows
        // have no magnitudes to recover, so they must read back as 0.0 rather
        // than failing the query and taking the whole history with them.
        let db = DatabaseManager::new(":memory:").expect("Failed to create in-memory db");
        db.set_encryption_key("");
        {
            let conn = db.conn.lock().unwrap();
            conn.execute(
                "INSERT INTO tracelet_telematics (event_type, severity, latitude, longitude) \
                 VALUES ('harsh_braking', 0.5, 1.0, 2.0)",
                [],
            )
            .unwrap();
        }

        let history = db.get_telematics_history(10).unwrap();
        assert_eq!(history.len(), 1, "a legacy row must still be readable");
        assert_eq!(history[0].speed, 0.0);
        assert_eq!(history[0].value, 0.0);
    }

    // ── #366: bounding the table that sync no longer empties ──

    #[test]
    fn prune_synced_telematics_never_takes_unsynced_rows() {
        // Unsynced rows are still owed to the server. Trimming history must not
        // become a second way to lose them.
        let db = telematics_db();
        let batch = db.get_telematics_events(2).unwrap();
        db.mark_telematics_synced(batch[1].id).unwrap();

        let removed = db.prune_synced_telematics(1).unwrap();
        assert_eq!(removed, 1, "only the older of the two synced rows may go");

        let remaining = db.get_telematics_events(10).unwrap();
        assert_eq!(remaining.len(), 2, "unsynced rows must survive the trim");
        assert_eq!(remaining[0].event_type, "speeding");
    }

    #[test]
    fn prune_synced_telematics_is_a_no_op_for_non_positive_caps() {
        let db = telematics_db();
        let batch = db.get_telematics_events(10).unwrap();
        db.mark_telematics_synced(batch.last().unwrap().id).unwrap();

        assert_eq!(db.prune_synced_telematics(0).unwrap(), 0);
        assert_eq!(db.prune_synced_telematics(-1).unwrap(), 0);
        assert_eq!(db.get_telematics_history(10).unwrap().len(), 4);
    }

    // ---- #402: trip correlation -------------------------------------------

    #[test]
    fn location_is_stamped_with_the_active_trip() {
        let db = DatabaseManager::new(":memory:").unwrap();
        db.set_encryption_key("");

        db.insert_location(None, 1.0, 1.0, 5.0, 0.0, 0.0, 0.0, false, false, "still", -1, None, None, None, None, None).unwrap();
        db.set_active_trip_id(Some("trip-a".into()));
        db.insert_location(None, 2.0, 2.0, 5.0, 0.0, 0.0, 0.0, false, true, "in_vehicle", -1, None, None, None, None, None).unwrap();
        db.set_active_trip_id(None);
        db.insert_location(None, 3.0, 3.0, 5.0, 0.0, 0.0, 0.0, false, false, "still", -1, None, None, None, None, None).unwrap();

        let rows = db.get_locations_batch(None).unwrap();
        assert_eq!(rows.len(), 3);
        assert_eq!(rows[0].trip_id, None, "written before the trip started");
        assert_eq!(rows[1].trip_id.as_deref(), Some("trip-a"));
        assert_eq!(rows[2].trip_id, None, "written after the trip ended");
    }

    #[test]
    fn a_later_trip_does_not_backfill_earlier_rows() {
        // The offline case this design exists for: rows queued during trip A
        // must still upload as trip A's, even though trip B is what is running
        // when the flush finally happens. Stamping at sync time would give the
        // opposite, and silently reassign the backlog.
        let db = DatabaseManager::new(":memory:").unwrap();
        db.set_encryption_key("");

        db.set_active_trip_id(Some("trip-a".into()));
        db.insert_location(None, 1.0, 1.0, 5.0, 0.0, 0.0, 0.0, false, true, "in_vehicle", -1, None, None, None, None, None).unwrap();
        db.insert_telematics_event("harsh_braking", 0.8, 18.4, 0.47, 1.0, 1.0).unwrap();

        // Trip A ends, hours pass offline, trip B begins — nothing has flushed.
        db.set_active_trip_id(None);
        db.set_active_trip_id(Some("trip-b".into()));
        db.insert_location(None, 9.0, 9.0, 5.0, 0.0, 0.0, 0.0, false, true, "in_vehicle", -1, None, None, None, None, None).unwrap();

        let rows = db.get_locations_batch(None).unwrap();
        assert_eq!(rows[0].trip_id.as_deref(), Some("trip-a"), "backlog was reassigned to the running trip");
        assert_eq!(rows[1].trip_id.as_deref(), Some("trip-b"));

        let events = db.get_telematics_events(10).unwrap();
        assert_eq!(events[0].trip_id.as_deref(), Some("trip-a"));
    }

    #[test]
    fn telematics_event_is_stamped_with_the_active_trip() {
        let db = DatabaseManager::new(":memory:").unwrap();
        db.insert_telematics_event("speeding", 0.4, 30.0, 12.0, 1.0, 2.0).unwrap();
        db.set_active_trip_id(Some("trip-x".into()));
        db.insert_telematics_event("harsh_cornering", 0.6, 12.0, 0.3, 3.0, 4.0).unwrap();

        let events = db.get_telematics_events(10).unwrap();
        assert_eq!(events.len(), 2);
        assert_eq!(events[0].trip_id, None, "recorded outside a trip");
        assert_eq!(events[1].trip_id.as_deref(), Some("trip-x"));
    }

    #[test]
    fn trip_id_survives_encrypted_storage() {
        // trip_id is a plaintext column in both modes — it has to be queryable
        // to correlate, and an opaque random id is not coordinate-level PII.
        let db = DatabaseManager::new(":memory:").unwrap();
        db.set_encryption_key("my_super_secret_encryption_key_!");
        db.set_active_trip_id(Some("trip-enc".into()));
        db.insert_location(None, 40.7, -74.0, 5.0, 0.0, 0.0, 0.0, false, true, "in_vehicle", -1, None, None, None, None, None).unwrap();

        let rows = db.get_locations_batch(None).unwrap();
        assert_eq!(rows[0].trip_id.as_deref(), Some("trip-enc"));
        assert_eq!(rows[0].latitude, 40.7, "encrypted payload still round-trips");
    }

    #[test]
    fn empty_trip_id_is_treated_as_no_trip() {
        // Guards the FFI edge: a native caller passing "" rather than null must
        // not write empty strings that a backend then has to distinguish.
        let db = DatabaseManager::new(":memory:").unwrap();
        db.set_encryption_key("");
        db.set_active_trip_id(Some(String::new()));
        assert_eq!(db.active_trip_id(), None);

        db.insert_location(None, 1.0, 1.0, 5.0, 0.0, 0.0, 0.0, false, false, "still", -1, None, None, None, None, None).unwrap();
        assert_eq!(db.get_locations_batch(None).unwrap()[0].trip_id, None);
    }

    #[test]
    fn rows_written_before_the_migration_read_as_no_trip() {
        // Simulates an upgrade: a row inserted without the column present.
        let db = DatabaseManager::new(":memory:").unwrap();
        db.set_encryption_key("");
        {
            let conn = db.conn.lock().unwrap();
            // The index is built on the column, so it goes first.
            conn.execute("DROP INDEX IF EXISTS idx_location_events_trip_id", []).unwrap();
            conn.execute("ALTER TABLE location_events DROP COLUMN trip_id", []).unwrap();
            conn.execute(
                "INSERT INTO location_events (uuid, timestamp, latitude, longitude, accuracy, speed, heading, altitude, is_mock, is_moving, activity, activity_confidence, timestamp_ms) \
                 VALUES ('legacy', '2026-01-01T00:00:00Z', 1.0, 2.0, 5.0, 0.0, 0.0, 0.0, 0, 0, 'walking', -1, 0)",
                [],
            ).unwrap();
            conn.execute("ALTER TABLE location_events ADD COLUMN trip_id TEXT", []).unwrap();
            conn.execute("CREATE INDEX IF NOT EXISTS idx_location_events_trip_id ON location_events(trip_id)", []).unwrap();
        }

        let rows = db.get_locations_batch(None).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].trip_id, None);
        assert_eq!(rows[0].uuid.as_deref(), Some("legacy"));
    }
}
