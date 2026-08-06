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

/// Number of consecutive out-of-fence fixes required to confirm an EXIT.
///
/// Hysteresis (the exit buffer) is the *spatial* half of a robust exit test;
/// this is the *temporal* half. A boundary crossing is a sustained state
/// change, so inferring it from a single fix is unsound: consumer GNSS
/// routinely emits an isolated "over-confident" fix — one that lands hundreds
/// of metres away while reporting a tight accuracy the accuracy-aware gate
/// (#274) cannot see through. Such a fix is always transient: the device
/// jumps out and is back inside on the very next fix. Requiring the device to
/// be confidently outside for N *consecutive* fixes absorbs those glitches on
/// every device, while a genuine departure — which stays outside — still fires
/// exactly one EXIT, delayed only by (N-1) fix intervals.
///
/// `2` is the minimal principled value: "do not act on a lone fix; require one
/// corroborating fix." It adds no per-device tuning and no magic distances.
const GEOFENCE_EXIT_CONFIRMATIONS: u32 = 2;

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
    /// Per-fence count of consecutive out-of-fence fixes observed while the
    /// device is still considered inside, pending EXIT confirmation. Reset the
    /// moment the device is back within the fence (a transient glitch) and
    /// cleared on ENTER/removal/clear. See [GEOFENCE_EXIT_CONFIRMATIONS].
    pending_exit_counts: std::sync::RwLock<HashMap<String, u32>>,
    rtree: std::sync::RwLock<Option<RTree<CoreGeofence>>>,
    indexed_geofences: std::sync::RwLock<Option<HashMap<String, CoreGeofence>>>,
}

/// Records one more consecutive out-of-fence observation for `identifier` and
/// returns `true` once [GEOFENCE_EXIT_CONFIRMATIONS] have accumulated — at which
/// point the pending count is cleared so a later re-entry then exit starts
/// fresh. Returns `false` (holding the EXIT) while confirmations are still
/// accruing.
fn confirm_exit(pending: &mut HashMap<String, u32>, identifier: &str) -> bool {
    let count = pending.get(identifier).copied().unwrap_or(0) + 1;
    if count >= GEOFENCE_EXIT_CONFIRMATIONS {
        pending.remove(identifier);
        true
    } else {
        pending.insert(identifier.to_string(), count);
        false
    }
}

#[uniffi::export]
impl GeofenceEvaluator {
    #[uniffi::constructor]
    /// Initializes a new GeofenceEvaluator.
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            inside_geofence_ids: std::sync::RwLock::new(HashSet::new()),
            pending_exit_counts: std::sync::RwLock::new(HashMap::new()),
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

        // #306: drop pending exit confirmations for fences the new index no
        // longer covers. `clear` and `remove_geofence` both prune this map;
        // re-indexing did not, so a half-accumulated count for a since-removed
        // fence survived for the evaluator's lifetime and would have counted
        // toward a later EXIT if that identifier was ever re-indexed.
        self.pending_exit_counts
            .write()
            .unwrap()
            .retain(|id, _| lookup.contains_key(id));

