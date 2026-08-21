use crate::algorithms::trip_manager::{TripManager as NativeTripManager, TripData as NativeTripData, TripLocation as NativeLocation, TripStart as NativeTripStart, TripTransition as NativeTripTransition, TripWaypoint as NativeWaypoint};

/// Represents a single waypoint along a tracked trip.
pub struct TripWaypointDart {
    pub latitude: f64,
    pub longitude: f64,
    pub timestamp_ms: i64,
}

impl From<NativeWaypoint> for TripWaypointDart {
    fn from(wp: NativeWaypoint) -> Self {
        Self {
            latitude: wp.latitude,
            longitude: wp.longitude,
            timestamp_ms: wp.timestamp_ms,
        }
    }
}

/// Represents a geographical location (start or stop) of a trip.
pub struct TripLocationDart {
    pub latitude: f64,
    pub longitude: f64,
}

impl From<NativeLocation> for TripLocationDart {
    fn from(loc: NativeLocation) -> Self {
        Self {
            latitude: loc.latitude,
            longitude: loc.longitude,
        }
    }
}

/// Contains the comprehensive data for a completed trip.
pub struct TripDataDart {
    /// The UUIDv4 minted at trip start, shared with every record written
    /// during the trip (#402).
    pub trip_id: String,
    pub distance_meters: f64,
    pub duration_seconds: f64,
    /// Absolute trip bounds in epoch milliseconds (#402).
    pub started_at_ms: i64,
    pub ended_at_ms: i64,
    pub start_location: Option<TripLocationDart>,
    pub stop_location: Option<TripLocationDart>,
    pub waypoints: Vec<TripWaypointDart>,
}

impl From<NativeTripData> for TripDataDart {
    fn from(data: NativeTripData) -> Self {
        Self {
            trip_id: data.trip_id,
            distance_meters: data.distance_meters,
            duration_seconds: data.duration_seconds,
            started_at_ms: data.started_at_ms,
            ended_at_ms: data.ended_at_ms,
            start_location: data.start_location.map(|l| l.into()),
            stop_location: data.stop_location.map(|l| l.into()),
            waypoints: data.waypoints.into_iter().map(|w| w.into()).collect(),
        }
    }
}

/// The moment a trip begins (#402).
pub struct TripStartDart {
    pub trip_id: String,
    pub started_at_ms: i64,
    pub start_location: Option<TripLocationDart>,
}

impl From<NativeTripStart> for TripStartDart {
    fn from(start: NativeTripStart) -> Self {
        Self {
            trip_id: start.trip_id,
            started_at_ms: start.started_at_ms,
            start_location: start.start_location.map(|l| l.into()),
        }
    }
}

/// A trip boundary crossed by a motion state change (#402).
///
/// Exactly one of the two fields is set. This is a struct rather than the
/// sealed enum the native side uses because flutter_rust_bridge lowers a
/// payload-carrying enum to a `freezed` union, and pulling `freezed` and
/// `build_runner` into the plugin package is a steep price for one type.
/// uniffi has no such constraint, so Kotlin and Swift do get the real enum.
pub struct TripTransitionDart {
    /// Set when this transition started a trip.
    pub started: Option<TripStartDart>,
    /// Set when this transition ended one.
    pub ended: Option<TripDataDart>,
}

impl From<NativeTripTransition> for TripTransitionDart {
    fn from(transition: NativeTripTransition) -> Self {
        match transition {
            NativeTripTransition::Started { start } => Self {
                started: Some(start.into()),
                ended: None,
            },
            NativeTripTransition::Ended { data } => Self {
                started: None,
                ended: Some(data.into()),
            },
        }
    }
}

/// Manages trip state and boundary detection based on motion transitions.
pub struct TripManagerDart {
    inner: NativeTripManager,
}

impl TripManagerDart {
    /// Initializes a new TripManager.
    #[flutter_rust_bridge::frb(sync)]
    pub fn new() -> Self {
        Self {
            inner: NativeTripManager::new(),
        }
    }

    /// Returns true if a trip is actively being recorded.
    #[flutter_rust_bridge::frb(sync)]
    pub fn is_trip_active(&self) -> bool {
        self.inner.is_trip_active()
    }

    /// The active trip's id, or `None` when no trip is running (#402).
    #[flutter_rust_bridge::frb(sync)]
    pub fn current_trip_id(&self) -> Option<String> {
        self.inner.current_trip_id()
    }

    /// Updates the motion state and reports the trip boundary it crossed, if
    /// any — `Started` with the new trip id, or `Ended` with the summary.
    #[flutter_rust_bridge::frb(sync)]
    pub fn on_motion_state_changed(
        &self,
        is_moving: bool,
        latitude: Option<f64>,
        longitude: Option<f64>,
        timestamp_ms: i64,
        now_ms: i64,
    ) -> Option<TripTransitionDart> {
        self.inner.on_motion_state_changed(is_moving, latitude, longitude, timestamp_ms, now_ms).map(|t| t.into())
    }

    /// Feeds a new location point to the trip manager.
    #[flutter_rust_bridge::frb(sync)]
    pub fn on_location_received(
        &self,
        latitude: f64,
        longitude: f64,
        timestamp_ms: i64,
    ) {
        self.inner.on_location_received(latitude, longitude, timestamp_ms);
    }

    /// Resets the trip manager, discarding any active trip.
    #[flutter_rust_bridge::frb(sync)]
    pub fn reset(&self) {
        self.inner.reset();
    }
}
