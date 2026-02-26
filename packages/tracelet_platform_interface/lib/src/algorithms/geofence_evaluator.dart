import 'geo_utils.dart';

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

  /// Read-only view of the geofence identifiers currently marked as "inside".
  Set<String> get insideGeofenceIds =>
      Set<String>.unmodifiable(_insideGeofenceIds);

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
    final transitions = <GeofenceTransition>[];

    for (final gf in geofences) {
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
            transitions.add(
              GeofenceTransition(
                identifier: identifier,
                action: 'ENTER',
                geofence: gf,
              ),
            );
          } else if (!isInside && wasInside) {
            _insideGeofenceIds.remove(identifier);
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
  void clear() => _insideGeofenceIds.clear();

  /// Remove a specific geofence from the "inside" set.
  ///
  /// Useful for knockout mode — after EXIT, the geofence is removed.
  void removeGeofence(String identifier) =>
      _insideGeofenceIds.remove(identifier);

  // ─────────────────────────────────────────────────────────────────────────
  // Private
  // ─────────────────────────────────────────────────────────────────────────

  static double? _toDouble(Object? value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return null;
  }
}
