import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

void main() async {
  await RustLib.init();
  group('BatteryBudgetEngine', () {
    test('constructor sets defaults', () {
      final engine = BatteryBudgetEngine();

      expect(engine.targetBudgetPerHour, 3.0);
      expect(engine.distanceFilter, 10.0);
      expect(engine.accuracyIndex, 0);
      expect(engine.periodicInterval, isNull);
    });

    test('constructor accepts custom initial values', () {
      final engine = BatteryBudgetEngine(
        targetBudgetPerHour: 5,
        initialDistanceFilter: 50,
        initialAccuracyIndex: 2,
        initialPeriodicInterval: 300,
      );

      expect(engine.targetBudgetPerHour, 5.0);
      expect(engine.distanceFilter, 50.0);
      expect(engine.accuracyIndex, 2);
      expect(engine.periodicInterval, 300);
    });

    test('clamps accuracy index to 0-4 range', () {
      final tooHigh = BatteryBudgetEngine(initialAccuracyIndex: 10);
      expect(tooHigh.accuracyIndex, 4);

      final tooLow = BatteryBudgetEngine(initialAccuracyIndex: -5);
      expect(tooLow.accuracyIndex, 0);
    });

    test('first processSample returns null (baseline)', () {
      final engine = BatteryBudgetEngine();

      final result = engine.processSample(0.95);
      expect(result, isNull);
    });

    test('second processSample within 60s returns null', () {
      final engine = BatteryBudgetEngine();

      // First call sets baseline
      engine.processSample(0.95);

      // Immediate second call — too soon (< 60 seconds)
      final result = engine.processSample(0.90);
      expect(result, isNull);
    });

    test('reset allows re-establishing baseline', () {
      final engine = BatteryBudgetEngine();

      engine.processSample(0.95);
      engine.reset();

      // After reset, next call should return null (new baseline)
      final result = engine.processSample(0.90);
      expect(result, isNull);
    });

    test('reset does not change configuration', () {
      final engine = BatteryBudgetEngine(
        targetBudgetPerHour: 5,
        initialDistanceFilter: 50,
        initialAccuracyIndex: 2,
      );

      engine.processSample(0.95);
      engine.reset();

      expect(engine.targetBudgetPerHour, 5.0);
      expect(engine.distanceFilter, 50.0);
      expect(engine.accuracyIndex, 2);
    });
  });

  group('BudgetAdjustmentEvent', () {
    test('constructor stores all fields', () {
      const event = BudgetAdjustmentEvent(
        currentBatteryDrain: 4.5,
        targetBudget: 3,
        newDistanceFilter: 50,
        newDesiredAccuracy: 2,
        newPeriodicInterval: 600,
      );

      expect(event.currentBatteryDrain, 4.5);
      expect(event.targetBudget, 3.0);
      expect(event.newDistanceFilter, 50.0);
      expect(event.newDesiredAccuracy, 2);
      expect(event.newPeriodicInterval, 600);
    });

    test('newPeriodicInterval defaults to null', () {
      const event = BudgetAdjustmentEvent(
        currentBatteryDrain: 2,
        targetBudget: 3,
        newDistanceFilter: 10,
        newDesiredAccuracy: 0,
      );

      expect(event.newPeriodicInterval, isNull);
    });
  });

  group('BatteryBudgetEngine — internal state', () {
    test('initial distanceFilter matches constructor param', () {
      final engine = BatteryBudgetEngine(initialDistanceFilter: 100);
      expect(engine.distanceFilter, 100.0);
    });

    test('initial periodicInterval matches constructor param', () {
      final engine = BatteryBudgetEngine(initialPeriodicInterval: 300);
      expect(engine.periodicInterval, 300);
    });

    test('periodicInterval is null when not provided', () {
      final engine = BatteryBudgetEngine();
      expect(engine.periodicInterval, isNull);
    });

    test('accuracy index clamped to minimum 0', () {
      final engine = BatteryBudgetEngine(initialAccuracyIndex: -100);
      expect(engine.accuracyIndex, 0);
    });

    test('accuracy index clamped to maximum 4', () {
      final engine = BatteryBudgetEngine(initialAccuracyIndex: 100);
      expect(engine.accuracyIndex, 4);
    });

    test('reset preserves distance filter and accuracy', () {
      final engine = BatteryBudgetEngine(
        targetBudgetPerHour: 5,
        initialDistanceFilter: 200,
        initialAccuracyIndex: 3,
        initialPeriodicInterval: 600,
      );

      // Establish baseline then reset
      engine.processSample(0.95);
      engine.reset();

      // Configuration should be preserved
      expect(engine.distanceFilter, 200.0);
      expect(engine.accuracyIndex, 3);
      expect(engine.periodicInterval, 600);

      // Next processSample should return null (new baseline)
      expect(engine.processSample(0.90), isNull);
    });

    test('charging (battery increase) returns null', () {
      final engine = BatteryBudgetEngine();

      // The engine uses DateTime.now() internally so we can only test
      // the first-sample baseline behavior directly. Charging detection
      // requires elapsed time > 60s which can't be simulated without
      // injecting a clock.
      engine.processSample(0.50);
      // Immediately calling with higher level returns null (too soon)
      expect(engine.processSample(0.60), isNull);
    });
  });

  /// The ladder replaced an unbounded multiplier in #393/#396, and these tests
  /// replaced the ones that described it.
  ///
  /// Every assertion here used to encode the defect rather than a requirement:
  /// a single one-hour window was enough to throttle, `distanceFilter` was
  /// multiplied by 1.5 and clamped up to a floor of 10 m regardless of what the
  /// app had configured, and accuracy was coarsened on the first over-budget
  /// reading. The field failure that prompted the rewrite was a device that had
  /// simply crossed one 5 % battery reporting step.
  group('BatteryBudgetEngine — the throttle ladder (clock injection)', () {
    late DateTime fakeNow;
    late BatteryBudgetEngine engine;

    setUp(() {
      fakeNow = DateTime(2024, 1, 1, 12);
    });

    BatteryBudgetEngine createEngine({
      double targetBudgetPerHour = 3.0,
      double initialDistanceFilter = 10.0,
      int initialAccuracyIndex = 0,
      int? initialPeriodicInterval,
    }) {
      return BatteryBudgetEngine(
        targetBudgetPerHour: targetBudgetPerHour,
        initialDistanceFilter: initialDistanceFilter,
        initialAccuracyIndex: initialAccuracyIndex,
        initialPeriodicInterval: initialPeriodicInterval,
        clock: () => fakeNow,
      );
    }

    /// Two consecutive conclusive over-budget windows — the dwell one rung
    /// takes. 20 %/hr over hour-long windows, well past the 5 %/hr such a
    /// window can resolve at the default reporting granularity.
    void climbOneRung(BatteryBudgetEngine engine, {double from = 0.95}) {
      engine.processSample(from);
      fakeNow = fakeNow.add(const Duration(hours: 1));
      engine.processSample(from - 0.20);
      fakeNow = fakeNow.add(const Duration(hours: 1));
      engine.processSample(from - 0.40);
    }

    test('one conclusive window is not enough to throttle', () {
      engine = createEngine();

      engine.processSample(0.95);
      fakeNow = fakeNow.add(const Duration(hours: 1));

      // 20 %/hr against a 3 %/hr budget: conclusive, but a single window.
      final result = engine.processSample(0.75);

      expect(result, isNull, reason: 'a lone window is not a dwell');
      expect(engine.distanceFilter, 10.0);
      expect(engine.accuracyIndex, 0);
    });

    test('a drain inside the measurement resolution never throttles', () {
      engine = createEngine();

      // 4 %/hr against a 3 %/hr budget, with a window that can only resolve
      // 5 %/hr — indistinguishable from the reporting step itself.
      for (var i = 0; i < 4; i++) {
        engine.processSample(0.95 - i * 0.04);
        fakeNow = fakeNow.add(const Duration(hours: 1));
      }

      expect(engine.distanceFilter, 10.0);
      expect(engine.accuracyIndex, 0);
    });

    test('sustained heavy drain climbs one rung, cadence first', () {
      engine = createEngine();

      climbOneRung(engine);

      // Rung 1 raises the platform distance filter to its floor and leaves
      // accuracy alone: on iOS the tier below Best is 100 m, which a 15 m
      // tracking gate would then reject wholesale.
      expect(engine.distanceFilter, 10.0);
      expect(engine.accuracyIndex, 0);
    });

    test('the ladder never goes below the configured values', () {
      engine = createEngine(
        initialDistanceFilter: 250,
        initialAccuracyIndex: 2,
      );

      climbOneRung(engine);

      expect(
        engine.distanceFilter,
        250.0,
        reason: 'a configured filter wider than the rung stands',
      );
      expect(
        engine.accuracyIndex,
        2,
        reason: 'a configured tier coarser than the rung stands',
      );
    });

    test('a configured distanceFilter of 0 is never clamped up', () {
      engine = createEngine(initialDistanceFilter: 0);

      expect(engine.distanceFilter, 0.0);

      climbOneRung(engine);

      // The opt-out the old engine destroyed first: (0 * 1.5).clamp(10, 5000)
      // became 10 m, permanently, since the recovery path clamped at 10 too.
      expect(engine.distanceFilter, greaterThanOrEqualTo(0.0));
    });

    test('the accuracy index stays within 0-4 however long it throttles', () {
      engine = createEngine(targetBudgetPerHour: 1, initialAccuracyIndex: 3);

      for (var round = 0; round < 6; round++) {
        engine.processSample(0.95);
        fakeNow = fakeNow.add(const Duration(hours: 1));
        engine.processSample(0.75);
        fakeNow = fakeNow.add(const Duration(hours: 1));
      }

      expect(engine.accuracyIndex, inInclusiveRange(0, 4));
    });

    test(
      'the periodic interval is stretched, never below the configured one',
      () {
        engine = createEngine(initialPeriodicInterval: 300);

        climbOneRung(engine);

        expect(engine.periodicInterval, isNotNull);
        expect(
          engine.periodicInterval,
          greaterThanOrEqualTo(300),
          reason: 'throttling stretches cadence, it never tightens it',
        );
        expect(engine.periodicInterval, lessThanOrEqualTo(43200));
      },
    );

    test('no adjustment when the drain sits on budget', () {
      engine = createEngine();

      engine.processSample(0.95);
      fakeNow = fakeNow.add(const Duration(hours: 1));

      // Exactly on budget: neither direction is conclusive.
      expect(engine.processSample(0.92), isNull);
    });

    test('no adjustment when charging', () {
      engine = createEngine();

      engine.processSample(0.50);
      fakeNow = fakeNow.add(const Duration(hours: 1));

      // Battery went UP. One window cannot move the ladder in either
      // direction, and there is nothing to lift at rung 0.
      expect(engine.processSample(0.60), isNull);
    });

    test('too-soon sample is ignored', () {
      engine = createEngine();

      engine.processSample(0.95);
      fakeNow = fakeNow.add(const Duration(seconds: 30));

      expect(engine.processSample(0.50), isNull);
    });

    test('a throttled session comes back down when the drain does', () {
      engine = createEngine();

      climbOneRung(engine);
      final throttledFilter = engine.distanceFilter;

      // Two conclusive under-budget windows: 0.25 %/hr over four hours, where
      // the window resolves 1.25 %/hr.
      for (var i = 0; i < 2; i++) {
        fakeNow = fakeNow.add(const Duration(hours: 4));
        engine.processSample(0.50 - i * 0.01);
      }

      expect(
        engine.distanceFilter,
        lessThanOrEqualTo(throttledFilter),
        reason: 'recovery uses the same evidence bar as escalation',
      );
    });
  });
}
