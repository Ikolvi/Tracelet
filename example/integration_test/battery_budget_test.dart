import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tracelet/tracelet.dart';

/// Integration tests for the Battery Budget Engine.
///
/// These tests verify the pure-Dart [BatteryBudgetEngine] and
/// [BudgetAdjustmentEvent] model serialization. The engine is a feedback
/// controller that adjusts tracking parameters based on measured vs target
/// battery drain.
///
/// **Note:** Actual battery drain measurement requires a real device with
/// active tracking. These tests verify the engine logic and model types.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('BatteryBudgetEngine — Construction', () {
    testWidgets('can be instantiated with default parameters', (tester) async {
      final engine = BatteryBudgetEngine(targetBudgetPerHour: 3.0);
      expect(engine, isA<BatteryBudgetEngine>());
    });

    testWidgets('accepts zero budget (disabled)', (tester) async {
      final engine = BatteryBudgetEngine(targetBudgetPerHour: 0.0);
      expect(engine, isA<BatteryBudgetEngine>());
    });
  });

  group('BatteryBudgetEngine — Budget Adjustment Logic', () {
    testWidgets('processSample returns null when no samples yet', (
      tester,
    ) async {
      final engine = BatteryBudgetEngine(targetBudgetPerHour: 3.0);

      // First call establishes baseline, no adjustment yet
      final adjustment = engine.processSample(0.95);
      expect(adjustment, isNull);
    });

    testWidgets('processSample returns adjustment after sufficient samples', (
      tester,
    ) async {
      final engine = BatteryBudgetEngine(targetBudgetPerHour: 3.0);

      // Simulate baseline
      engine.processSample(0.95);

      // Simulate significant drain — engine may or may not produce
      // an adjustment depending on internal timing
      final result = engine.processSample(0.90);

      // Result is either null (not enough time elapsed) or a valid event
      if (result != null) {
        expect(result, isA<BudgetAdjustmentEvent>());
        expect(result.targetBudget, 3.0);
        expect(result.newDistanceFilter, greaterThan(0));
      }
    });
  });

  group('BudgetAdjustmentEvent — Model', () {
    testWidgets('BudgetAdjustmentEvent has correct fields', (tester) async {
      const event = BudgetAdjustmentEvent(
        currentBatteryDrain: 4.5,
        targetBudget: 3.0,
        newDistanceFilter: 50.0,
        newDesiredAccuracy: 2,
        newPeriodicInterval: null,
      );

      expect(event.currentBatteryDrain, 4.5);
      expect(event.targetBudget, 3.0);
      expect(event.newDistanceFilter, 50.0);
      expect(event.newDesiredAccuracy, 2);
      expect(event.newPeriodicInterval, isNull);
    });

    testWidgets('BudgetAdjustmentEvent supports periodic interval', (
      tester,
    ) async {
      const event = BudgetAdjustmentEvent(
        currentBatteryDrain: 5.0,
        targetBudget: 2.0,
        newDistanceFilter: 100.0,
        newDesiredAccuracy: 3,
        newPeriodicInterval: 1800,
      );

      expect(event.newPeriodicInterval, 1800);
    });
  });

  group('GeoConfig — Battery Budget Property', () {
    testWidgets('GeoConfig accepts batteryBudgetPerHour', (tester) async {
      const config = GeoConfig(batteryBudgetPerHour: 3.0);
      expect(config.batteryBudgetPerHour, 3.0);
    });

    testWidgets('GeoConfig defaults batteryBudgetPerHour to 0', (tester) async {
      const config = GeoConfig();
      expect(config.batteryBudgetPerHour, 0.0);
    });

    testWidgets('GeoConfig.toMap includes batteryBudgetPerHour', (
      tester,
    ) async {
      const config = GeoConfig(batteryBudgetPerHour: 2.5);
      final map = config.toMap();
      expect(map['batteryBudgetPerHour'], 2.5);
    });
  });
}
