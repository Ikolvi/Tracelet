import 'geo_utils.dart';
import 'rtree.dart';

/// A single geofence state transition detected by [GeofenceEvaluator].
class GeofenceTransition {
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
  /// Set of geofence identifiers the device is currently inside.
  final Set<String> _insideGeofenceIds = <String>{};

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
    final tree = RTree<Map<String, Object?>>(maxEntries: 8);
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
  List<GeofenceTransition> evaluateProximity({
    required double latitude,
    required double longitude,
    required List<Map<String, Object?>> geofences,
  }) {
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
            _cachedInsideView = null;
            transitions.add(
              GeofenceTransition(
                identifier: identifier,
                action: 'ENTER',
                geofence: gf,
              ),
            );
          } else if (!isInside && wasInside) {
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
          continue; // Skip circular check.
        }
      }

      // ── Circular geofence ─────────────────────────────────────────────
      if (gfLat == null || gfLng == null) continue;

      final gfRadius = _toDouble(gf['radius']) ?? 100.0;
      if (gfRadius <= 0) continue;

      final distance = GeoUtils.haversine(latitude, longitude, gfLat, gfLng);
      final wasInside = _insideGeofenceIds.contains(identifier);
      final isInside = distance <= gfRadius;

      if (isInside && !wasInside) {
        _insideGeofenceIds.add(identifier);
        _cachedInsideView = null;
        transitions.add(
          GeofenceTransition(
            identifier: identifier,
            action: 'ENTER',
            distance: distance,
            geofence: gf,
          ),
        );
      } else if (!isInside && wasInside) {
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
    }

    return transitions;
  }

  /// Clear all tracking state. Call when tracking restarts.
  void clear() {
    _insideGeofenceIds.clear();
    _cachedInsideView = null;
    clearIndex();
  }

  /// Remove a specific geofence from the "inside" set.
  ///
  /// Useful for knockout mode — after EXIT, the geofence is removed.
  void removeGeofence(String identifier) {
    _insideGeofenceIds.remove(identifier);
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
