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
}
