import 'package:meta/meta.dart';

/// Event dispatched to the headless (background isolate) callback.
///
/// The [name] identifies the event type (e.g. `'location'`, `'geofence'`,
/// `'heartbeat'`), and [event] contains the event payload as a map.
@immutable
class HeadlessEvent {
  /// Creates a new [HeadlessEvent].
  const HeadlessEvent({
    required this.name,
    required this.event,
  });

  /// The name of the event (corresponds to the EventChannel suffix).
  ///
  /// Known values: `'location'`, `'motionchange'`, `'activitychange'`,
  /// `'providerchange'`, `'geofence'`, `'geofenceschange'`, `'heartbeat'`,
  /// `'http'`, `'schedule'`, `'powersavechange'`, `'connectivitychange'`,
  /// `'enabledchange'`, `'notificationaction'`, `'authorization'`.
  final String name;

  /// The raw event payload as a map.
  ///
  /// Use the appropriate model's `fromMap()` factory to parse this,
  /// based on the [name] value.
  final Map<String, Object?> event;

  /// Creates a [HeadlessEvent] from a platform map.
  factory HeadlessEvent.fromMap(Map<String, Object?> map) {
    final eventRaw = map['event'];
    final eventMap = eventRaw is Map
        ? eventRaw.map<String, Object?>(
            (Object? k, Object? v) => MapEntry(k.toString(), v))
        : const <String, Object?>{};

    return HeadlessEvent(
      name: map['name'] as String? ?? '',
      event: eventMap,
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'name': name,
      'event': event,
    };
  }

  @override
  String toString() => 'HeadlessEvent($name)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HeadlessEvent &&
          runtimeType == other.runtimeType &&
          name == other.name;

  @override
  int get hashCode => name.hashCode;
}
