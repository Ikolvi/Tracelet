import 'package:meta/meta.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

/// Event fired when the detected device activity changes.
///
/// Reports the current activity type and confidence level.
@immutable
class ActivityChangeEvent {
  /// Creates a new [ActivityChangeEvent].
  const ActivityChangeEvent({
    required this.activity,
    required this.confidence,
  });

  /// The detected activity type.
  final ActivityType activity;

  /// The confidence level of the detection.
  final ActivityConfidence confidence;

  /// Creates an [ActivityChangeEvent] from a platform map.
  factory ActivityChangeEvent.fromMap(Map<String, Object?> map) {
    ActivityType act = ActivityType.unknown;
    final rawAct = map['activity'];
    if (rawAct is int) {
      act = ActivityType.values[rawAct.clamp(0, ActivityType.values.length - 1)];
    } else if (rawAct is String) {
      act = ActivityType.values.firstWhere(
        (e) => e.name == rawAct,
        orElse: () => ActivityType.unknown,
      );
    }

    ActivityConfidence conf = ActivityConfidence.low;
    final rawConf = map['confidence'];
    if (rawConf is int) {
      if (rawConf >= 75) {
        conf = ActivityConfidence.high;
      } else if (rawConf >= 50) {
        conf = ActivityConfidence.medium;
      } else {
        conf = ActivityConfidence.low;
      }
    } else if (rawConf is String) {
      conf = ActivityConfidence.values.firstWhere(
        (e) => e.name == rawConf,
        orElse: () => ActivityConfidence.low,
      );
    }

    return ActivityChangeEvent(activity: act, confidence: conf);
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'activity': activity.name,
      'confidence': confidence.name,
    };
  }

  @override
  String toString() =>
      'ActivityChangeEvent($activity, $confidence)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivityChangeEvent &&
          runtimeType == other.runtimeType &&
          activity == other.activity &&
          confidence == other.confidence;

  @override
  int get hashCode => Object.hash(activity, confidence);
}
