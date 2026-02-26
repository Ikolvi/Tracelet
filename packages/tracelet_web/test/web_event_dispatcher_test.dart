import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet_web/src/web_event_dispatcher.dart';

void main() {
  late WebEventDispatcher events;

  setUp(() {
    events = WebEventDispatcher();
  });

  tearDown(() {
    events.dispose();
  });

  group('WebEventDispatcher', () {
    test('emitLocation broadcasts to listeners', () async {
      final locations = <Map<String, Object?>>[];
      events.onLocation.listen(locations.add);

      events.emitLocation(<String, Object?>{'lat': 37.0});
      events.emitLocation(<String, Object?>{'lat': 38.0});
      await Future<void>.delayed(Duration.zero);

      expect(locations, hasLength(2));
    });

    test('emitMotionChange broadcasts', () async {
      Map<String, Object?>? received;
      events.onMotionChange.listen((e) => received = e);

      events.emitMotionChange(<String, Object?>{'isMoving': true});
      await Future<void>.delayed(Duration.zero);

      expect(received, isNotNull);
      expect(received!['isMoving'], true);
    });

    test('emitGeofence broadcasts', () async {
      Map<String, Object?>? received;
      events.onGeofence.listen((e) => received = e);

      events.emitGeofence(<String, Object?>{'action': 'ENTER'});
      await Future<void>.delayed(Duration.zero);

      expect(received?['action'], 'ENTER');
    });

    test('emitConnectivityChange broadcasts', () async {
      bool? received;
      events.onConnectivityChange.listen((e) {
        received = e['connected'] as bool?;
      });

      events.emitConnectivityChange(true);
      await Future<void>.delayed(Duration.zero);

      expect(received, true);
    });

    test('emitEnabledChange broadcasts', () async {
      bool? received;
      events.onEnabledChange.listen((e) => received = e);

      events.emitEnabledChange(false);
      await Future<void>.delayed(Duration.zero);

      expect(received, false);
    });

    test('emitHttp broadcasts', () async {
      Map<String, Object?>? received;
      events.onHttp.listen((e) => received = e);

      events.emitHttp(<String, Object?>{'success': true, 'status': 200});
      await Future<void>.delayed(Duration.zero);

      expect(received?['success'], true);
      expect(received?['status'], 200);
    });

    test('log appends to internal log', () {
      events.log('info', 'Hello');
      events.log('error', 'Oops');

      final log = events.getLog();
      expect(log, contains('[info] Hello'));
      expect(log, contains('[error] Oops'));
    });

    test('clearLog empties log', () {
      events.log('info', 'something');
      events.clearLog();
      expect(events.getLog(), isEmpty);
    });

    test('multiple listeners on broadcast stream', () async {
      final list1 = <Map<String, Object?>>[];
      final list2 = <Map<String, Object?>>[];

      events.onLocation.listen(list1.add);
      events.onLocation.listen(list2.add);

      events.emitLocation(<String, Object?>{'id': 1});
      await Future<void>.delayed(Duration.zero);

      expect(list1, hasLength(1));
      expect(list2, hasLength(1));
    });
  });
}
