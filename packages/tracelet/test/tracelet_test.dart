import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet/tracelet.dart';

void main() {
  test('Config has sensible defaults', () {
    const config = Config();
    expect(config.geo.desiredAccuracy, DesiredAccuracy.high);
    expect(config.geo.distanceFilter, 10.0);
    expect(config.app.stopOnTerminate, true);
    expect(config.http.autoSync, true);
  });

  test('Config round-trip serialization', () {
    const config = Config(
      geo: GeoConfig(distanceFilter: 50.0),
      app: AppConfig(heartbeatInterval: 120),
    );
    final map = config.toMap();
    final restored = Config.fromMap(map);
    expect(restored.geo.distanceFilter, 50.0);
    expect(restored.app.heartbeatInterval, 120);
  });
}
