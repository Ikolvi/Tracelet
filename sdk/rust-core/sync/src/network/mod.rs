use std::collections::HashMap;
use tracelet_core::error::TraceletError;
use reqwest::{Client, Method, header::{HeaderMap, HeaderName, HeaderValue}};
use serde_json::json;
use std::str::FromStr;
use std::time::Duration;

#[derive(uniffi::Record, Debug, Clone)]
pub struct SyncHttpConfig {
    pub url: Option<String>,
    pub method: i32,
    pub headers: HashMap<String, String>,
    pub batch_sync: bool,
    pub max_batch_size: i32,
    pub auto_sync: bool,
    pub max_retries: i32,
    pub retry_backoff_base: i32,
    pub retry_backoff_cap: i32,
    pub ssl_pinning_certificates: Option<Vec<String>>,
    pub ssl_pinning_fingerprints: Option<Vec<String>>,
    pub http_root_property: Option<String>,
    pub params: Option<HashMap<String, String>>,
    pub extras: Option<HashMap<String, String>>,
    pub disable_auto_sync_on_cellular: bool,
    pub enable_delta_compression: bool,
    pub delta_coordinate_precision: i32,
    pub locations_order_direction: i32,
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct SyncLocationRecord {
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
    /// Motion state of this record (#151).
    pub is_moving: bool,
    pub activity: String,
    /// Trigger that recorded this point: "location", "motionchange",
    /// "heartbeat", "geofence", etc. (#156).
    pub event: String,
    pub route_context: Option<String>,
    /// Reverse-geocoded address as a JSON object string (#212). Mirrors
    /// `DbLocationRecord.address`; emitted into the default payload so the
    /// backend receives it without a custom body builder.
    pub address: Option<String>,
    /// The trip this record was written during (#402), or `None` if none was
    /// active. Carried straight from the row rather than resolved at flush
    /// time, so a queued record uploads with the trip it belongs to.
    pub trip_id: Option<String>,
}

#[derive(uniffi::Object)]
pub struct SyncManager {
    client: Client,
}

#[uniffi::export]
impl SyncManager {
    #[uniffi::constructor]
    pub fn new() -> Self {
        // Explicitly initialize the CryptoProvider to prevent crashes when both
        // aws-lc-rs and ring features might be enabled simultaneously by reqwest/rustls.
        let _ = rustls::crypto::ring::default_provider().install_default();
        
        Self {
            client: Client::builder()
                .timeout(Duration::from_secs(60))
                .build()
                .unwrap_or_else(|_| Client::new()),
        }
    }

