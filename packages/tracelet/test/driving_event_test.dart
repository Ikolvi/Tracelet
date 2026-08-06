import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet/tracelet.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

void main() {
  test('DrivingEvent.fromTl maps all fields', () {
    final e = DrivingEvent.fromTl(
      TlDrivingEvent(
        kind: 'harsh_braking',
        severity: 0.7,
        speed: 12,
        value: 0.9,
        latitude: 1,
        longitude: 2,
        timestampMs: 1000,
      ),
    );
    expect(e.kind, 'harsh_braking');
    expect(e.severity, 0.7);
    expect(e.value, 0.9);
    expect(e.timestamp.millisecondsSinceEpoch, 1000);
  });

  test('ImpactEvent.fromTl maps fields and isPotential', () {
    final pot = ImpactEvent.fromTl(
      TlImpactEvent(
        kind: 'potential_crash',
        id: 5,
        confidence: 0.8,
        peakG: 4,
        speedBefore: 16,
        latitude: 1,
        longitude: 2,
        timestampMs: 1000,
        confirmDeadlineMs: 16000,
      ),
    );
    expect(pot.isPotential, isTrue);
    expect(pot.id, 5);
    expect(pot.confirmDeadline.millisecondsSinceEpoch, 16000);

    final confirmed = ImpactEvent.fromTl(
      TlImpactEvent(
        kind: 'crash',
        id: 5,
        confidence: 0.8,
        peakG: 4,
        speedBefore: 16,
        latitude: 1,
        longitude: 2,
        timestampMs: 1000,
        confirmDeadlineMs: 1000,
      ),
    );
    expect(confirmed.isPotential, isFalse);
  });

  test('ModeChangeEvent.fromTl maps fields', () {
    final e = ModeChangeEvent.fromTl(
      TlModeChangeEvent(mode: 'vehicle', confidence: 0.95),
    );
    expect(e.mode, 'vehicle');
    expect(e.confidence, 0.95);
  });

  test('ModeChangeEvent.appliedTuning is null when auto-tuning is off (#301)', () {
    // The common case: no auto-tune, so nothing was applied and the host's own
    // thresholds are still in force.
    final e = ModeChangeEvent.fromTl(
      TlModeChangeEvent(mode: 'walking', confidence: 0.8),
    );
    expect(e.appliedTuning, isNull);
    expect(e.toString(), isNot(contains('tuned')));
  });

  test('ModeChangeEvent.fromTl surfaces the applied tuning (#301)', () {
    // The walking row of the auto-tune table, as the native SDK reports it.
    final e = ModeChangeEvent.fromTl(
      TlModeChangeEvent(
        mode: 'walking',
        confidence: 0.8,
        appliedTuning: TlLocationTuning(
          distanceFilter: 8,
          trackingAccuracyThreshold: 15,
          odometerAccuracyThreshold: 10,
          maxImpliedSpeed: 4,
        ),
      ),
    );
    expect(e.mode, 'walking');
    expect(
      e.appliedTuning,
      const LocationTuning(
        distanceFilter: 8,
        trackingAccuracyThreshold: 15,
        odometerAccuracyThreshold: 10,
        maxImpliedSpeed: 4,
      ),
    );
    // An auto-tune must be visible in a logged event, not just in the fields.
    expect(e.toString(), contains('tuned'));
  });
}
