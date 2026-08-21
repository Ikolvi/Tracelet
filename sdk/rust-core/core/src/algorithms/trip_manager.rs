use crate::algorithms::geo_utils::haversine;
use rand::RngCore;
use std::collections::VecDeque;
use std::sync::Mutex;

const MAX_WAYPOINTS: usize = 5000;

/// Generates a RFC 4122 version 4 UUID from the `rand` crate already in the
/// dependency tree (#402).
///
/// Deliberately not a new dependency: the only consumer is the trip id, and
/// `tracelet_web` already hand-rolls v4 the same way. The value is opaque —
/// nothing parses it and nothing orders by it, so the only property that has
/// to hold is that two trips never collide, which 122 random bits give us.
pub(crate) fn generate_uuid_v4() -> String {
    let mut bytes = [0u8; 16];
    rand::thread_rng().fill_bytes(&mut bytes);
    // Version 4 in the high nibble of byte 6, RFC 4122 variant in byte 8.
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    let h = |b: &[u8]| b.iter().map(|x| format!("{:02x}", x)).collect::<String>();
    format!(
        "{}-{}-{}-{}-{}",
        h(&bytes[0..4]),
        h(&bytes[4..6]),
        h(&bytes[6..8]),
        h(&bytes[8..10]),
        h(&bytes[10..16])
    )
}

/// A geographical point recorded as part of a trip's path.
#[derive(Clone, Debug, uniffi::Record)]
pub struct TripWaypoint {
    pub latitude: f64,
    pub longitude: f64,
    pub timestamp_ms: i64,
}

/// Represents the start or end geographical location of a trip.
#[derive(Clone, Debug, uniffi::Record)]
pub struct TripLocation {
    pub latitude: f64,
    pub longitude: f64,
}

/// Summarized data for a tracked trip, including distance, duration, and path.
#[derive(Clone, Debug, uniffi::Record)]
pub struct TripData {
    /// The UUIDv4 minted when this trip started (#402). The same value was
    /// stamped on every location and driving event written while it ran, so it
    /// is the join key between this summary and those rows.
    pub trip_id: String,
    pub distance_meters: f64,
    pub duration_seconds: f64,
    /// Absolute trip bounds (#402). `duration_seconds` alone cannot place a
    /// trip on a timeline, so a consumer could not window a query against it.
    pub started_at_ms: i64,
    pub ended_at_ms: i64,
    pub start_location: Option<TripLocation>,
    pub stop_location: Option<TripLocation>,
    pub waypoints: Vec<TripWaypoint>,
}

/// The moment a trip begins (#402).
///
/// Previously unobservable: `on_motion_state_changed` returned data only at
/// trip *end*, so nothing outside the state machine could tell that a trip had
/// started, and an application wanting a trip identity had to re-derive the
/// boundary from raw motion changes.
#[derive(Clone, Debug, uniffi::Record)]
pub struct TripStart {
    pub trip_id: String,
    pub started_at_ms: i64,
    pub start_location: Option<TripLocation>,
}

/// A trip boundary crossed by a motion state change (#402).
#[derive(Clone, Debug, uniffi::Enum)]
pub enum TripTransition {
    Started { start: TripStart },
    Ended { data: TripData },
}

struct TripManagerState {
    is_trip_active: bool,
    /// The active trip's id, `None` between trips. Cleared at trip end and
    /// never restored, so a trip id is used by exactly one journey (#402).
    trip_id: Option<String>,
    start_lat: Option<f64>,
    start_lng: Option<f64>,
    start_time_ms: i64,
    total_distance: f64,
    last_waypoint_lat: Option<f64>,
    last_waypoint_lng: Option<f64>,
    waypoints: VecDeque<TripWaypoint>,
}

/// Core logic for determining trip boundaries (start/stop) based on location and motion changes.
#[derive(uniffi::Object)]
pub struct TripManager {
    state: Mutex<TripManagerState>,
}

