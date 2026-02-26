import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

void main() {
  group('PersistDecider', () {
    group('shouldPersistLocation', () {
      test('mode 0 (all) persists locations', () {
        expect(PersistDecider.shouldPersistLocation(0), isTrue);
      });

      test('mode 1 (location) persists locations', () {
        expect(PersistDecider.shouldPersistLocation(1), isTrue);
      });

      test('mode 2 (geofence) does not persist locations', () {
        expect(PersistDecider.shouldPersistLocation(2), isFalse);
      });

      test('mode 3 (none) does not persist locations', () {
        expect(PersistDecider.shouldPersistLocation(3), isFalse);
      });

      test('skips providerchange when disableProviderChangeRecord', () {
        expect(
          PersistDecider.shouldPersistLocation(
            0,
            event: 'providerchange',
            disableProviderChangeRecord: true,
          ),
          isFalse,
        );
      });

      test('allows providerchange when not disabled', () {
        expect(
          PersistDecider.shouldPersistLocation(
            0,
            event: 'providerchange',
            disableProviderChangeRecord: false,
          ),
          isTrue,
        );
      });
    });

    group('shouldPersistGeofence', () {
      test('mode 0 (all) persists geofences', () {
        expect(PersistDecider.shouldPersistGeofence(0), isTrue);
      });

      test('mode 1 (location) does not persist geofences', () {
        expect(PersistDecider.shouldPersistGeofence(1), isFalse);
      });

      test('mode 2 (geofence) persists geofences', () {
        expect(PersistDecider.shouldPersistGeofence(2), isTrue);
      });

      test('mode 3 (none) does not persist geofences', () {
        expect(PersistDecider.shouldPersistGeofence(3), isFalse);
      });
    });
  });
}
