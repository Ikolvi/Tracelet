import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

void main() {
  group('BatteryBudgetEngine', () {
    test('constructor sets defaults', () {
      final engine = BatteryBudgetEngine(targetBudgetPerHour: 3.0);

      expect(engine.targetBudgetPerHour, 3.0);
      expect(engine.distanceFilter, 10.0);
      expect(engine.accuracyIndex, 0);
      expect(engine.periodicInterval, isNull);
    });

    test('constructor accepts custom initial values', () {
      final engine = BatteryBudgetEngine(
        targetBudgetPerHour: 5.0,
        initialDistanceFilter: 50.0,
        initialAccuracyIndex: 2,
        initialPeriodicInterval: 300,
      );

      expect(engine.targetBudgetPerHour, 5.0);
      expect(engine.distanceFilter, 50.0);
      expect(engine.accuracyIndex, 2);
      expect(engine.periodicInterval, 300);
    });

    test('clamps accuracy index to 0-4 range', () {
      final tooHigh = BatteryBudgetEngine(
        targetBudgetPerHour: 3.0,
        initialAccuracyIndex: 10,
      );
      expect(tooHigh.accuracyIndex, 4);

      final tooLow = BatteryBudgetEngine(
        targetBudgetPerHour: 3.0,
        initialAccuracyIndex: -5,
      );
      expect(tooLow.accuracyIndex, 0);
    });

    test('first processSample returns null (baseline)', () {
      final engine = BatteryBudgetEngine(targetBudgetPerHour: 3.0);

      final result = engine.processSample(0.95);
      expect(result, isNull);
    });

    test('second processSample within 60s returns null', () {
      final engine = BatteryBudgetEngine(targetBudgetPerHour: 3.0);

      // First call sets baseline
      engine.processSample(0.95);

      // Immediate second call — too soon (< 60 seconds)
      final result = engine.processSample(0.90);
      expect(result, isNull);
    });

    test('reset allows re-establishing baseline', () {
      final engine = BatteryBudgetEngine(targetBudgetPerHour: 3.0);

      engine.processSample(0.95);
      engine.reset();

      // After reset, next call should return null (new baseline)
      final result = engine.processSample(0.90);
      expect(result, isNull);
    });

    test('reset does not change configuration', () {
      final engine = BatteryBudgetEngine(
        targetBudgetPerHour: 5.0,
        initialDistanceFilter: 50.0,
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
        targetBudget: 3.0,
        newDistanceFilter: 50.0,
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
        currentBatteryDrain: 2.0,
        targetBudget: 3.0,
        newDistanceFilter: 10.0,
        newDesiredAccuracy: 0,
      );

      expect(event.newPeriodicInterval, isNull);
    });

    test('toString produces readable output', () {
      const event = BudgetAdjustmentEvent(
        currentBatteryDrain: 4.5,
        targetBudget: 3.0,
        newDistanceFilter: 50.0,
        newDesiredAccuracy: 2,
      );

      final s = event.toString();
      expect(s, contains('4.50%/hr'));
      expect(s, contains('3.00%/hr'));
      expect(s, contains('50.0'));
      expect(s, contains('accuracy=2'));
    });
  });

  group('BatteryBudgetEngine — internal state', () {
    test('initial distanceFilter matches constructor param', () {
      final engine = BatteryBudgetEngine(
        targetBudgetPerHour: 3.0,
        initialDistanceFilter: 100.0,
      );
      expect(engine.distanceFilter, 100.0);
    });

    test('initial periodicInterval matches constructor param', () {
      final engine = BatteryBudgetEngine(
        targetBudgetPerHour: 3.0,
        initialPeriodicInterval: 300,
      );
      expect(engine.periodicInterval, 300);
    });

    test('periodicInterval is null when not provided', () {
      final engine = BatteryBudgetEngine(targetBudgetPerHour: 3.0);
      expect(engine.periodicInterval, isNull);
    });

    test('accuracy index clamped to minimum 0', () {
      final engine = BatteryBudgetEngine(
        targetBudgetPerHour: 3.0,
        initialAccuracyIndex: -100,
      );
      expect(engine.accuracyIndex, 0);
    });

    test('accuracy index clamped to maximum 4', () {
      final engine = BatteryBudgetEngine(
        targetBudgetPerHour: 3.0,
        initialAccuracyIndex: 100,
      );
      expect(engine.accuracyIndex, 4);
    });

    test('reset preserves distance filter and accuracy', () {
      final engine = BatteryBudgetEngine(
        targetBudgetPerHour: 5.0,
        initialDistanceFilter: 200.0,
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
      final engine = BatteryBudgetEngine(targetBudgetPerHour: 3.0);

      // The engine uses DateTime.now() internally so we can only test
      // the first-sample baseline behavior directly. Charging detection
      // requires elapsed time > 60s which can't be simulated without
      // injecting a clock.
      engine.processSample(0.50);
      // Immediately calling with higher level returns null (too soon)
      expect(engine.processSample(0.60), isNull);
    });
  });

  group('BatteryBudgetEngine — time-dependent (clock injection)', () {
    late DateTime fakeNow;
    late BatteryBudgetEngine engine;

    setUp(() {
      fakeNow = DateTime(2024, 1, 1, 12, 0, 0);
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

    test('throttles when draining too fast', () {
      engine = createEngine(targetBudgetPerHour: 3.0);

      // Baseline at 95%
      engine.processSample(0.95);

      // Advance 1 hour
      fakeNow = fakeNow.add(const Duration(hours: 1));

      // Battery dropped to 85% → 10% drain/hr >> 3% budget
      final result = engine.processSample(0.85);

      expect(result, isNotNull);
      expect(result!.currentBatteryDrain, closeTo(10.0, 0.1));
      expect(result.targetBudget, 3.0);
      // Distance filter should increase (10 * 1.5 = 15)
      expect(engine.distanceFilter, closeTo(15.0, 0.1));
      // Accuracy should degrade (0 → 1)
      expect(engine.accuracyIndex, 1);
    });

    test('boosts when under budget', () {
      engine = createEngine(
        targetBudgetPerHour: 10.0,
        initialDistanceFilter: 100.0,
        initialAccuracyIndex: 3,
      );

      // Baseline at 95%
      engine.processSample(0.95);

      // Advance 1 hour
      fakeNow = fakeNow.add(const Duration(hours: 1));

      // Battery dropped to 94% → 1% drain/hr << 10% budget
      final result = engine.processSample(0.94);

      expect(result, isNotNull);
      expect(result!.currentBatteryDrain, closeTo(1.0, 0.1));
      // Distance filter should decrease (100 * 0.8 = 80)
      expect(engine.distanceFilter, closeTo(80.0, 0.1));
      // Accuracy should improve (3 → 2)
      expect(engine.accuracyIndex, 2);
    });

    test('no adjustment when within error threshold', () {
      engine = createEngine(targetBudgetPerHour: 3.0);

      // Baseline at 95%
      engine.processSample(0.95);

      // Advance 1 hour
      fakeNow = fakeNow.add(const Duration(hours: 1));

      // Battery dropped to 92% → 3% drain/hr == exactly on budget
      final result = engine.processSample(0.92);

      // Error = 3.0 - 3.0 = 0.0 < 0.5 threshold → no adjustment
      expect(result, isNull);
    });

    test('no adjustment when charging', () {
      engine = createEngine(targetBudgetPerHour: 3.0);

      engine.processSample(0.50);

      fakeNow = fakeNow.add(const Duration(hours: 1));

      // Battery went UP (charging)
      final result = engine.processSample(0.60);
      expect(result, isNull);
    });

    test('too-soon sample is ignored', () {
      engine = createEngine(targetBudgetPerHour: 3.0);

      engine.processSample(0.95);

      // Only 30 seconds later — too soon
      fakeNow = fakeNow.add(const Duration(seconds: 30));

      final result = engine.processSample(0.50);
      expect(result, isNull);
    });

    test('throttles periodic interval when draining fast', () {
      engine = createEngine(
        targetBudgetPerHour: 3.0,
        initialPeriodicInterval: 300,
      );

      engine.processSample(0.95);
      fakeNow = fakeNow.add(const Duration(hours: 1));

      // 10% drain/hr >> 3% budget
      final result = engine.processSample(0.85);

      expect(result, isNotNull);
      // 300 * 1.5 = 450
      expect(engine.periodicInterval, 450);
    });

    test('boosts periodic interval when under budget', () {
      engine = createEngine(
        targetBudgetPerHour: 10.0,
        initialPeriodicInterval: 300,
      );

      engine.processSample(0.95);
      fakeNow = fakeNow.add(const Duration(hours: 1));

      // 1% drain/hr << 10% budget
      final result = engine.processSample(0.94);

      expect(result, isNotNull);
      // 300 * 0.8 = 240
      expect(engine.periodicInterval, 240);
    });

    test('accuracy index does not exceed 4 on repeated throttling', () {
      engine = createEngine(targetBudgetPerHour: 1.0, initialAccuracyIndex: 3);

      engine.processSample(0.95);
      fakeNow = fakeNow.add(const Duration(hours: 1));
      engine.processSample(0.85); // accuracy 3 → 4

      expect(engine.accuracyIndex, 4);

      // Throttle again — accuracy already at max
      fakeNow = fakeNow.add(const Duration(hours: 1));
      engine.processSample(0.75);
      expect(engine.accuracyIndex, 4);
    });

    test('accuracy index does not go below 0 on repeated boosting', () {
      engine = createEngine(targetBudgetPerHour: 50.0, initialAccuracyIndex: 1);

      engine.processSample(0.95);
      fakeNow = fakeNow.add(const Duration(hours: 1));
      engine.processSample(0.94); // accuracy 1 → 0

      expect(engine.accuracyIndex, 0);

      fakeNow = fakeNow.add(const Duration(hours: 1));
      engine.processSample(0.93);
      expect(engine.accuracyIndex, 0);
    });

    test('distance filter clamped to min on aggressive boosting', () {
      engine = createEngine(
        targetBudgetPerHour: 50.0,
        initialDistanceFilter: 11.0,
      );

      engine.processSample(0.95);
      fakeNow = fakeNow.add(const Duration(hours: 1));
      engine.processSample(0.94);

      // 11 * 0.8 = 8.8 → clamped to 10.0
      expect(engine.distanceFilter, 10.0);
    });

    test('distance filter clamped to max on aggressive throttling', () {
      engine = createEngine(
        targetBudgetPerHour: 0.1,
        initialDistanceFilter: 4000.0,
      );

      engine.processSample(0.95);
      fakeNow = fakeNow.add(const Duration(hours: 1));
      engine.processSample(0.85);

      // 4000 * 1.5 = 6000 → clamped to 5000
      expect(engine.distanceFilter, 5000.0);
    });

    test('periodic interval clamped to min 60 on boosting', () {
      engine = createEngine(
        targetBudgetPerHour: 50.0,
        initialPeriodicInterval: 65,
      );

      engine.processSample(0.95);
      fakeNow = fakeNow.add(const Duration(hours: 1));
      engine.processSample(0.94);

      // 65 * 0.8 = 52 → clamped to 60
      expect(engine.periodicInterval, 60);
    });

    test('periodic interval clamped to max 43200 on throttling', () {
      engine = createEngine(
        targetBudgetPerHour: 0.1,
        initialPeriodicInterval: 40000,
      );

      engine.processSample(0.95);
      fakeNow = fakeNow.add(const Duration(hours: 1));
      engine.processSample(0.85);

      // 40000 * 1.5 = 60000 → clamped to 43200
      expect(engine.periodicInterval, 43200);
    });

    test('multiple successive adjustments accumulate', () {
      engine = createEngine(
        targetBudgetPerHour: 1.0,
        initialDistanceFilter: 10.0,
        initialAccuracyIndex: 0,
      );

      // Round 1: heavy drain
      engine.processSample(0.95);
      fakeNow = fakeNow.add(const Duration(hours: 1));
      engine.processSample(0.85);

      expect(engine.distanceFilter, closeTo(15.0, 0.1)); // 10 * 1.5
      expect(engine.accuracyIndex, 1);

      // Round 2: still draining heavy
      fakeNow = fakeNow.add(const Duration(hours: 1));
      engine.processSample(0.75);

      expect(engine.distanceFilter, closeTo(22.5, 0.1)); // 15 * 1.5
      expect(engine.accuracyIndex, 2);
    });
  });
}
