/// The platform interface for the Tracelet background geolocation plugin.
///
/// This package provides the abstract [TraceletPlatform] class that platform
/// implementations must extend, along with shared type definitions and the
/// default [PigeonTracelet] implementation.
library;

export 'src/algorithms/algorithms.dart';
export 'src/tracelet_platform.dart';
export 'src/method_channel_tracelet.dart'; // Legacy, kept for backward compat
export 'src/pigeon_tracelet.dart';
export 'src/pigeon_event_receiver.dart';
export 'src/event_channel_names.dart';
export 'src/generated/tracelet_api.g.dart';
export 'src/types/types.dart';
