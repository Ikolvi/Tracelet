/// Android implementation of the Tracelet background geolocation plugin.
library;

import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

/// The Android implementation of [TraceletPlatform].
///
/// This class registers itself as the platform implementation by calling
/// [TraceletPlatform.instance] with a [MethodChannelTracelet] instance
/// during [registerWith].
class TraceletAndroid extends MethodChannelTracelet {
  /// Registers this class as the default instance of [TraceletPlatform].
  static void registerWith() {
    TraceletPlatform.instance = TraceletAndroid();
  }
}
