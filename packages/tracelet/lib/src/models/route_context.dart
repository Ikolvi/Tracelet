import 'package:meta/meta.dart';

/// Immutable context attached to each location at record time.
///
/// When set via [Tracelet.setRouteContext], every subsequently recorded
/// location persists these fields alongside its coordinates. Unlike
/// [HttpConfig.extras] (which are read from global config at sync time),
/// route context is **captured once at insert time** and travels with the
/// location row through the sync queue — even if the app changes context
/// (e.g. switches tasks) before the batch is drained.
///
/// This is critical for multi-task or multi-driver apps where locations
/// queue up across task/session boundaries: each point is attributed to
/// the correct task, not whatever task happens to be active when sync
/// fires.
///
/// ```dart
/// // Start a delivery task
/// await Tracelet.setRouteContext(RouteContext(
///   taskId: 'delivery-42',
///   driverId: 'driver-7',
///   trackingSessionId: Uuid().v4(),
/// ));
///
/// // Later, switch to a new task — queued points keep the old context
/// await Tracelet.setRouteContext(RouteContext(
///   taskId: 'delivery-43',
///   driverId: 'driver-7',
///   trackingSessionId: Uuid().v4(),
/// ));
///
/// // Clear context when done
/// await Tracelet.clearRouteContext();
/// ```
@immutable
class RouteContext {
  /// Creates a new [RouteContext].
  const RouteContext({
    this.ownerId,
    this.driverId,
    this.taskId,
    this.trackingSessionId,
    this.startedAt,
    this.custom = const <String, String>{},
  });

  /// The ID of the entity that owns this route (e.g. fleet, company).
  final String? ownerId;

  /// The ID of the driver or operator.
  final String? driverId;

  /// The ID of the current task, delivery, or work order.
  final String? taskId;

  /// A unique session identifier for this tracking period.
  final String? trackingSessionId;

  /// ISO 8601 timestamp of when this context was activated.
  final String? startedAt;

  /// Custom key-value pairs for application-specific context.
  final Map<String, String> custom;

  /// Creates a [RouteContext] from a map.
  factory RouteContext.fromMap(Map<String, Object?> map) {
    final customRaw = map['custom'];
    return RouteContext(
      ownerId: map['ownerId'] as String?,
      driverId: map['driverId'] as String?,
      taskId: map['taskId'] as String?,
      trackingSessionId: map['trackingSessionId'] as String?,
      startedAt: map['startedAt'] as String?,
      custom: customRaw is Map
          ? Map<String, String>.from(
              customRaw.map(
                (Object? k, Object? v) => MapEntry(k.toString(), v.toString()),
              ),
            )
          : const <String, String>{},
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (ownerId != null) 'ownerId': ownerId,
      if (driverId != null) 'driverId': driverId,
      if (taskId != null) 'taskId': taskId,
      if (trackingSessionId != null) 'trackingSessionId': trackingSessionId,
      if (startedAt != null) 'startedAt': startedAt,
      if (custom.isNotEmpty) 'custom': custom,
    };
  }

  @override
  String toString() =>
      'RouteContext(ownerId: $ownerId, driverId: $driverId, '
      'taskId: $taskId, sessionId: $trackingSessionId)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RouteContext &&
          runtimeType == other.runtimeType &&
          ownerId == other.ownerId &&
          driverId == other.driverId &&
          taskId == other.taskId &&
          trackingSessionId == other.trackingSessionId &&
          startedAt == other.startedAt;

  @override
  int get hashCode =>
      Object.hash(ownerId, driverId, taskId, trackingSessionId, startedAt);
}
