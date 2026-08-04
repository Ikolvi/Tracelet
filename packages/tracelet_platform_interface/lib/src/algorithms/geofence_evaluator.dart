import 'package:tracelet_platform_interface/src/algorithms/geo_utils.dart';
import 'package:tracelet_platform_interface/src/algorithms/rtree.dart';

/// A single geofence state transition detected by [GeofenceEvaluator].
class GeofenceTransition {
  /// Creates a new [GeofenceTransition] containing details about the crossing.
  const GeofenceTransition({
    required this.identifier,
    required this.action,
    this.distance,
    this.geofence = const <String, Object?>{},
  });

  /// The geofence identifier that triggered.
  final String identifier;

  /// `'ENTER'` or `'EXIT'`.
  final String action;

  /// Distance in meters from the geofence center (circular only).
  final double? distance;

  /// The full geofence data map.
  final Map<String, Object?> geofence;

  @override
  String toString() =>
      'GeofenceTransition($action: $identifier'
      '${distance != null ? ', ${distance!.toStringAsFixed(1)}m' : ''})';
}

/// Pure-Dart high-accuracy geofence proximity evaluator.
///
/// Replaces the `evaluateHighAccuracyProximity()` method previously
/// duplicated in native Kotlin (`GeofenceManager.kt`) and Swift
/// (`GeofenceManager.swift`).
///
/// On each location update, this evaluator computes the distance from the
/// current position to every registered geofence and fires ENTER/EXIT
/// transitions based on threshold crossings. It maintains an internal set
/// of "inside" geofence identifiers to track state across calls.
///
/// Supports both **circular** geofences (distance ≤ radius) and **polygon**
/// geofences (ray-casting point-in-polygon via [GeoUtils]).
///
/// **This is a pure Dart implementation** — no native code required. It runs
/// identically on Android, iOS, web, macOS, Linux, and Windows.
///
/// ```dart
/// final evaluator = GeofenceEvaluator();
/// final transitions = evaluator.evaluateProximity(
///   latitude: 37.422,
///   longitude: -122.084,
///   geofences: [
///     {'identifier': 'office', 'latitude': 37.422, 'longitude': -122.084, 'radius': 100},
///   ],
/// );
/// for (final t in transitions) {
///   print('${t.action}: ${t.identifier}');
/// }
/// ```
class GeofenceEvaluator {
  /// Fraction of the geofence radius used as an exit-hysteresis band.
  ///
  /// A device ENTERs at the true `radius`, but only EXITs once it is farther
  /// than `radius * (1 + _exitHysteresisFraction)` from the center. This
  /// asymmetric threshold prevents ENTER/EXIT "flapping" when a stationary
  /// device's GPS fixes jitter across the boundary (issue #268).
  static const double _exitHysteresisFraction = 0.1;

  /// Minimum exit-hysteresis band in meters, so small-radius geofences still
  /// get a meaningful buffer against typical GPS noise (e.g. a 50 m geofence
  /// gets a 20 m band rather than 5 m).
  static const double _minExitHysteresisMeters = 20;

  /// Number of consecutive out-of-fence fixes required to confirm an EXIT
  /// (mirror of `GEOFENCE_EXIT_CONFIRMATIONS` in the Rust core).
  ///
  /// Hysteresis is the *spatial* half of a robust exit test; this is the
  /// *temporal* half. Consumer GNSS routinely emits a lone "over-confident"
  /// fix — one that lands far outside while reporting a tight accuracy the
  /// accuracy-aware gate (#274) cannot see through — and such a fix is always
  /// transient (the device is back inside on the very next fix). Requiring the
  /// device to be confidently outside for N consecutive fixes absorbs those
  /// glitches, while a genuine departure still fires exactly one EXIT, delayed
  /// only by (N-1) fix intervals (issue #294).
  static const int _exitConfirmations = 2;

  /// Set of geofence identifiers the device is currently inside.
  final Set<String> _insideGeofenceIds = <String>{};

  /// Per-fence count of consecutive out-of-fence fixes seen while still inside,
  /// pending EXIT confirmation. Reset the moment the device is back inside.
  final Map<String, int> _pendingExitCounts = <String, int>{};

  /// Cached unmodifiable view — invalidated when [_insideGeofenceIds] changes (D-M4).
  Set<String>? _cachedInsideView;

  /// Spatial index for O(log n) geofence queries. Built by [indexGeofences].
  RTree<Map<String, Object?>>? _rtree;

  /// Geofence data indexed by identifier, for EXIT detection on indexed path.
  Map<String, Map<String, Object?>>? _indexedGeofences;

  /// Read-only view of the geofence identifiers currently marked as "inside".
  Set<String> get insideGeofenceIds =>
      _cachedInsideView ??= Set<String>.unmodifiable(_insideGeofenceIds);

  /// Whether a spatial index is currently active.
  bool get isIndexed => _rtree != null;

