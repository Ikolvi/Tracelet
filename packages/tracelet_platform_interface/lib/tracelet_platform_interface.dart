/// The platform interface for the Tracelet background geolocation plugin.
///
/// This package provides the abstract [TraceletPlatform] class that platform
/// implementations must extend, along with shared type definitions and the
/// default [MethodChannelTracelet] implementation.
library;

export 'src/tracelet_platform.dart';
export 'src/method_channel_tracelet.dart';
export 'src/event_channel_names.dart';
export 'src/types/types.dart';