#[uniffi::export]
impl TripManager {
    /// Initializes a new TripManager state machine.
    #[uniffi::constructor]
    pub fn new() -> Self {
        Self {
            state: Mutex::new(TripManagerState {
                is_trip_active: false,
                trip_id: None,
                start_lat: None,
                start_lng: None,
                start_time_ms: 0,
                total_distance: 0.0,
                last_waypoint_lat: None,
                last_waypoint_lng: None,
                waypoints: VecDeque::new(),
            }),
        }
    }

    /// Returns true if a trip is currently being tracked.
    pub fn is_trip_active(&self) -> bool {
        let state = self.state.lock().unwrap();
        state.is_trip_active
    }

    /// The active trip's id, or `None` when no trip is running (#402).
    ///
    /// Readable at any time, including from a headless process, which is what
    /// lets an insert stamp the id it was written under rather than having it
    /// back-filled at sync time.
    pub fn current_trip_id(&self) -> Option<String> {
        let state = self.state.lock().unwrap();
        state.trip_id.clone()
    }

    /// Evaluates a motion state transition and reports the trip boundary it
    /// crossed, if any.
    ///
    /// Returns `Started` when a trip begins — carrying the freshly minted
    /// `trip_id` — and `Ended` with the accumulated `TripData` when it
    /// finishes. Before #402 a trip start produced no value at all, so callers
    /// could only observe a trip once it was over.
    pub fn on_motion_state_changed(
        &self,
        is_moving: bool,
        latitude: Option<f64>,
        longitude: Option<f64>,
        timestamp_ms: i64,
        now_ms: i64,
    ) -> Option<TripTransition> {
        let mut state = self.state.lock().unwrap();
        if is_moving && !state.is_trip_active {
            let start = Self::start_trip(&mut state, latitude, longitude, timestamp_ms, now_ms);
            Some(TripTransition::Started { start })
        } else if !is_moving && state.is_trip_active {
            let data = Self::end_trip(&mut state, latitude, longitude, timestamp_ms, now_ms);
            Some(TripTransition::Ended { data })
        } else {
            None
        }
    }

    /// Feeds a new location sample into the active trip to update its path and distance.
    pub fn on_location_received(
        &self,
        latitude: f64,
        longitude: f64,
        timestamp_ms: i64,
    ) {
        let mut state = self.state.lock().unwrap();
        if !state.is_trip_active {
            return;
        }

        if let (Some(prev_lat), Some(prev_lng)) = (state.last_waypoint_lat, state.last_waypoint_lng) {
            state.total_distance += haversine(prev_lat, prev_lng, latitude, longitude);
        }
        
        state.last_waypoint_lat = Some(latitude);
        state.last_waypoint_lng = Some(longitude);

        if state.waypoints.len() >= MAX_WAYPOINTS {
            state.waypoints.pop_front();
        }
        state.waypoints.push_back(TripWaypoint {
            latitude,
            longitude,
            timestamp_ms,
        });
    }

    /// Resets the trip manager, discarding any active trip and path data.
    pub fn reset(&self) {
        let mut state = self.state.lock().unwrap();
        state.is_trip_active = false;
        state.trip_id = None;
        state.start_lat = None;
        state.start_lng = None;
        state.last_waypoint_lat = None;
        state.last_waypoint_lng = None;
        state.start_time_ms = 0;
        state.total_distance = 0.0;
        state.waypoints.clear();
    }
}

impl TripManager {
    fn start_trip(
        state: &mut TripManagerState,
        lat: Option<f64>,
        lng: Option<f64>,
        timestamp_ms: i64,
        now_ms: i64,
    ) -> TripStart {
        state.is_trip_active = true;
        state.trip_id = Some(generate_uuid_v4());
        state.start_lat = lat;
        state.start_lng = lng;
        state.last_waypoint_lat = lat;
        state.last_waypoint_lng = lng;
        state.start_time_ms = now_ms;
        state.total_distance = 0.0;
        state.waypoints.clear();

        if let (Some(l), Some(g)) = (lat, lng) {
            state.waypoints.push_back(TripWaypoint {
                latitude: l,
                longitude: g,
                timestamp_ms,
            });
        }

        TripStart {
            // Set immediately above, so the expect is unreachable.
            trip_id: state.trip_id.clone().expect("trip id is minted at trip start"),
            started_at_ms: now_ms,
            start_location: match (lat, lng) {
                (Some(l), Some(g)) => Some(TripLocation { latitude: l, longitude: g }),
                _ => None,
            },
        }
    }