  /// Build an R-tree spatial index over [geofences] for O(log n) queries.
  ///
  /// When the index is present, [evaluateProximity] uses it to narrow
  /// candidates before computing exact distances. For ≤ 50 geofences the
  /// linear scan is fast enough; the index becomes worthwhile at 100+.
  ///
  /// Call this whenever the registered geofence list changes. To remove
  /// the index, call [clearIndex].
  void indexGeofences(List<Map<String, Object?>> geofences) {
    final tree = RTree<Map<String, Object?>>();
    final lookup = <String, Map<String, Object?>>{};

    for (final gf in geofences) {
      final id = gf['identifier'] as String?;
      if (id == null) continue;

      final lat = _toDouble(gf['latitude']);
      final lng = _toDouble(gf['longitude']);
      if (lat == null || lng == null) continue;

      final radius = _toDouble(gf['radius']) ?? 100.0;
      tree.insert(lat, lng, radius, gf);
      lookup[id] = gf;
    }

    _rtree = tree;
    _indexedGeofences = lookup;
  }

  /// Remove the spatial index. [evaluateProximity] will fall back to O(n).
  void clearIndex() {
    _rtree?.clear();
    _rtree = null;
    _indexedGeofences = null;
  }

  /// Evaluate all geofences against the current position.
  ///
  /// Returns a list of [GeofenceTransition]s that occurred (may be empty).
  ///
  /// Each geofence map should contain:
  /// - `identifier` (`String`) — unique identifier.
  /// - `latitude` (`double`) — center latitude (for circular geofences).
  /// - `longitude` (`double`) — center longitude.
  /// - `radius` (`double`) — radius in meters (default 100).
  /// - `vertices` (`List<List<double>>`) — optional polygon vertices
  ///   (`[[lat, lng], ...]`). When present with ≥ 3 vertices, the geofence
  ///   is treated as a polygon.
  ///
  /// [accuracy] is the fix's horizontal accuracy radius in meters. It makes the
  /// circular EXIT decision drift-aware: a geofence only EXITs once the entire
  /// accuracy circle clears the fence (`distance - accuracy > radius + buffer`),
  /// preventing a single high-drift fix from firing a false EXIT (#274). Pass
  /// `0.0` (the default) to disable gating and keep the legacy behavior.
  List<GeofenceTransition> evaluateProximity({
    required double latitude,
    required double longitude,
    required List<Map<String, Object?>> geofences,
    double accuracy = 0.0,
  }) {
    // Clamp unknown/invalid accuracy (some platforms report negative when the
    // fix has no horizontal accuracy) to 0 so gating is a no-op rather than
    // pulling the exit threshold inward (#274).
    final acc = accuracy.isFinite && accuracy > 0 ? accuracy : 0.0;

    // When a spatial index exists, use it to narrow candidates.
    final effectiveGeofences = _resolveGeofences(
      latitude,
      longitude,
      geofences,
    );

    final transitions = <GeofenceTransition>[];

    for (final gf in effectiveGeofences) {
      final identifier = gf['identifier'] as String?;
      if (identifier == null) continue;

      final gfLat = _toDouble(gf['latitude']);
      final gfLng = _toDouble(gf['longitude']);

      // ── Polygon geofence ──────────────────────────────────────────────
      final rawVertices = gf['vertices'];
      if (rawVertices is List && rawVertices.length >= 3) {
        final vertices = <List<double>>[];
        var valid = true;
        for (final v in rawVertices) {
          if (v is List && v.length >= 2) {
            final lat = _toDouble(v[0]);
            final lng = _toDouble(v[1]);
            if (lat != null && lng != null) {
              vertices.add(<double>[lat, lng]);
              continue;
            }
          }
          valid = false;
          break;
        }

        if (valid && vertices.length >= 3) {
          final isInside = GeoUtils.isPointInPolygon(
            lat: latitude,
            lng: longitude,
            vertices: vertices,
          );
          final wasInside = _insideGeofenceIds.contains(identifier);

          if (isInside && !wasInside) {
            _insideGeofenceIds.add(identifier);
            _pendingExitCounts.remove(identifier);
            _cachedInsideView = null;
            transitions.add(
              GeofenceTransition(
                identifier: identifier,
                action: 'ENTER',
                geofence: gf,
              ),
            );
          } else if (wasInside) {
            if (isInside) {
              // Back inside: cancel any pending exit (transient excursion).
              _pendingExitCounts.remove(identifier);
            } else if (_confirmExit(identifier)) {
              _insideGeofenceIds.remove(identifier);
              _cachedInsideView = null;
              transitions.add(
                GeofenceTransition(
                  identifier: identifier,
                  action: 'EXIT',
                  geofence: gf,
                ),
              );
            }
          }
          continue; // Skip circular check.
        }
      }

      // ── Circular geofence ─────────────────────────────────────────────
      if (gfLat == null || gfLng == null) continue;

      final gfRadius = _toDouble(gf['radius']) ?? 100.0;
      if (gfRadius <= 0) continue;

      final distance = GeoUtils.haversine(latitude, longitude, gfLat, gfLng);
      final wasInside = _insideGeofenceIds.contains(identifier);

      // Exit hysteresis (#268): ENTER at the true radius, but only EXIT once
      // the device is clearly beyond it (radius + buffer). Without this, a
      // stationary device whose fixes jitter across the boundary produces
      // repeated ENTER/EXIT events.
      final scaledBuffer = gfRadius * _exitHysteresisFraction;
      final exitBuffer = scaledBuffer > _minExitHysteresisMeters
          ? scaledBuffer
          : _minExitHysteresisMeters;
      final entered = distance <= gfRadius;
      // Accuracy-aware EXIT (#274): require the whole error circle to clear the
      // fence, not just the reported point. `distance - acc` is the nearest the
      // device could plausibly be given the fix uncertainty; only exit when even
      // that is clearly beyond the boundary. This stops a single high-drift fix
      // (reported with a correspondingly large accuracy) from firing a false
      // EXIT while the device is stationary inside the fence. ENTER is left
      // accuracy-agnostic so arrivals still trigger promptly.
      final exited = (distance - acc) > gfRadius + exitBuffer;

      if (entered && !wasInside) {
        _insideGeofenceIds.add(identifier);
        _pendingExitCounts.remove(identifier);
        _cachedInsideView = null;
        transitions.add(
          GeofenceTransition(
            identifier: identifier,
            action: 'ENTER',
            distance: distance,
            geofence: gf,
          ),
        );
      } else if (wasInside) {
        if (exited) {
          // Confirmed-exit gate (#294): a lone over-confident fix that lands
          // outside is a transient glitch, so require the device to be
          // confidently outside for [_exitConfirmations] consecutive fixes
          // before emitting EXIT.
          if (_confirmExit(identifier)) {
            _insideGeofenceIds.remove(identifier);
            _cachedInsideView = null;
            transitions.add(
              GeofenceTransition(
                identifier: identifier,
                action: 'EXIT',
                distance: distance,
                geofence: gf,
              ),
            );
          }
        } else {
          // Within `radius + exitBuffer` while inside: still in. Any in-flight
          // exit excursion was transient — reset its count.
          _pendingExitCounts.remove(identifier);
        }
      }
    }

    return transitions;
  }

