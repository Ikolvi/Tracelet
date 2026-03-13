import '../types/enums.dart';

/// Event emitted when the battery budget engine adjusts tracking parameters.
class BudgetAdjustmentEvent {
  /// Creates a [BudgetAdjustmentEvent].
  const BudgetAdjustmentEvent({
    required this.currentBatteryDrain,
    required this.targetBudget,
    required this.newDistanceFilter,
    required this.newDesiredAccuracy,
    this.newPeriodicInterval,
  });

  /// Estimated current battery drain in %/hr.
  final double currentBatteryDrain;

  /// Configured budget target in %/hr.
  final double targetBudget;

  /// Adjusted distance filter (meters).
  final double newDistanceFilter;

  /// Adjusted desired accuracy level index.
  final int newDesiredAccuracy;

  /// Adjusted periodic interval (null if not in periodic mode).
  final int? newPeriodicInterval;

  @override
  String toString() =>
      'BudgetAdjustmentEvent(drain=${currentBatteryDrain.toStringAsFixed(2)}%/hr, '
      'target=${targetBudget.toStringAsFixed(2)}%/hr, '
      'distanceFilter=$newDistanceFilter, '
      'accuracy=$newDesiredAccuracy)';
}

/// Pure-Dart battery budget engine.
///
/// Given a target maximum battery consumption per hour (% points), this
/// engine monitors actual battery drain and auto-adjusts `distanceFilter`,
/// `desiredAccuracy`, and (for periodic mode) the polling interval to stay
/// within the budget.
///
/// **Control loop** (called every sampling window):
/// 1. Compute actual drain over the window, normalize to %/hr.
/// 2. Compare to target budget.
/// 3. If draining too fast: increase distanceFilter, degrade accuracy.
/// 4. If under budget: decrease distanceFilter, improve accuracy.
/// 5. Clamp values to sane ranges.
///
/// Accuracy levels (ordered by battery cost, index 0 = highest):
/// `high (0) → medium (1) → low (2) → veryLow (3) → passive (4)`
class BatteryBudgetEngine {
  /// Creates a new [BatteryBudgetEngine].
  ///
  /// [targetBudgetPerHour] is the maximum allowed battery drain in %/hr.
  /// [initialDistanceFilter] is the starting distance filter in meters.
  /// [initialAccuracyIndex] maps to [DesiredAccuracy] enum index.
  BatteryBudgetEngine({
    required this.targetBudgetPerHour,
    double initialDistanceFilter = 10.0,
    int initialAccuracyIndex = 0,
    int? initialPeriodicInterval,
  }) : _distanceFilter = initialDistanceFilter,
       _accuracyIndex = initialAccuracyIndex.clamp(0, 4),
       _periodicInterval = initialPeriodicInterval;

  /// Target maximum battery drain per hour (% points).
  final double targetBudgetPerHour;

  /// Error threshold before adjustments are made (% points/hr).
  static const double _errorThreshold = 0.5;

  /// Minimum allowed distance filter (meters).
  static const double _minDistanceFilter = 10.0;

  /// Maximum allowed distance filter (meters).
  static const double _maxDistanceFilter = 5000.0;

  /// Throttle factor when draining too fast.
  static const double _throttleFactor = 1.5;

  /// Boost factor when under budget.
  static const double _boostFactor = 0.8;

  // Internal state.
  double _distanceFilter;
  int _accuracyIndex;
  int? _periodicInterval;
  double? _prevBatteryLevel;
  DateTime? _prevSampleTime;

  /// Current adjusted distance filter.
  double get distanceFilter => _distanceFilter;

  /// Current adjusted accuracy index (0=high, 4=passive).
  int get accuracyIndex => _accuracyIndex;

  /// Current adjusted periodic interval (null if not periodic).
  int? get periodicInterval => _periodicInterval;

  /// Process a new battery sample and return an adjustment if needed.
  ///
  /// Call this periodically (every 5 minutes is recommended).
  /// Returns a [BudgetAdjustmentEvent] if parameters were adjusted,
  /// or `null` if no change was needed.
  ///
  /// [batteryLevel] is 0.0–1.0 (percentage as fraction).
  BudgetAdjustmentEvent? processSample(double batteryLevel) {
    final now = DateTime.now();

    if (_prevBatteryLevel == null || _prevSampleTime == null) {
      _prevBatteryLevel = batteryLevel;
      _prevSampleTime = now;
      return null;
    }

    final elapsed = now.difference(_prevSampleTime!).inSeconds;
    if (elapsed < 60) return null; // Too soon for meaningful measurement.

    // Compute actual drain normalized to %/hr.
    // Battery level is 0.0–1.0, convert to percentage.
    final drain = (_prevBatteryLevel! - batteryLevel) * 100.0;
    final drainPerHour = drain * (3600.0 / elapsed);

    _prevBatteryLevel = batteryLevel;
    _prevSampleTime = now;

    // Charging — no adjustment needed.
    if (drainPerHour <= 0) return null;

    final error = drainPerHour - targetBudgetPerHour;

    if (error.abs() < _errorThreshold) return null; // Within budget tolerance.

    bool adjusted = false;

    if (error > 0) {
      // Draining too fast — throttle.
      _distanceFilter = (_distanceFilter * _throttleFactor).clamp(
        _minDistanceFilter,
        _maxDistanceFilter,
      );
      if (_accuracyIndex < 4) {
        _accuracyIndex++;
        adjusted = true;
      }
      if (_periodicInterval != null) {
        _periodicInterval = ((_periodicInterval! * _throttleFactor).round())
            .clamp(60, 43200);
      }
      adjusted = true;
    } else {
      // Under budget — can improve.
      _distanceFilter = (_distanceFilter * _boostFactor).clamp(
        _minDistanceFilter,
        _maxDistanceFilter,
      );
      if (_accuracyIndex > 0) {
        _accuracyIndex--;
        adjusted = true;
      }
      if (_periodicInterval != null) {
        _periodicInterval = ((_periodicInterval! * _boostFactor).round()).clamp(
          60,
          43200,
        );
      }
      adjusted = true;
    }

    if (!adjusted) return null;

    return BudgetAdjustmentEvent(
      currentBatteryDrain: drainPerHour,
      targetBudget: targetBudgetPerHour,
      newDistanceFilter: _distanceFilter,
      newDesiredAccuracy: _accuracyIndex,
      newPeriodicInterval: _periodicInterval,
    );
  }

  /// Reset the engine state. Call when tracking restarts.
  void reset() {
    _prevBatteryLevel = null;
    _prevSampleTime = null;
  }
}