    fn end_trip(
        state: &mut TripManagerState,
        lat: Option<f64>,
        lng: Option<f64>,
        timestamp_ms: i64,
        now_ms: i64,
    ) -> TripData {
        state.is_trip_active = false;

        if let (Some(l), Some(g), Some(prev_lat), Some(prev_lng)) = (lat, lng, state.last_waypoint_lat, state.last_waypoint_lng) {
            state.total_distance += haversine(prev_lat, prev_lng, l, g);
            
            if state.waypoints.len() >= MAX_WAYPOINTS {
                state.waypoints.pop_front();
            }
            state.waypoints.push_back(TripWaypoint {
                latitude: l,
                longitude: g,
                timestamp_ms,
            });
        }

        let duration_ms = now_ms - state.start_time_ms;
        let duration_seconds = (duration_ms as f64) / 1000.0;

        let start_location = match (state.start_lat, state.start_lng) {
            (Some(l), Some(g)) => Some(TripLocation { latitude: l, longitude: g }),
            _ => None,
        };

        let stop_location = match (lat, lng) {
            (Some(l), Some(g)) => Some(TripLocation { latitude: l, longitude: g }),
            _ => None,
        };

        let trip_data = TripData {
            // A trip that somehow ran without an id (a manager mutated before
            // #402's minting path, or a restored state) still produces a
            // summary rather than panicking; it just cannot be correlated.
            trip_id: state.trip_id.clone().unwrap_or_default(),
            distance_meters: state.total_distance,
            duration_seconds,
            started_at_ms: state.start_time_ms,
            ended_at_ms: now_ms,
            start_location,
            stop_location,
            waypoints: state.waypoints.iter().cloned().collect(),
        };

        // Discarded, never restored: the next trip mints its own, so an id is
        // never handed to a second journey (#402).
        state.trip_id = None;
        state.start_lat = None;
        state.start_lng = None;
        state.last_waypoint_lat = None;
        state.last_waypoint_lng = None;
        state.start_time_ms = 0;
        state.total_distance = 0.0;
        state.waypoints.clear();

        trip_data
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    /// Drives a full trip and returns the transition each edge produced.
    fn run_trip(tm: &TripManager, start_ms: i64, end_ms: i64) -> (TripStart, TripData) {
        let started = tm
            .on_motion_state_changed(true, Some(1.0), Some(2.0), start_ms, start_ms)
            .expect("moving from stationary starts a trip");
        let ended = tm
            .on_motion_state_changed(false, Some(1.1), Some(2.1), end_ms, end_ms)
            .expect("stopping ends the active trip");
        match (started, ended) {
            (TripTransition::Started { start }, TripTransition::Ended { data }) => (start, data),
            _ => panic!("expected a Started edge followed by an Ended edge"),
        }
    }

    #[test]
    fn generated_id_is_a_v4_uuid() {
        let id = generate_uuid_v4();
        assert_eq!(id.len(), 36, "canonical form is 8-4-4-4-12: {id}");
        let groups: Vec<&str> = id.split('-').collect();
        assert_eq!(groups.iter().map(|g| g.len()).collect::<Vec<_>>(), vec![8, 4, 4, 4, 12]);
        assert!(id.chars().all(|c| c == '-' || c.is_ascii_hexdigit()), "non-hex in {id}");
        // Version nibble and RFC 4122 variant, the two bits that make it a v4.
        assert_eq!(groups[2].chars().next().unwrap(), '4', "version nibble in {id}");
        assert!(
            matches!(groups[3].chars().next().unwrap(), '8' | '9' | 'a' | 'b'),
            "variant nibble in {id}"
        );
    }

    #[test]
    fn generated_ids_do_not_collide() {
        let ids: HashSet<String> = (0..10_000).map(|_| generate_uuid_v4()).collect();
        assert_eq!(ids.len(), 10_000, "duplicate id in 10k draws");
    }

    #[test]
    fn trip_id_is_minted_at_start_and_stable_for_the_trip() {
        let tm = TripManager::new();
        assert_eq!(tm.current_trip_id(), None, "no trip id before the first trip");

        let started = tm.on_motion_state_changed(true, Some(1.0), Some(2.0), 1_000, 1_000);
        let start = match started {
            Some(TripTransition::Started { start }) => start,
            other => panic!("expected Started, got {other:?}"),
        };

        assert_eq!(tm.current_trip_id().as_deref(), Some(start.trip_id.as_str()));
        assert_eq!(start.started_at_ms, 1_000);

        // Nothing during the trip may rotate it.
        tm.on_location_received(1.5, 2.5, 2_000);
        tm.on_location_received(1.6, 2.6, 3_000);
        assert_eq!(
            tm.current_trip_id().as_deref(),
            Some(start.trip_id.as_str()),
            "trip id changed mid-trip"
        );
    }

    #[test]
    fn trip_summary_carries_the_id_minted_at_start() {
        let tm = TripManager::new();
        let (start, data) = run_trip(&tm, 1_000, 61_000);
        assert_eq!(
            data.trip_id, start.trip_id,
            "the summary must be joinable to the rows written during the trip"
        );
    }

    #[test]
    fn trip_id_is_cleared_at_end_and_never_reused() {
        let tm = TripManager::new();
        let (first_start, first_data) = run_trip(&tm, 1_000, 2_000);
        assert_eq!(tm.current_trip_id(), None, "id must not survive trip end");

        let (second_start, second_data) = run_trip(&tm, 3_000, 4_000);
        assert_ne!(
            first_start.trip_id, second_start.trip_id,
            "a second journey was handed the first journey's id"
        );
        assert_ne!(first_data.trip_id, second_data.trip_id);
    }

    #[test]
    fn trip_carries_absolute_bounds_not_just_duration() {
        // #402: `duration_seconds` alone cannot place a trip on a timeline.
        let tm = TripManager::new();
        let (_, data) = run_trip(&tm, 10_000, 130_000);
        assert_eq!(data.started_at_ms, 10_000);
        assert_eq!(data.ended_at_ms, 130_000);
        assert_eq!(data.duration_seconds, 120.0);
        assert_eq!(
            data.ended_at_ms - data.started_at_ms,
            (data.duration_seconds * 1000.0) as i64,
            "bounds and duration must agree"
        );
    }

    #[test]
    fn motion_change_without_a_boundary_reports_nothing() {
        let tm = TripManager::new();
        assert!(
            tm.on_motion_state_changed(false, Some(1.0), Some(2.0), 1_000, 1_000).is_none(),
            "stopping while already stopped is not a boundary"
        );
        tm.on_motion_state_changed(true, Some(1.0), Some(2.0), 2_000, 2_000);
        assert!(
            tm.on_motion_state_changed(true, Some(1.0), Some(2.0), 3_000, 3_000).is_none(),
            "moving while already moving is not a boundary"
        );
    }

    #[test]
    fn reset_discards_the_active_trip_id() {
        let tm = TripManager::new();
        tm.on_motion_state_changed(true, Some(1.0), Some(2.0), 1_000, 1_000);
        assert!(tm.current_trip_id().is_some());

        tm.reset();
        assert_eq!(tm.current_trip_id(), None, "reset must not leave a stale trip id");
        assert!(!tm.is_trip_active());

        // And the trip after a reset is a genuinely new one.
        let started = tm.on_motion_state_changed(true, Some(1.0), Some(2.0), 5_000, 5_000);
        assert!(matches!(started, Some(TripTransition::Started { .. })));
    }
}
