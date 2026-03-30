import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet/tracelet.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

import 'permission_degradation_test.dart' show EmptyEventStreamsMixin;

/// Mock platform for testing safe stop / getState before ready().
class MockSafeStopPlatform extends TraceletPlatform
    with EmptyEventStreamsMixin {
  final List<({String method, Object? args})> calls = [];

  /// Whether ready() has been called — controls what getState() returns.
  bool readyCalled = false;

  /// Configurable state returned by getState/stop/start.
  Map<String, Object?> stateResult = {
    'enabled': false,
    'trackingMode': 0,
    'isMoving': false,
    'odometer': 0.0,
  };

  @override
  Future<Map<String, Object?>> ready(Map<String, Object?> config) async {
    calls.add((method: 'ready', args: config));
    readyCalled = true;
    stateResult['enabled'] = false;
    return Map<String, Object?>.from(stateResult);
  }

  @override
  Future<Map<String, Object?>> start() async {
    calls.add((method: 'start', args: null));
    stateResult['enabled'] = true;
    return Map<String, Object?>.from(stateResult);
  }

  @override
  Future<Map<String, Object?>> stop() async {
    calls.add((method: 'stop', args: null));
    stateResult['enabled'] = false;
    return Map<String, Object?>.from(stateResult);
  }

  @override
  Future<Map<String, Object?>> getState() async {
    calls.add((method: 'getState', args: null));
    // Mirrors native SDK: returns disabled state before ready()
    if (!readyCalled) {
      return {
        'enabled': false,
        'trackingMode': 0,
        'isMoving': false,
        'odometer': 0.0,
      };
    }
    return Map<String, Object?>.from(stateResult);
  }
}

void main() {
  late MockSafeStopPlatform mock;

  setUp(() {
    mock = MockSafeStopPlatform();
    TraceletPlatform.instance = mock;
  });

  tearDown(() {
    mock.calls.clear();
  });

  // ==========================================================================
  // getState() before ready() — Issue #46
  // ==========================================================================
  group('getState before ready (issue #46)', () {
    test('returns disabled state when called before ready()', () async {
      final state = await Tracelet.getState();

      expect(state.enabled, isFalse);
      expect(state.isMoving, isFalse);
      expect(state.trackingMode, TrackingMode.location);
      expect(mock.calls.length, 1);
      expect(mock.calls.first.method, 'getState');
    });

    test('returns correct state after ready()', () async {
      await Tracelet.ready(Config());
      final state = await Tracelet.getState();

      expect(state.enabled, isFalse);
      expect(mock.calls.length, 2);
      expect(mock.calls[0].method, 'ready');
      expect(mock.calls[1].method, 'getState');
    });

    test('returns enabled state after start()', () async {
      await Tracelet.ready(Config());
      await Tracelet.start();
      final state = await Tracelet.getState();

      expect(state.enabled, isTrue);
      expect(mock.calls.length, 3);
      expect(mock.calls[0].method, 'ready');
      expect(mock.calls[1].method, 'start');
      expect(mock.calls[2].method, 'getState');
    });
  });

  // ==========================================================================
  // Safe stop pattern — check getState() before calling stop()
  // ==========================================================================
  group('safe stop pattern', () {
    test('skip stop if getState shows not enabled', () async {
      // Simulate the user's pattern: check state, skip stop if not running
      final state = await Tracelet.getState();
      if (state.enabled) {
        await Tracelet.stop();
      }

      // stop() should NOT have been called
      expect(mock.calls.length, 1);
      expect(mock.calls.first.method, 'getState');
      expect(mock.calls.where((c) => c.method == 'stop'), isEmpty);
    });

    test('calls stop if getState shows enabled', () async {
      await Tracelet.ready(Config());
      await Tracelet.start();
      mock.calls.clear();

      // Now state.enabled is true
      final state = await Tracelet.getState();
      expect(state.enabled, isTrue);

      if (state.enabled) {
        await Tracelet.stop();
      }

      expect(mock.calls.length, 2);
      expect(mock.calls[0].method, 'getState');
      expect(mock.calls[1].method, 'stop');
    });

    test('stop before ready returns disabled state', () async {
      // Calling stop directly before ready should still work (with isReady
      // guards in native SDK). Verify the Dart layer doesn't crash.
      final state = await Tracelet.stop();

      expect(state.enabled, isFalse);
      expect(mock.calls.length, 1);
      expect(mock.calls.first.method, 'stop');
    });

    test('full user pattern: getState → stop → ready', () async {
      // Reproduce @sfaizanh's pattern from issue #46
      final state = await Tracelet.getState();
      if (state.enabled) {
        await Tracelet.stop();
      }
      final readyState = await Tracelet.ready(Config());

      expect(readyState.enabled, isFalse);
      // Only getState + ready; stop was skipped because enabled=false
      expect(mock.calls.length, 2);
      expect(mock.calls[0].method, 'getState');
      expect(mock.calls[1].method, 'ready');
    });
  });
}
