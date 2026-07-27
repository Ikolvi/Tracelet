use std::collections::{HashSet, HashMap};
use std::sync::Arc;
use crate::algorithms::geo_utils::{haversine, is_point_in_polygon, Coordinate};
use crate::spatial::rtree::RTree;

/// Fraction of the geofence radius used as an exit-hysteresis band.
///
/// A device is considered to have ENTERed at the true `radius`, but is only
/// considered to have EXITed once it is farther than `radius * (1 + FRACTION)`
/// from the center. This asymmetric threshold prevents ENTER/EXIT "flapping"
/// (dithering) when a stationary device's GPS fixes jitter across the boundary
/// (issue #268).
const GEOFENCE_EXIT_HYSTERESIS_FRACTION: f64 = 0.1;

/// Minimum exit-hysteresis band in meters.
///
/// For small-radius geofences `radius * FRACTION` is smaller than typical GPS
/// noise, so a floor is applied to keep the buffer meaningful (e.g. a 50 m
/// geofence still gets a 20 m band rather than 5 m).
const GEOFENCE_MIN_EXIT_HYSTERESIS_METERS: f64 = 20.0;

#[derive(uniffi::Record, Clone, Debug)]
/// Defines a geofence with a spatial polygon or circular radius for evaluation.
pub struct CoreGeofence {
    pub identifier: String,
    pub latitude: f64,
    pub longitude: f64,
    pub radius: f64,
    pub vertices: Vec<Coordinate>,
    pub extras: Option<String>,
}

#[derive(uniffi::Record, Clone, Debug)]
/// Represents a crossing event when a user enters or exits a geofence.
pub struct GeofenceTransition {
    pub identifier: String,
    pub action: String,
}

#[derive(uniffi::Object)]
/// Evaluates location updates against active geofences to detect boundary crossings.
pub struct GeofenceEvaluator {
    inside_geofence_ids: std::sync::RwLock<HashSet<String>>,
    rtree: std::sync::RwLock<Option<RTree<CoreGeofence>>>,
    indexed_geofences: std::sync::RwLock<Option<HashMap<String, CoreGeofence>>>,
}

#[uniffi::export]
impl GeofenceEvaluator {
    #[uniffi::constructor]
    /// Initializes a new GeofenceEvaluator.
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            inside_geofence_ids: std::sync::RwLock::new(HashSet::new()),
            rtree: std::sync::RwLock::new(None),
            indexed_geofences: std::sync::RwLock::new(None),
        })
    }

    /// Indexes a collection of geofences for efficient spatial querying.
    pub fn index_geofences(&self, geofences: Vec<CoreGeofence>) {
        let mut tree = RTree::new(8);
        let mut lookup = HashMap::new();

        for gf in geofences {
            let id = gf.identifier.clone();
            tree.insert(gf.latitude, gf.longitude, gf.radius, gf.clone());
            lookup.insert(id, gf);
        }

        *self.rtree.write().unwrap() = Some(tree);
        *self.indexed_geofences.write().unwrap() = Some(lookup);
    }

    /// Clears the current spatial index.
    pub fn clear_index(&self) {
        *self.rtree.write().unwrap() = None;
        *self.indexed_geofences.write().unwrap() = None;
    }

    /// Evaluates a location update and returns a list of triggered geofence transitions.
    pub fn evaluate_proximity(&self, latitude: f64, longitude: f64, geofences: Vec<CoreGeofence>) -> Vec<GeofenceTransition> {
        let effective_geofences = self.resolve_geofences(latitude, longitude, geofences);
        let mut transitions = Vec::new();
        let mut inside_ids = self.inside_geofence_ids.write().unwrap();

        for gf in effective_geofences {
            let identifier = &gf.identifier;

            // ── Polygon geofence ──────────────────────────────────────────────
            if gf.vertices.len() >= 3 {
                let is_inside = is_point_in_polygon(latitude, longitude, gf.vertices);
                let was_inside = inside_ids.contains(identifier);

                if is_inside && !was_inside {
                    inside_ids.insert(identifier.clone());
                    transitions.push(GeofenceTransition {
                        identifier: identifier.clone(),
                        action: "ENTER".to_string(),
                    });
                } else if !is_inside && was_inside {
                    inside_ids.remove(identifier);
                    transitions.push(GeofenceTransition {
                        identifier: identifier.clone(),
                        action: "EXIT".to_string(),
                    });
                }
                continue; // Skip circular check
            }

            // ── Circular geofence ─────────────────────────────────────────────
            if gf.radius <= 0.0 {
                continue;
            }

            let distance = haversine(latitude, longitude, gf.latitude, gf.longitude);
            let was_inside = inside_ids.contains(identifier);

            // Exit hysteresis: ENTER at the true radius, but only EXIT once the
            // device is clearly beyond it (radius + buffer). Without this, a
            // stationary device whose fixes jitter across the boundary produces
            // repeated ENTER/EXIT events (issue #268).
            let exit_buffer = (gf.radius * GEOFENCE_EXIT_HYSTERESIS_FRACTION)
                .max(GEOFENCE_MIN_EXIT_HYSTERESIS_METERS);
            let entered = distance <= gf.radius;
            let exited = distance > gf.radius + exit_buffer;

            if entered && !was_inside {
                inside_ids.insert(identifier.clone());
                transitions.push(GeofenceTransition {
                    identifier: identifier.clone(),
                    action: "ENTER".to_string(),
                });
            } else if exited && was_inside {
                inside_ids.remove(identifier);
                transitions.push(GeofenceTransition {
                    identifier: identifier.clone(),
                    action: "EXIT".to_string(),
                });
            }
            // Between `radius` and `radius + exit_buffer` while already inside:
            // hold the current state (no transition) to absorb boundary jitter.
        }

        transitions
    }

    pub fn clear(&self) {
        self.inside_geofence_ids.write().unwrap().clear();
        self.clear_index();
    }

    pub fn remove_geofence(&self, identifier: String) {
        self.inside_geofence_ids.write().unwrap().remove(&identifier);
    }
}

