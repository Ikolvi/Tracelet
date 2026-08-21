import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:tracelet_platform_interface/src/rust/api_dart/trip.dart';

/// Rust-powered TripManager.
class TripManager {
  /// Creates a [TripManager] instance that tracks geographical trips.
  TripManager() {
    if (!kIsWeb) {
      _inner = TripManagerDart();
    }
  }
  TripManagerDart? _inner;

  /// Callback fired when a trip is completed, returning the trip summary.
  void Function(Map<String, Object?>)? onTripEnd;

  /// Callback fired when a trip *starts*, with its freshly minted id (#402).
  ///
  /// Before #402 a trip only became observable once it was over, so anything
  /// wanting to tag records with the trip they belong to had no moment to act
  /// on and had to re-derive the boundary from raw motion changes.
  void Function(Map<String, Object?>)? onTripStart;

  /// Returns true if a trip is currently being tracked.
  bool get isTripActive => _inner?.isTripActive() ?? false;

  /// The active trip's id, or `null` between trips (#402).
  ///
  /// Prefers the id supplied by the native layer, which is the one actually
  /// stamped onto database rows. This manager's own Rust instance mints an id
  /// too — it has to, since it runs the same state machine — but that one is
  /// only a fallback for a platform that does not report its trip.
  String? get currentTripId => _nativeTripId ?? _inner?.currentTripId();

  /// The native layer's id for the trip currently running, when it reported
  /// one. Adopted at trip start and held until trip end, so the summary can be
  /// labelled with it after the native side has already cleared its own.
  String? _nativeTripId;

  /// Feeds motion state changes to the engine to start or stop a trip.
  void onMotionStateChanged({
    required bool isMoving,
    double? latitude,
    double? longitude,
    Object? timestamp,
    String? nativeTripId,
  }) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    var timestampMs = nowMs;
    if (timestamp is int) {
      timestampMs = timestamp;
    } else if (timestamp is String) {
      timestampMs =
          DateTime.tryParse(timestamp)?.millisecondsSinceEpoch ?? nowMs;
    }

    if (_inner == null) return;

    final transition = _inner!.onMotionStateChanged(
      isMoving: isMoving,
      latitude: latitude,
      longitude: longitude,
      timestampMs: PlatformInt64Util.from(timestampMs),
      nowMs: PlatformInt64Util.from(nowMs),
    );

    final start = transition?.started;
    if (start != null) {
      // Adopt the native id if one came with the event. Without this the two
      // trip managers — this one and the platform's — would label the same
      // journey with two different ids, and the one an app received here would
      // match nothing in the synced records.
      _nativeTripId = nativeTripId;
      final startLocation = <String, Object?>{};
      if (start.startLocation != null) {
        startLocation['latitude'] = start.startLocation!.latitude;
        startLocation['longitude'] = start.startLocation!.longitude;
      }
      onTripStart?.call(<String, Object?>{
        'tripId': nativeTripId ?? start.tripId,
        'startedAt': _asInt(start.startedAtMs),
        'startLocation': startLocation,
      });
      return;
    }

    final tripData = transition?.ended;
    if (tripData != null && onTripEnd != null) {
      final startMap = <String, Object?>{};
      if (tripData.startLocation != null) {
        startMap['latitude'] = tripData.startLocation!.latitude;
        startMap['longitude'] = tripData.startLocation!.longitude;
      }

      final stopMap = <String, Object?>{};
      if (tripData.stopLocation != null) {
        stopMap['latitude'] = tripData.stopLocation!.latitude;
        stopMap['longitude'] = tripData.stopLocation!.longitude;
      }

      final waypoints = tripData.waypoints.map((w) {
        return <String, Object?>{
          'latitude': w.latitude,
          'longitude': w.longitude,
          'timestamp': w.timestampMs is BigInt
              ? (w.timestampMs as dynamic).toInt()
              : w.timestampMs,
        };
      }).toList();

      final resolvedTripId = _nativeTripId ?? tripData.tripId;
      _nativeTripId = null;
      onTripEnd!({
        'isMoving': false,
        // #402: the join key shared with every location and driving event
        // recorded during this trip.
        'tripId': resolvedTripId,
        'startedAt': _asInt(tripData.startedAtMs),
        'endedAt': _asInt(tripData.endedAtMs),
        'distance': tripData.distanceMeters,
        'duration': tripData.durationSeconds,
        'startLocation': startMap,
        'stopLocation': stopMap,
        'waypoints': waypoints,
      });
    }
  }

  /// Feeds a new location waypoint into the active trip.
  void onLocationReceived({
    required double latitude,
    required double longitude,
    Object? timestamp,
  }) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    var timestampMs = nowMs;
    if (timestamp is int) {
      timestampMs = timestamp;
    } else if (timestamp is String) {
      timestampMs =
          DateTime.tryParse(timestamp)?.millisecondsSinceEpoch ?? nowMs;
    }

    if (_inner == null) return;

    _inner!.onLocationReceived(
      latitude: latitude,
      longitude: longitude,
      timestampMs: PlatformInt64Util.from(timestampMs),
    );
  }

  /// Resets the trip manager, clearing any active trips.
  void reset() {
    _nativeTripId = null;
    _inner?.reset();
  }

  /// Narrows a bridge `PlatformInt64`, which is an `int` natively and a
  /// `BigInt` on web-shaped builds.
  static int? _asInt(Object? value) => value is BigInt
      ? value.toInt()
      : value is int
      ? value
      : null;
}