  /// Records one more consecutive out-of-fence observation for [identifier] and
  /// returns true once [_exitConfirmations] have accumulated — clearing the
  /// count so a later re-entry then exit starts fresh. Returns false (holding
  /// the EXIT) while confirmations are still accruing.
  bool _confirmExit(String identifier) {
    final count = (_pendingExitCounts[identifier] ?? 0) + 1;
    if (count >= _exitConfirmations) {
      _pendingExitCounts.remove(identifier);
      return true;
    }
    _pendingExitCounts[identifier] = count;
    return false;
  }

  /// Clear all tracking state. Call when tracking restarts.
  void clear() {
    _insideGeofenceIds.clear();
    _pendingExitCounts.clear();
    _cachedInsideView = null;
    clearIndex();
  }

  /// Remove a specific geofence from the "inside" set.
  ///
  /// Useful for knockout mode — after EXIT, the geofence is removed.
  void removeGeofence(String identifier) {
    _insideGeofenceIds.remove(identifier);
    _pendingExitCounts.remove(identifier);
    _cachedInsideView = null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Private
  // ─────────────────────────────────────────────────────────────────────────

  /// When a spatial index exists, narrow the candidate list using an R-tree
  /// query plus any currently-inside geofences (to catch EXITs).
  /// Falls back to [allGeofences] when no index is built.
  List<Map<String, Object?>> _resolveGeofences(
    double lat,
    double lng,
    List<Map<String, Object?>> allGeofences,
  ) {
    final tree = _rtree;
    final lookup = _indexedGeofences;
    if (tree == null || lookup == null) return allGeofences;

    // Query a generous radius — 50 km covers any practical geofence.
    const searchRadius = 50000.0; // meters
    final nearby = tree.queryCircle(lat, lng, searchRadius);

    // Ensure currently-inside geofences are always evaluated (EXIT detection).
    if (_insideGeofenceIds.isEmpty) return nearby;

    final seen = <String>{};
    final merged = <Map<String, Object?>>[];
    for (final gf in nearby) {
      final id = gf['identifier'] as String?;
      if (id != null) seen.add(id);
      merged.add(gf);
    }
    for (final id in _insideGeofenceIds) {
      if (!seen.contains(id)) {
        final gf = lookup[id];
        if (gf != null) merged.add(gf);
      }
    }
    return merged;
  }

  static double? _toDouble(Object? value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    // `num` has exactly two subtypes (double, int) — both handled above (D-L1).
    return null;
  }
}