impl GeofenceEvaluator {
    fn resolve_geofences(&self, lat: f64, lng: f64, all_geofences: Vec<CoreGeofence>) -> Vec<CoreGeofence> {
        let rtree_guard = self.rtree.read().unwrap();
        let lookup_guard = self.indexed_geofences.read().unwrap();

        if rtree_guard.is_none() || lookup_guard.is_none() {
            return all_geofences;
        }

        let tree = rtree_guard.as_ref().unwrap();
        let lookup = lookup_guard.as_ref().unwrap();

        let search_radius = 50000.0; // 50 km
        let nearby = tree.query_circle(lat, lng, search_radius);

        let inside_ids = self.inside_geofence_ids.read().unwrap();
        if inside_ids.is_empty() {
            return nearby.into_iter().cloned().collect();
        }

        let mut seen = HashSet::new();
        let mut merged = Vec::new();

        for gf in nearby {
            seen.insert(gf.identifier.clone());
            merged.push(gf.clone());
        }

        for id in inside_ids.iter() {
            if !seen.contains(id) {
                if let Some(gf) = lookup.get(id) {
                    merged.push(gf.clone());
                }
            }
        }

        merged
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn circular(identifier: &str, lat: f64, lng: f64, radius: f64) -> CoreGeofence {
        CoreGeofence {
            identifier: identifier.to_string(),
            latitude: lat,
            longitude: lng,
            radius,
            vertices: Vec::new(),
            extras: None,
        }
    }

    /// Approximate a point `dist_m` meters due north of the given center.
    /// 1 degree of latitude ≈ 111_320 m, so this yields ~`dist_m` haversine
    /// distance from the center — enough to script boundary crossings.
    fn point_north(center_lat: f64, center_lng: f64, dist_m: f64) -> (f64, f64) {
        (center_lat + dist_m / 111_320.0, center_lng)
    }

    fn count(transitions: &[GeofenceTransition]) -> (usize, usize) {
        let enters = transitions.iter().filter(|t| t.action == "ENTER").count();
        let exits = transitions.iter().filter(|t| t.action == "EXIT").count();
        (enters, exits)
    }

    /// Regression for #268: a stationary device near the edge whose fixes
    /// jitter across the boundary must NOT flap. With exit hysteresis it enters
    /// once and holds inside despite fixes just outside the radius.
    #[test]
    fn stationary_jitter_does_not_flap() {
        let (lat, lng) = (37.4219983, -122.084);
        let gf = circular("flap", lat, lng, 100.0);

        // Distances (m): initial solid fix inside, then jitter straddling the
        // 100 m boundary but staying within radius + buffer (120 m).
        let distances = [40.0, 96.0, 104.0, 95.0, 106.0, 97.0, 103.0];

        let eval = GeofenceEvaluator::new();
        let (mut enters, mut exits) = (0usize, 0usize);
        for d in distances {
            let (plat, plng) = point_north(lat, lng, d);
            let (e, x) = count(&eval.evaluate_proximity(plat, plng, vec![gf.clone()]));
            enters += e;
            exits += x;
        }

        assert_eq!(enters, 1, "expected exactly one ENTER, got {enters}");
        assert_eq!(exits, 0, "boundary jitter must not produce any EXIT, got {exits}");
    }

    /// A genuine departure — clearly beyond radius + hysteresis band — must
    /// still produce exactly one EXIT.
    #[test]
    fn genuine_exit_beyond_buffer_fires_once() {
        let (lat, lng) = (37.4219983, -122.084);
        let gf = circular("home", lat, lng, 100.0);
        let eval = GeofenceEvaluator::new();

        // Enter well inside.
        let (plat, plng) = point_north(lat, lng, 20.0);
        let (e, _) = count(&eval.evaluate_proximity(plat, plng, vec![gf.clone()]));
        assert_eq!(e, 1);

        // Move clearly outside (well past radius + 20 m buffer).
        let (plat, plng) = point_north(lat, lng, 400.0);
        let (_, x) = count(&eval.evaluate_proximity(plat, plng, vec![gf.clone()]));
        assert_eq!(x, 1, "a clear departure must fire exactly one EXIT");
    }

    /// Small-radius geofences use the meter floor for their hysteresis band, so
    /// they too resist flapping from typical GPS noise.
    #[test]
    fn small_radius_uses_meter_floor() {
        let (lat, lng) = (37.4219983, -122.084);
        let gf = circular("small", lat, lng, 50.0); // radius*0.1 = 5m < 20m floor
        let eval = GeofenceEvaluator::new();

        // Enter, then jitter to 60 m (outside 50 m radius but inside 50+20=70 m).
        let distances = [30.0, 55.0, 60.0, 52.0, 65.0];
        let (mut enters, mut exits) = (0usize, 0usize);
        for d in distances {
            let (plat, plng) = point_north(lat, lng, d);
            let (e, x) = count(&eval.evaluate_proximity(plat, plng, vec![gf.clone()]));
            enters += e;
            exits += x;
        }
        assert_eq!(enters, 1);
        assert_eq!(exits, 0);
    }
}
