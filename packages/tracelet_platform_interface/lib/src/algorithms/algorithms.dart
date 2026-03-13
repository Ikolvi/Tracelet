/// Shared pure-Dart algorithms for the Tracelet platform interface.
///
/// These algorithms were previously duplicated in native Kotlin (Android)
/// and Swift (iOS) code. They are now shared across all platforms.
library;

export 'adaptive_sampling_engine.dart';
export 'battery_budget_engine.dart';
export 'carbon_estimator.dart';
export 'delta_encoder.dart';
export 'geo_utils.dart';
export 'geofence_evaluator.dart';
export 'kalman_filter.dart';
export 'location_processor.dart';
export 'persist_decider.dart';
export 'rtree.dart';
export 'schedule_parser.dart';
export 'trip_manager.dart';
