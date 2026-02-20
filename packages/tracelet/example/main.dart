// ignore_for_file: avoid_print

import 'package:tracelet/tracelet.dart' as tl;

/// Minimal example demonstrating Tracelet background geolocation.
Future<void> main() async {
  // 1. Subscribe to location events.
  tl.Tracelet.onLocation((location) {
    print(
      '📍 ${location.coords.latitude}, ${location.coords.longitude} '
      '· accuracy: ${location.coords.accuracy}m',
    );
  });

  // 2. Initialize the plugin with a configuration.
  final state = await tl.Tracelet.ready(tl.Config(
    geo: tl.GeoConfig(
      desiredAccuracy: tl.DesiredAccuracy.high,
      distanceFilter: 10,
    ),
    logging: tl.LogConfig(logLevel: tl.LogLevel.verbose),
  ));

  print('Tracelet ready — enabled: ${state.enabled}, '
      'tracking: ${state.trackingMode}');

  // 3. Start tracking.
  await tl.Tracelet.start();
}