    /// Performs a synchronous/blocking sync of a batch of location records.
    /// Returns the number of successfully synced records.
    pub fn sync_batch_blocking(&self, config: SyncHttpConfig, records: Vec<SyncLocationRecord>) -> Result<u32, TraceletError> {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .map_err(|e| TraceletError::Network(e.to_string()))?;
        let res = rt.block_on(self.sync_batch(&config, &records))?;
        Ok(res as u32)
    }
}

use rustls::client::danger::{ServerCertVerified, ServerCertVerifier, HandshakeSignatureValid};
use rustls::pki_types::{ServerName, CertificateDer, UnixTime};
use rustls::{DigitallySignedStruct, Error as RustlsError};
use std::sync::Arc;
use sha2::{Digest, Sha256};

#[derive(Debug)]
struct FingerprintVerifier {
    pinned_fingerprints: Vec<Vec<u8>>,
    default_verifier: Arc<dyn ServerCertVerifier>,
}

impl ServerCertVerifier for FingerprintVerifier {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        intermediates: &[CertificateDer<'_>],
        server_name: &ServerName<'_>,
        ocsp_response: &[u8],
        now: UnixTime,
    ) -> Result<ServerCertVerified, RustlsError> {
        // Run standard chain verification first
        self.default_verifier.verify_server_cert(end_entity, intermediates, server_name, ocsp_response, now)?;

        // Compute SHA-256 fingerprint of the end-entity certificate
        let mut hasher = Sha256::new();
        hasher.update(end_entity.as_ref());
        let hash = hasher.finalize();
        
        let hash_hex = hex::encode(hash.as_slice());

        let pinned_hex: Vec<String> = self.pinned_fingerprints.iter().map(|fp| hex::encode(fp)).collect();

        // Check if computed fingerprint matches any pinned fingerprint
        if self.pinned_fingerprints.iter().any(|fp| fp.as_slice() == hash.as_slice()) {
            Ok(ServerCertVerified::assertion())
        } else {
            tracelet_core::logger::error(&format!("[Rust Core] ❌ SSL Pinning Error: Certificate fingerprint {} did not match any pinned fingerprints: {:?}", hash_hex, pinned_hex));
            Err(RustlsError::General(format!("Server certificate fingerprint mismatch. Expected one of {:?}, got {}", pinned_hex, hash_hex)))
        }
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, RustlsError> {
        self.default_verifier.verify_tls12_signature(message, cert, dss)
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, RustlsError> {
        self.default_verifier.verify_tls13_signature(message, cert, dss)
    }

    fn supported_verify_schemes(&self) -> Vec<rustls::SignatureScheme> {
        self.default_verifier.supported_verify_schemes()
    }
}

impl SyncManager {
    pub(crate) fn build_sync_payload(config: &SyncHttpConfig, records: &[SyncLocationRecord]) -> serde_json::Value {
        let mut payload = if config.batch_sync {
            let json_records: Vec<_> = records.iter().map(|r| {
                let mut base_json = json!({
                    "id": r.id,
                    "uuid": r.uuid,
                    "timestamp": r.timestamp,
                    "coords": {
                        "latitude": r.latitude,
                        "longitude": r.longitude,
                        "accuracy": r.accuracy,
                        "speed": r.speed,
                        "heading": r.heading,
                        "altitude": r.altitude,
                    },
                    "is_mock": r.is_mock,
                    "is_moving": r.is_moving,
                    "activity": r.activity,
                    "event": r.event
                });
                // Reverse-geocoded address (#212): emit as a nested object when it
                // parses as JSON, else as a raw string. Matches the custom-builder
                // schema so default and custom payloads carry address identically.
                if let Some(addr) = r.address.as_ref().filter(|a| !a.is_empty()) {
                    if let Some(obj) = base_json.as_object_mut() {
                        let val = serde_json::from_str(addr)
                            .unwrap_or_else(|_| serde_json::Value::String(addr.clone()));
                        obj.insert("address".to_string(), val);
                    }
                }

                // #402: always present so a consumer can rely on the key, and
                // explicitly null outside a trip rather than absent — the two
                // are different to most JSON parsers. Additive: nothing else
                // moves or is renamed.
                if let Some(obj) = base_json.as_object_mut() {
                    obj.insert(
                        "trip_id".to_string(),
                        r.trip_id.clone().map_or(serde_json::Value::Null, serde_json::Value::String),
                    );
                }

                let record_route_context: Option<serde_json::Value> = r.route_context.as_ref()
                    .and_then(|rc| serde_json::from_str(rc).ok());

                if let Some(ref rc) = record_route_context {
                    if let Some(obj) = base_json.as_object_mut() {
                        if let Some(rc_obj) = rc.as_object() {
                            for (k, v) in rc_obj.iter() {
                                obj.insert(k.clone(), v.clone());
                            }
                        }
                    }
                }
                base_json
            }).collect();
            let mut map = serde_json::Map::new();
            if !json_records.is_empty() {
                let root_key = config.http_root_property.as_deref().unwrap_or("location");
                map.insert(root_key.to_string(), serde_json::Value::Array(json_records));
            }
            serde_json::Value::Object(map)
        } else {
            // For non-batch, just send the latest record
            let mut map = serde_json::Map::new();
            if let Some(r) = records.last() {
                let mut base_json = json!({
                    "id": r.id,
                    "uuid": r.uuid,
                    "timestamp": r.timestamp,
                    "coords": {
                        "latitude": r.latitude,
                        "longitude": r.longitude,
                        "accuracy": r.accuracy,
                        "speed": r.speed,
                        "heading": r.heading,
                        "altitude": r.altitude,
                    },
                    "is_mock": r.is_mock,
                        "is_moving": r.is_moving,
                        "activity": r.activity,
                        "event": r.event
                });
                // Reverse-geocoded address (#212): emit as a nested object when it
                // parses as JSON, else as a raw string. Matches the custom-builder
                // schema so default and custom payloads carry address identically.
                if let Some(addr) = r.address.as_ref().filter(|a| !a.is_empty()) {
                    if let Some(obj) = base_json.as_object_mut() {
                        let val = serde_json::from_str(addr)
                            .unwrap_or_else(|_| serde_json::Value::String(addr.clone()));
                        obj.insert("address".to_string(), val);
                    }
                }

                // #402: always present so a consumer can rely on the key, and
                // explicitly null outside a trip rather than absent — the two
                // are different to most JSON parsers. Additive: nothing else
                // moves or is renamed.
                if let Some(obj) = base_json.as_object_mut() {
                    obj.insert(
                        "trip_id".to_string(),
                        r.trip_id.clone().map_or(serde_json::Value::Null, serde_json::Value::String),
                    );
                }

                let record_route_context: Option<serde_json::Value> = r.route_context.as_ref()
                    .and_then(|rc| serde_json::from_str(rc).ok());

                if let Some(ref rc) = record_route_context {
                    if let Some(obj) = base_json.as_object_mut() {
                        if let Some(rc_obj) = rc.as_object() {
                            for (k, v) in rc_obj.iter() {
                                obj.insert(k.clone(), v.clone());
                            }
                        }
                    }
                }
                let root_key = config.http_root_property.as_deref().unwrap_or("location");
                map.insert(root_key.to_string(), base_json);
            }
            serde_json::Value::Object(map)
        };

        // Attach params and extras to the root of the payload
        if let Some(obj) = payload.as_object_mut() {
            if let Some(params) = &config.params {
                let mut params_obj = serde_json::Map::new();
                for (k, v) in params {
                    let parsed_val = serde_json::from_str(v).unwrap_or_else(|_| serde_json::Value::String(v.clone()));
                    params_obj.insert(k.clone(), parsed_val);
                }
                obj.insert("params".to_string(), serde_json::Value::Object(params_obj));
            }
            if let Some(extras) = &config.extras {
                let mut extras_obj = serde_json::Map::new();
                for (k, v) in extras {
                    if k == "__telematics" {
                        let parsed_val = serde_json::from_str(v).unwrap_or_else(|_| serde_json::Value::String(v.clone()));
                        obj.insert("telematics".to_string(), parsed_val);
                    } else {
                        let parsed_val = serde_json::from_str(v).unwrap_or_else(|_| serde_json::Value::String(v.clone()));
                        extras_obj.insert(k.clone(), parsed_val);
                    }
                }
                if !extras_obj.is_empty() {
                    obj.insert("extras".to_string(), serde_json::Value::Object(extras_obj));
                }
            }
        }
        
        payload
    }

    /// Performs an asynchronous sync of a batch of location records.
    /// Returns the number of successfully synced records.
    pub async fn sync_batch(&self, config: &SyncHttpConfig, records: &[SyncLocationRecord]) -> Result<i32, TraceletError> {
        let url = match &config.url {
            Some(u) if !u.is_empty() => u,
            _ => {
                tracelet_core::logger::warn("[Rust Core] ⚠️ Sync skipped: HTTP sync URL is not configured in EngineConfig.");
                return Err(TraceletError::Config("HTTP sync URL not configured".into()));
            }
        };

        let has_telematics = config.extras.as_ref().map_or(false, |e| e.contains_key("__telematics"));
        if records.is_empty() && !has_telematics {
            tracelet_core::logger::info("[Rust Core] ℹ️ Sync skipped: Location batch is empty and no telematics.");
            return Ok(0);
        }

        tracelet_core::logger::info(&format!("[Rust Core] 🌐 HTTP Sync batch size: {} record(s). Target URL: {}", records.len(), url));

        // Prepare Headers
        let mut header_map = HeaderMap::new();
        header_map.insert("Content-Type", HeaderValue::from_static("application/json"));
        for (k, v) in &config.headers {
            if let (Ok(name), Ok(value)) = (HeaderName::from_str(k), HeaderValue::from_str(v)) {
                header_map.insert(name, value);
            }
        }


        // Prepare Payload
        let payload = Self::build_sync_payload(config, records);

        let method = if config.method == 1 { Method::PUT } else { Method::POST };

        // Handle SSL Pinning dynamically if configured
        let mut active_client = self.client.clone();
        
        let has_certs = config.ssl_pinning_certificates.as_ref().map_or(false, |c| !c.is_empty());
        let has_fingerprints = config.ssl_pinning_fingerprints.as_ref().map_or(false, |f| !f.is_empty());

        if has_certs || has_fingerprints {
            let mut root_cert_store = rustls::RootCertStore::empty();
            let mut custom_certs_added = false;

            if let Some(certs) = &config.ssl_pinning_certificates {
                for cert_str in certs {
                    let mut reader = std::io::Cursor::new(cert_str.as_bytes());
                    let mut parsed = false;
                    for item in rustls_pemfile::certs(&mut reader) {
                        if let Ok(cert) = item {
                            if let Ok(_) = root_cert_store.add(cert) {
                                custom_certs_added = true;
                                parsed = true;
                            }
                        }
                    }
                    if !parsed {
                        // Attempt raw DER fallback
                        if let Ok(_) = root_cert_store.add(rustls::pki_types::CertificateDer::from(cert_str.as_bytes().to_vec())) {
                            custom_certs_added = true;
                        }
                    }
                }
            }
            
            // If no valid custom certs were added (or none were provided), use system/webpki roots
            if !custom_certs_added {
                root_cert_store.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
            }

            let default_verifier = rustls::client::WebPkiServerVerifier::builder(Arc::new(root_cert_store))
                .build()
                .unwrap();

            let verifier: Arc<dyn ServerCertVerifier> = if has_fingerprints {
                let mut decoded_fingerprints = Vec::new();
                if let Some(fps) = &config.ssl_pinning_fingerprints {
                    for fp in fps {
                        // Support both raw hex and hex with colons (e.g. AA:BB:CC)
                        let clean_fp = fp.replace(":", "").to_lowercase();
                        if let Ok(decoded) = hex::decode(&clean_fp) {
                            decoded_fingerprints.push(decoded);
                        }
                    }
                }
                
                Arc::new(FingerprintVerifier {
                    pinned_fingerprints: decoded_fingerprints,
                    default_verifier,
                })
            } else {
                default_verifier
            };

            let rustls_config = rustls::ClientConfig::builder()
                .dangerous()
                .with_custom_certificate_verifier(verifier)
                .with_no_client_auth();

            active_client = Client::builder()
                .timeout(Duration::from_secs(60))
                .use_preconfigured_tls(rustls_config)
                .build()
                .map_err(|e| {
                    tracelet_core::logger::error(&format!("[Rust Core] ❌ Failed to build custom TLS client: {}", e));
                    TraceletError::Network(format!("Failed to build custom TLS client: {}", e))
                })?;
        }

        let max_retries = if config.max_retries < 0 { 0 } else { config.max_retries as u32 };
        let backoff_base = if config.retry_backoff_base <= 0 { 1000 } else { config.retry_backoff_base as u64 };
        let backoff_cap = if config.retry_backoff_cap <= 0 { 10000 } else { config.retry_backoff_cap as u64 };
        
        let mut attempt = 0;
        loop {
            tracelet_core::logger::info(&format!("[Rust Core] 🌐 Sending HTTP {} request... (Attempt {}/{})", method, attempt + 1, max_retries + 1));
            // Execute Request
            let request = active_client.request(method.clone(), url)
                .headers(header_map.clone())
                .json(&payload);

            match request.send().await {
                Ok(response) => {
                    let status = response.status();
                    if status.is_success() {
                        tracelet_core::logger::info(&format!("[Rust Core] ✅ HTTP Sync succeeded! Status: {}, successfully synced {} location(s).", status, records.len()));
                        return Ok(records.len() as i32);
                    } else if status.is_client_error() {
                        // Do not retry 4xx errors
                        tracelet_core::logger::error(&format!("[Rust Core] ❌ HTTP Sync failed with client error (4xx): {}. Aborting sync retries.", status));
                        return Err(TraceletError::Network(format!("HTTP Error: {}", status)));
                    } else {
                        // 5xx errors can be retried
                        tracelet_core::logger::error(&format!("[Rust Core] ⚠️ HTTP Sync received server error (5xx): {}.", status));
                        if attempt >= max_retries {
                            tracelet_core::logger::error("[Rust Core] ❌ Max retries reached. Permanent sync failure.");
                            return Err(TraceletError::Network(format!("HTTP Error: {}", status)));
                        }
                    }
                },
                Err(e) => {
                    tracelet_core::logger::error(&format!("[Rust Core] ⚠️ HTTP Sync connection error occurred: {}", e));
                    if attempt >= max_retries {
                        tracelet_core::logger::error("[Rust Core] ❌ Max retries reached. Permanent sync failure.");
                        return Err(TraceletError::Network(e.to_string()));
                    }
                }
            }
            
            // Calculate exponential backoff
            let multiplier = 2_u64.pow(attempt);
            let delay_ms = std::cmp::min(backoff_base * multiplier, backoff_cap);
            tracelet_core::logger::info(&format!("[Rust Core] 🔄 Retrying HTTP Sync in {}ms...", delay_ms));
            tokio::time::sleep(Duration::from_millis(delay_ms)).await;
            attempt += 1;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;

    fn get_test_record() -> SyncLocationRecord {
        SyncLocationRecord {
            id: 1,
            uuid: Some("test-uuid-1234".to_string()),
            timestamp: "2023-01-01T00:00:00Z".to_string(),
            latitude: 10.0,
            longitude: 20.0,
            accuracy: 5.0,
            speed: 15.0,
            heading: 90.0,
            altitude: 100.0,
            is_mock: false,
            is_moving: true,
            activity: "moving".to_string(),
            event: "location".to_string(),
            trip_id: None,
            route_context: None,
            address: None,
        }
    }

    fn get_test_config(batch_sync: bool) -> SyncHttpConfig {
        SyncHttpConfig {
            url: Some("http://localhost".to_string()),
            method: 0,
            headers: HashMap::new(),
            batch_sync,
            max_batch_size: 10,
            auto_sync: true,
            max_retries: 3,
            retry_backoff_base: 1000,
            retry_backoff_cap: 10000,
            ssl_pinning_certificates: None,
            ssl_pinning_fingerprints: None,
            http_root_property: None,
            params: None,
            extras: None,
            disable_auto_sync_on_cellular: false,
            enable_delta_compression: false,
            delta_coordinate_precision: 5,
            locations_order_direction: 0,
        }
    }

    #[test]
    fn test_build_sync_payload_batch_includes_uuid() {
        let config = get_test_config(true);
        let records = vec![get_test_record()];
        
        let payload = SyncManager::build_sync_payload(&config, &records);
        
        // Assert payload structure for batch
        let locations = payload.get("location").expect("Missing 'location' array in payload")
            .as_array().expect("'location' should be an array");
            
        assert_eq!(locations.len(), 1);
        let first_loc = &locations[0];
        
        // Assert uuid is mapped correctly
        assert_eq!(first_loc.get("uuid").and_then(Value::as_str), Some("test-uuid-1234"));
        assert_eq!(first_loc.get("id").and_then(Value::as_i64), Some(1));
    }

    #[test]
    fn test_build_sync_payload_single_includes_uuid() {
        let config = get_test_config(false);
        let records = vec![get_test_record()];
        
        let payload = SyncManager::build_sync_payload(&config, &records);
        
        // Assert payload structure for non-batch
        let location = payload.get("location").expect("Missing 'location' object in payload");
            
        // Assert uuid is mapped correctly
        assert_eq!(location.get("uuid").and_then(Value::as_str), Some("test-uuid-1234"));
        assert_eq!(location.get("id").and_then(Value::as_i64), Some(1));
    }

    #[test]
    fn test_build_sync_payload_includes_address() {
        // #212: the persisted reverse-geocoded address must appear in the default
        // payload (batch + non-batch), as a nested object when it is JSON.
        let addr = r#"{"city":"Paris","country":"FR"}"#;

        // Batch
        let mut record = get_test_record();
        record.address = Some(addr.to_string());
        let payload = SyncManager::build_sync_payload(&get_test_config(true), &[record]);
        let first = &payload.get("location").unwrap().as_array().unwrap()[0];
        assert_eq!(first.get("address").and_then(|a| a.get("city")).and_then(Value::as_str), Some("Paris"));

        // Non-batch
        let mut record2 = get_test_record();
        record2.address = Some(addr.to_string());
        let payload2 = SyncManager::build_sync_payload(&get_test_config(false), &[record2]);
        let loc = payload2.get("location").unwrap();
        assert_eq!(loc.get("address").and_then(|a| a.get("country")).and_then(Value::as_str), Some("FR"));

        // Absent address => no "address" key (no null pollution).
        let payload3 = SyncManager::build_sync_payload(&get_test_config(true), &[get_test_record()]);
        let first3 = &payload3.get("location").unwrap().as_array().unwrap()[0];
        assert!(first3.get("address").is_none());
    }

    #[test]
    fn test_build_sync_payload_merges_route_context_audit_hash() {
        let config = get_test_config(true);
        let mut record = get_test_record();
        
        // Inject an audit_hash into the route_context (simulating iOS/Android behaviour)
        record.route_context = Some(r#"{"custom":"{app: tracelet-example}","audit_hash":"hash123","audit_chain_index":42}"#.to_string());
        
        let records = vec![record];
        let payload = SyncManager::build_sync_payload(&config, &records);
        
        let locations = payload.get("location").expect("Missing 'location' array in payload")
            .as_array().expect("'location' should be an array");
            
        assert_eq!(locations.len(), 1);
        let first_loc = &locations[0];
        
        // The audit_hash should be merged directly into the location JSON object
        assert_eq!(first_loc.get("audit_hash").and_then(Value::as_str), Some("hash123"), "audit_hash was not merged into the sync payload!");
        assert_eq!(first_loc.get("audit_chain_index").and_then(Value::as_i64), Some(42), "audit_chain_index was not merged into the sync payload!");
        assert_eq!(first_loc.get("custom").and_then(Value::as_str), Some("{app: tracelet-example}"));
    }

    #[test]
    fn test_build_sync_payload_uses_custom_root_property_and_extras() {
        let mut config = get_test_config(true); // uses "events" and extras
        config.http_root_property = Some("events".to_string());
        config.extras = Some(HashMap::from([("custom_meta".to_string(), "123".to_string())]));
        let records = vec![get_test_record()];
        
        let payload = SyncManager::build_sync_payload(&config, &records);
        
        // Assert payload uses custom root "events" instead of "location"
        let locations = payload.get("events").expect("Missing custom root 'events' array in payload")
            .as_array().expect("'events' should be an array");
            
        assert_eq!(locations.len(), 1);
        
        // Assert extras are attached at the root level of the payload as an object
        let extras = payload.get("extras").expect("Missing 'extras' object in payload");
        assert_eq!(extras.get("custom_meta").and_then(serde_json::Value::as_i64), Some(123), "extras were not attached to the payload!");
    }

    #[test]
    fn payload_carries_trip_id_in_both_batch_modes() {
        // #402: present as an explicit null outside a trip, so a consumer can
        // rely on the key existing rather than distinguishing absent from null.
        for batch in [true, false] {
            let payload = SyncManager::build_sync_payload(&get_test_config(batch), &[get_test_record()]);
            let node = payload.get("location").unwrap();
            let record = if batch { &node.as_array().unwrap()[0] } else { node };
            assert_eq!(
                record.get("trip_id"),
                Some(&Value::Null),
                "batch_sync={batch}: trip_id must be present and null outside a trip"
            );
        }
    }

    #[test]
    fn payload_emits_the_trip_the_row_was_written_under() {
        let mut record = get_test_record();
        record.trip_id = Some("9f2c0f1e-4c31-4b2a-9a77-1d0f3b5e7c88".to_string());
        let payload = SyncManager::build_sync_payload(&get_test_config(true), &[record]);
        let first = &payload.get("location").unwrap().as_array().unwrap()[0];
        assert_eq!(
            first.get("trip_id").and_then(Value::as_str),
            Some("9f2c0f1e-4c31-4b2a-9a77-1d0f3b5e7c88")
        );
        // Additive: the pre-existing shape is untouched.
        assert_eq!(first.get("id").and_then(Value::as_i64), Some(1));
        assert_eq!(first.get("event").and_then(Value::as_str), Some("location"));
        assert!(first.get("coords").is_some());
    }
}