        *self.rtree.write().unwrap() = Some(tree);
        *self.indexed_geofences.write().unwrap() = Some(lookup);
    }

    /// Clears the current spatial index.
    pub fn clear_index(&self) {
        *self.rtree.write().unwrap() = None;
        *self.indexed_geofences.write().unwrap() = None;
    }

    /// Evaluates a location update and returns a list of triggered geofence transitions.
    ///
    /// `accuracy` is the fix's horizontal accuracy radius in meters (a 68%
    /// confidence circle). It is used to make the EXIT decision drift-aware:
    /// a circular geofence only EXITs once the *entire* accuracy circle clears
    /// the fence (`distance - accuracy > radius + exitBuffer`). This prevents a
    /// single high-drift fix — which is reported with a correspondingly large
    /// accuracy value — from producing a false EXIT while the device is
    /// stationary inside the fence (issue #274). Pass `0.0` (or any
    /// non-positive/non-finite value) to disable accuracy gating and preserve
    /// the legacy `distance`-only behavior. ENTER is intentionally left
    /// accuracy-agnostic so arrivals still trigger promptly.
    pub fn evaluate_proximity(&self, latitude: f64, longitude: f64, accuracy: f64, geofences: Vec<CoreGeofence>) -> Vec<GeofenceTransition> {
        // Clamp unknown/invalid accuracy (iOS reports negative when invalid) to
        // 0 so gating is a no-op rather than pulling the exit threshold inward.
        let acc = if accuracy.is_finite() && accuracy > 0.0 { accuracy } else { 0.0 };
        let effective_geofences = self.resolve_geofences(latitude, longitude, geofences);
        let mut transitions = Vec::new();
        let mut inside_ids = self.inside_geofence_ids.write().unwrap();
        let mut pending = self.pending_exit_counts.write().unwrap();

        for gf in effective_geofences {
            let identifier = &gf.identifier;

            // ── Polygon geofence ──────────────────────────────────────────────
            if gf.vertices.len() >= 3 {
                let is_inside = is_point_in_polygon(latitude, longitude, gf.vertices);
                let was_inside = inside_ids.contains(identifier);

                if is_inside && !was_inside {
                    inside_ids.insert(identifier.clone());
                    pending.remove(identifier);
                    transitions.push(GeofenceTransition {
                        identifier: identifier.clone(),
                        action: "ENTER".to_string(),
                    });
                } else if was_inside {
                    if is_inside {
                        // Back inside (or never really left): cancel any pending exit.
                        pending.remove(identifier);
                    } else if confirm_exit(&mut pending, identifier) {
                        inside_ids.remove(identifier);
                        transitions.push(GeofenceTransition {
                            identifier: identifier.clone(),
                            action: "EXIT".to_string(),
                        });
                    }
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
            // Accuracy-aware EXIT (#274): require the whole error circle to be
            // beyond the fence, not just the reported point. `distance - acc`
            // is the nearest the device could plausibly be to the center given
            // the fix uncertainty; only exit when even that is clearly outside.
            let exited = (distance - acc) > gf.radius + exit_buffer;

            if entered && !was_inside {
                inside_ids.insert(identifier.clone());
                pending.remove(identifier);
                transitions.push(GeofenceTransition {
                    identifier: identifier.clone(),
                    action: "ENTER".to_string(),
                });
            } else if was_inside {
                if exited {
                    // Confirmed-exit gate: a lone over-confident fix that lands
                    // outside is a transient glitch, so require the device to be
                    // confidently outside for GEOFENCE_EXIT_CONFIRMATIONS
                    // consecutive fixes before emitting EXIT (see the constant).
                    if confirm_exit(&mut pending, identifier) {
                        inside_ids.remove(identifier);
                        transitions.push(GeofenceTransition {
                            identifier: identifier.clone(),
                            action: "EXIT".to_string(),
                        });
                    }
                } else {
                    // Within `radius + exit_buffer` while inside: still in. Any
                    // in-flight exit excursion was transient — reset its count.
                    pending.remove(identifier);
                }
            }
        }

        transitions
    }

    pub fn clear(&self) {
        self.inside_geofence_ids.write().unwrap().clear();
        self.pending_exit_counts.write().unwrap().clear();
        self.clear_index();
    }

    pub fn remove_geofence(&self, identifier: String) {
        self.inside_geofence_ids.write().unwrap().remove(&identifier);
        self.pending_exit_counts.write().unwrap().remove(&identifier);
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

    /// #306: re-indexing must drop pending exit confirmations for fences the
    /// new index no longer covers, so a stale half-count cannot contribute to a
    /// later EXIT if that identifier comes back.
    #[test]
    fn reindexing_drops_pending_counts_for_absent_fences() {
        let (lat, lng) = (37.4219983, -122.084);
        let gf = circular("gone", lat, lng, 100.0);

        let eval = GeofenceEvaluator::new();
        eval.index_geofences(vec![gf.clone()]);

        // Get inside, then accumulate ONE out-of-fence observation (of the two
        // needed to confirm an EXIT).
        let (ilat, ilng) = point_north(lat, lng, 10.0);
        eval.evaluate_proximity(ilat, ilng, 0.0, vec![gf.clone()]);
        let (olat, olng) = point_north(lat, lng, 400.0);
        let t = eval.evaluate_proximity(olat, olng, 0.0, vec![gf.clone()]);
        assert_eq!(count(&t), (0, 0), "first outside fix must not exit yet");

        // Re-index WITHOUT that fence: its pending count must not survive.
        eval.index_geofences(vec![circular("other", lat, lng, 100.0)]);

        // Re-index the original fence again and take one outside fix. If the
        // stale count had survived, this lone fix would confirm an EXIT.
        eval.index_geofences(vec![gf.clone()]);
        let t = eval.evaluate_proximity(olat, olng, 0.0, vec![gf.clone()]);
        assert_eq!(
            count(&t),
            (0, 0),
            "a stale pending count must not let one fix confirm an EXIT"
        );
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
            let (e, x) = count(&eval.evaluate_proximity(plat, plng, 0.0, vec![gf.clone()]));
            enters += e;
            exits += x;
        }

        assert_eq!(enters, 1, "expected exactly one ENTER, got {enters}");
        assert_eq!(exits, 0, "boundary jitter must not produce any EXIT, got {exits}");
    }

    /// A genuine departure — clearly beyond radius + hysteresis band, and
    /// *sustained* — must produce exactly one EXIT once confirmed.
    #[test]
    fn genuine_exit_beyond_buffer_fires_once() {
        let (lat, lng) = (37.4219983, -122.084);
        let gf = circular("home", lat, lng, 100.0);
        let eval = GeofenceEvaluator::new();

        // Enter well inside.
        let (plat, plng) = point_north(lat, lng, 20.0);
        let (e, _) = count(&eval.evaluate_proximity(plat, plng, 0.0, vec![gf.clone()]));
        assert_eq!(e, 1);

        // Move clearly outside (well past radius + 20 m buffer). The first
        // out-of-fence fix is held pending confirmation, not emitted.
        let (plat, plng) = point_north(lat, lng, 400.0);
        let (_, x) = count(&eval.evaluate_proximity(plat, plng, 0.0, vec![gf.clone()]));
        assert_eq!(x, 0, "a lone out-of-fence fix must be held pending confirmation");

        // Still outside on the next fix → confirmed departure → exactly one EXIT.
        let (_, x) = count(&eval.evaluate_proximity(plat, plng, 0.0, vec![gf.clone()]));
        assert_eq!(x, 1, "a sustained departure must fire exactly one EXIT");
    }

    /// Regression for the over-confident-drift pattern (vivo/Samsung field logs):
    /// a stationary device inside the fence gets a single fix that lands far
    /// outside while *reporting a tight accuracy* — the accuracy gate (#274)
    /// cannot see through it. It must be absorbed as the transient glitch it is
    /// (the device is back inside on the next fix), producing no EXIT.
    #[test]
    fn single_overconfident_fix_is_absorbed() {
        let (lat, lng) = (10.787929, 76.684183);
        let gf = circular("office", lat, lng, 50.0); // exit threshold = 70 m
        let eval = GeofenceEvaluator::new();

        // Inside.
        let (plat, plng) = point_north(lat, lng, 10.0);
        let (e, x) = count(&eval.evaluate_proximity(plat, plng, 5.0, vec![gf.clone()]));
        assert_eq!((e, x), (1, 0));

        // Over-confident glitch: 200 m out at 1.7 m accuracy (200 - 1.7 = 198 >
        // 70, so it passes the accuracy gate) — but it is a lone fix.
        let (plat, plng) = point_north(lat, lng, 200.0);
        let (_, x) = count(&eval.evaluate_proximity(plat, plng, 1.7, vec![gf.clone()]));
        assert_eq!(x, 0, "a lone over-confident out-of-fence fix must not EXIT");

        // Back inside on the very next fix → no EXIT, no re-ENTER.
        let (plat, plng) = point_north(lat, lng, 9.0);
        let (e, x) = count(&eval.evaluate_proximity(plat, plng, 5.0, vec![gf.clone()]));
        assert_eq!((e, x), (0, 0), "the glitch must leave no trace");
    }

    /// The confirmation counter resets the moment the device is back inside, so
    /// a device that repeatedly glitches out and returns never EXITs.
    #[test]
    fn exit_confirmation_resets_on_return() {
        let (lat, lng) = (10.787929, 76.684183);
        let gf = circular("office", lat, lng, 50.0);
        let eval = GeofenceEvaluator::new();

        let (plat, plng) = point_north(lat, lng, 10.0);
        let _ = eval.evaluate_proximity(plat, plng, 5.0, vec![gf.clone()]);

        // out, in, out, in, out — each excursion is a single fix.
        let seq = [200.0, 10.0, 220.0, 12.0, 210.0];
        let mut exits = 0usize;
        for d in seq {
            let (plat, plng) = point_north(lat, lng, d);
            let (_, x) = count(&eval.evaluate_proximity(plat, plng, 1.7, vec![gf.clone()]));
            exits += x;
        }
        assert_eq!(exits, 0, "alternating out/in glitches must never confirm an EXIT");
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
            let (e, x) = count(&eval.evaluate_proximity(plat, plng, 0.0, vec![gf.clone()]));
            enters += e;
            exits += x;
        }
        assert_eq!(enters, 1);
        assert_eq!(exits, 0);
    }

    /// Regression for #274: a stationary device inside a small fence whose GPS
    /// briefly drifts well past `radius + buffer` must NOT fire a false EXIT
    /// when the fix carries a correspondingly large accuracy value.
    #[test]
    fn high_accuracy_drift_does_not_false_exit() {
        let (lat, lng) = (37.4219983, -122.084);
        let gf = circular("attendance", lat, lng, 50.0); // exit threshold = 70 m
        let eval = GeofenceEvaluator::new();

        // Solid fix inside with good accuracy → ENTER.
        let (plat, plng) = point_north(lat, lng, 10.0);
        let (e, x) = count(&eval.evaluate_proximity(plat, plng, 8.0, vec![gf.clone()]));
        assert_eq!((e, x), (1, 0), "good-accuracy fix inside must ENTER once");

        // Drift spike: reported 160 m out but with ±150 m accuracy. The nearest
        // plausible position (160 - 150 = 10 m) is still inside → hold, no EXIT.
        let (plat, plng) = point_north(lat, lng, 160.0);
        let (_, x) = count(&eval.evaluate_proximity(plat, plng, 150.0, vec![gf.clone()]));
        assert_eq!(x, 0, "high-drift low-confidence fix must not fire EXIT");

        // Recovered accurate fix back inside → still no spurious transitions.
        let (plat, plng) = point_north(lat, lng, 12.0);
        let (e, x) = count(&eval.evaluate_proximity(plat, plng, 6.0, vec![gf.clone()]));
        assert_eq!((e, x), (0, 0), "recovery must not re-ENTER or EXIT");
    }

    /// A genuine departure reported with good accuracy must still EXIT even
    /// though accuracy gating is active — gating only holds when the error
    /// circle overlaps the fence.
    #[test]
    fn accurate_departure_still_exits_with_gating() {
        let (lat, lng) = (37.4219983, -122.084);
        let gf = circular("attendance", lat, lng, 50.0); // exit threshold = 70 m
        let eval = GeofenceEvaluator::new();

        let (plat, plng) = point_north(lat, lng, 10.0);
        let _ = eval.evaluate_proximity(plat, plng, 8.0, vec![gf.clone()]);

        // 120 m out with ±10 m accuracy: 120 - 10 = 110 > 70. Sustained across
        // two consecutive fixes → real EXIT (the first is held for confirmation).
        let (plat, plng) = point_north(lat, lng, 120.0);
        let (_, x) = count(&eval.evaluate_proximity(plat, plng, 10.0, vec![gf.clone()]));
        assert_eq!(x, 0, "first out-of-fence fix is held pending confirmation");
        let (_, x) = count(&eval.evaluate_proximity(plat, plng, 10.0, vec![gf.clone()]));
        assert_eq!(x, 1, "an accurate, sustained departure must still EXIT");
    }
}
