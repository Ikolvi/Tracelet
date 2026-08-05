import 'package:meta/meta.dart';
import 'package:tracelet/src/models/_helpers.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

// ---------------------------------------------------------------------------
// TelematicsConfig (driving-behavior events)
// ---------------------------------------------------------------------------

/// Driving-behavior (telematics) event detection.
///
/// When [enableDrivingEvents] is `true`, Tracelet scores the location stream
/// into `harsh_braking`, `harsh_acceleration`, `harsh_cornering`, and
/// `speeding` events (delivered via `Tracelet.onDrivingEvent`) plus a per-trip
/// driving score. Thresholds are in **g** (1 g ≈ 9.81 m/s²) and follow common
/// usage-based-insurance practice; all are tunable.
///
/// Default: **disabled** — zero behavior change when off.
@immutable
class TelematicsConfig {
  /// Creates a new [TelematicsConfig].
  const TelematicsConfig({
    this.enableDrivingEvents = false,
    this.harshBrakingG = 0.40,
    this.harshAccelerationG = 0.35,
    this.harshCorneringG = 0.40,
    this.speedLimitKmh = 0.0,
    this.speedingToleranceKmh = 5.0,
    this.speedingMinDurationMs = 3000,
    this.minSpeedForEventsKmh = 5.0,
    this.eventDebounceMs = 2000,
  });

  /// Creates a [TelematicsConfig] from a map.
  factory TelematicsConfig.fromMap(Map<String, Object?> map) {
    return TelematicsConfig(
      enableDrivingEvents: ensureBool(
        map['enableDrivingEvents'],
        fallback: false,
      ),
      harshBrakingG: ensureDouble(map['harshBrakingG'], fallback: 0.40),
      harshAccelerationG: ensureDouble(
        map['harshAccelerationG'],
        fallback: 0.35,
      ),
      harshCorneringG: ensureDouble(map['harshCorneringG'], fallback: 0.40),
      speedLimitKmh: ensureDouble(map['speedLimitKmh'], fallback: 0),
      speedingToleranceKmh: ensureDouble(
        map['speedingToleranceKmh'],
        fallback: 5,
      ),
      speedingMinDurationMs: ensureInt(
        map['speedingMinDurationMs'],
        fallback: 3000,
      ),
      minSpeedForEventsKmh: ensureDouble(
        map['minSpeedForEventsKmh'],
        fallback: 5,
      ),
      eventDebounceMs: ensureInt(map['eventDebounceMs'], fallback: 2000),
    );
  }

  /// Master switch. When `false` the telematics engine is never created.
  final bool enableDrivingEvents;

  /// Deceleration (g) above which `harsh_braking` fires. Default `0.40`.
  final double harshBrakingG;

  /// Acceleration (g) above which `harsh_acceleration` fires. Default `0.35`.
  final double harshAccelerationG;

  /// Lateral acceleration (g) above which `harsh_cornering` fires. Default `0.40`.
  final double harshCorneringG;

  /// Global speed limit (km/h); `0` disables threshold-based speeding. Default `0`.
  final double speedLimitKmh;

  /// Grace over the limit (km/h) before speeding counts. Default `5`.
  final double speedingToleranceKmh;

  /// Sustained time over the limit (ms) before `speeding` fires. Default `3000`.
  final int speedingMinDurationMs;

  /// Suppress brake/accel/corner events below this speed (km/h). Default `5`.
  final double minSpeedForEventsKmh;

  /// Minimum time between same-kind events (ms). Default `2000`.
  final int eventDebounceMs;

  /// Serializes to a map.
  Map<String, Object?> toMap() => <String, Object?>{
    'enableDrivingEvents': enableDrivingEvents,
    'harshBrakingG': harshBrakingG,
    'harshAccelerationG': harshAccelerationG,
    'harshCorneringG': harshCorneringG,
    'speedLimitKmh': speedLimitKmh,
    'speedingToleranceKmh': speedingToleranceKmh,
    'speedingMinDurationMs': speedingMinDurationMs,
    'minSpeedForEventsKmh': minSpeedForEventsKmh,
    'eventDebounceMs': eventDebounceMs,
  };

  /// Converts to Pigeon [TlTelematicsConfig].
  TlTelematicsConfig toTlConfig() => TlTelematicsConfig(
    enableDrivingEvents: enableDrivingEvents,
    harshBrakingG: harshBrakingG,
    harshAccelerationG: harshAccelerationG,
    harshCorneringG: harshCorneringG,
    speedLimitKmh: speedLimitKmh,
    speedingToleranceKmh: speedingToleranceKmh,
    speedingMinDurationMs: speedingMinDurationMs,
    minSpeedForEventsKmh: minSpeedForEventsKmh,
    eventDebounceMs: eventDebounceMs,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TelematicsConfig &&
          runtimeType == other.runtimeType &&
          enableDrivingEvents == other.enableDrivingEvents &&
          harshBrakingG == other.harshBrakingG &&
          harshAccelerationG == other.harshAccelerationG &&
          harshCorneringG == other.harshCorneringG &&
          speedLimitKmh == other.speedLimitKmh &&
          speedingToleranceKmh == other.speedingToleranceKmh &&
          speedingMinDurationMs == other.speedingMinDurationMs &&
          minSpeedForEventsKmh == other.minSpeedForEventsKmh &&
          eventDebounceMs == other.eventDebounceMs;

  @override
  int get hashCode => Object.hash(
    enableDrivingEvents,
    harshBrakingG,
    harshAccelerationG,
    harshCorneringG,
    speedLimitKmh,
    speedingToleranceKmh,
    speedingMinDurationMs,
    minSpeedForEventsKmh,
    eventDebounceMs,
  );
}

// ---------------------------------------------------------------------------
// ClassifierConfig (on-device transport-mode classifier)
// ---------------------------------------------------------------------------

/// On-device transport-mode classifier (fused accelerometer + GPS speed).
///
/// When [enableFusedClassifier] is `true`, Tracelet emits a fused travel mode
/// (`still`/`walking`/`running`/`cycling`/`vehicle`) with confidence via
/// `Tracelet.onModeChange`. By default it **annotates** (the platform Activity
/// Recognition value stays authoritative) unless [fusedClassifierAuthoritative].
///
/// Default: **disabled**.
@immutable
class ClassifierConfig {
  /// Creates a new [ClassifierConfig].
  const ClassifierConfig({
    this.enableFusedClassifier = false,
    this.fusedClassifierAuthoritative = false,
    this.modeSwitchDwellMs = 8000,
    this.minModeConfidence = 0.6,
    this.autoTuneFromTransportMode = false,
  });

  /// Creates a [ClassifierConfig] from a map.
  factory ClassifierConfig.fromMap(Map<String, Object?> map) {
    return ClassifierConfig(
      enableFusedClassifier: ensureBool(
        map['enableFusedClassifier'],
        fallback: false,
      ),
      fusedClassifierAuthoritative: ensureBool(
        map['fusedClassifierAuthoritative'],
        fallback: false,
      ),
      modeSwitchDwellMs: ensureInt(map['modeSwitchDwellMs'], fallback: 8000),
      minModeConfidence: ensureDouble(map['minModeConfidence'], fallback: 0.6),
      autoTuneFromTransportMode: ensureBool(
        map['autoTuneFromTransportMode'],
        fallback: false,
      ),
    );
  }

  /// Master switch. When `false` the classifier and accel feed never start.
  final bool enableFusedClassifier;

  /// If `true`, the fused mode overrides the platform activity for sampling.
  final bool fusedClassifierAuthoritative;

  /// Dwell (ms) a candidate mode must persist before committing. Default `8000`.
  final int modeSwitchDwellMs;

  /// Below this confidence the mode is reported as `unknown`. Default `0.6`.
  final double minModeConfidence;

  /// Whether a committed transport mode retunes the location filter thresholds.
  ///
  /// When `true`, committing a mode swaps `distanceFilter`,
  /// `trackingAccuracyThreshold`, `odometerAccuracyThreshold` and
  /// `maxImpliedSpeed` for values suited to that mode — tighter on foot, looser
  /// in a vehicle — which is what keeps distance from inflating while walking.
  /// Retuning happens only on a *committed* change (confidence-gated and
  /// debounced by [modeSwitchDwellMs]), and a mode of `unknown` restores the
  /// values you configured. The applied thresholds are reported on
  /// `onModeChange` so an auto-tune is never silent.
  ///
  /// Requires [enableFusedClassifier]. Defaults to `false`, so existing
  /// integrations keep the thresholds they set.
  final bool autoTuneFromTransportMode;

  /// Serializes to a map.
  Map<String, Object?> toMap() => <String, Object?>{
    'enableFusedClassifier': enableFusedClassifier,
    'fusedClassifierAuthoritative': fusedClassifierAuthoritative,
    'modeSwitchDwellMs': modeSwitchDwellMs,
    'minModeConfidence': minModeConfidence,
    'autoTuneFromTransportMode': autoTuneFromTransportMode,
  };

  /// Converts to Pigeon [TlClassifierConfig].
  TlClassifierConfig toTlConfig() => TlClassifierConfig(
    enableFusedClassifier: enableFusedClassifier,
    fusedClassifierAuthoritative: fusedClassifierAuthoritative,
    modeSwitchDwellMs: modeSwitchDwellMs,
    minModeConfidence: minModeConfidence,
    autoTuneFromTransportMode: autoTuneFromTransportMode,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClassifierConfig &&
          runtimeType == other.runtimeType &&
          enableFusedClassifier == other.enableFusedClassifier &&
          fusedClassifierAuthoritative == other.fusedClassifierAuthoritative &&
          modeSwitchDwellMs == other.modeSwitchDwellMs &&
          minModeConfidence == other.minModeConfidence &&
          autoTuneFromTransportMode == other.autoTuneFromTransportMode;

  @override
  int get hashCode => Object.hash(
    enableFusedClassifier,
    fusedClassifierAuthoritative,
    modeSwitchDwellMs,
    minModeConfidence,
    autoTuneFromTransportMode,
  );
}

// ---------------------------------------------------------------------------
// ImpactConfig (crash & fall detection)
// ---------------------------------------------------------------------------

/// Crash & fall detection.
///
/// When [enableCrashDetection] is `true`, a corroborated high-g impact while
/// moving raises a `potential_crash` (with a [confirmWindowMs] cancel
/// countdown) that auto-confirms to `crash` unless cancelled — delivered via
/// `Tracelet.onImpact`. [enableFallDetection] adds best-effort personal-fall
/// detection (more false positives; default off).
///
/// Default: **disabled**. Tracelet provides the trigger + cancel window; it
/// never places emergency calls.
@immutable
class ImpactConfig {
  /// Creates a new [ImpactConfig].
  const ImpactConfig({
    this.enableCrashDetection = false,
    this.enableFallDetection = false,
    this.crashGThreshold = 2.0,
    this.crashMinSpeedKmh = 25.0,
    this.fallGThreshold = 2.5,
    this.confirmWindowMs = 15000,
    this.minImpactConfidence = 0.6,
    this.crashModelUrl,
    this.crashModelSha256,
    this.crashModelThreshold = 0.5,
    this.crashModelUnlockUrl,
    this.crashModelLicenseKey,
  });

  /// Creates an [ImpactConfig] from a map.
  factory ImpactConfig.fromMap(Map<String, Object?> map) {
    return ImpactConfig(
      enableCrashDetection: ensureBool(
        map['enableCrashDetection'],
        fallback: false,
      ),
      enableFallDetection: ensureBool(
        map['enableFallDetection'],
        fallback: false,
      ),
      crashGThreshold: ensureDouble(map['crashGThreshold'], fallback: 2),
      crashMinSpeedKmh: ensureDouble(map['crashMinSpeedKmh'], fallback: 25),
      fallGThreshold: ensureDouble(map['fallGThreshold'], fallback: 2.5),
      confirmWindowMs: ensureInt(map['confirmWindowMs'], fallback: 15000),
      minImpactConfidence: ensureDouble(
        map['minImpactConfidence'],
        fallback: 0.6,
      ),
      crashModelUrl: map['crashModelUrl'] as String?,
      crashModelSha256: map['crashModelSha256'] as String?,
      crashModelThreshold: ensureDouble(
        map['crashModelThreshold'],
        fallback: 0.5,
      ),
      crashModelUnlockUrl: map['crashModelUnlockUrl'] as String?,
      crashModelLicenseKey: map['crashModelLicenseKey'] as String?,
    );
  }

  /// Master switch for vehicle crash detection.
  final bool enableCrashDetection;

  /// Personal fall detection (best-effort; default `false`).
  final bool enableFallDetection;

  /// Impact magnitude (g) for a crash candidate. Default `2.0` (lowered from 3.0
  /// after a field-data study found 3.0 g missed ~half of real crashes; the
  /// cancel-countdown offsets the extra false alarms).
  final double crashGThreshold;

  /// Pre-impact speed (km/h) required to corroborate a crash. Default `25`.
  final double crashMinSpeedKmh;

  /// Impact magnitude (g) for a fall candidate. Default `2.5`.
  final double fallGThreshold;

  /// Countdown (ms) before a candidate auto-confirms. Default `15000`.
  final int confirmWindowMs;

  /// Suppress candidates below this confidence. Default `0.6`.
  final double minImpactConfidence;

  /// Optional URL of an **AES-256-GCM encrypted** crash ML model (the portable
  /// random-forest JSON). When set (and crash detection is enabled), the SDK
  /// downloads it once, verifies [crashModelSha256], decrypts and runs it to
  /// score impacts; it falls back to the rule engine if absent/offline. The
  /// model is opt-in and downloaded — never embedded — so the base SDK size is
  /// unchanged. `null` ⇒ pure rule engine (default). The decryption key is
  /// supplied by the host at build/run time, never via this config.
  final String? crashModelUrl;

  /// Optional SHA-256 (hex) of the encrypted model blob for integrity
  /// verification after download. Recommended whenever [crashModelUrl] is set.
  final String? crashModelSha256;

  /// Probability threshold (`0..1`) at which the ML model flags a crash. Default
  /// `0.5`. Use the `rf_probability_threshold` from the model's training report.
  final double crashModelThreshold;

  /// Optional licensing **unlock endpoint** (e.g. a Cloudflare Worker). When set
  /// with [crashModelLicenseKey], the SDK POSTs the license to this URL to fetch
  /// the decryption key + model URL at runtime, instead of the host injecting the
  /// key manually. The key is held in memory only. `null` ⇒ no auto-unlock.
  final String? crashModelUnlockUrl;

  /// Customer license key presented to [crashModelUnlockUrl]. Bound to your app
  /// (package/bundle id) and signed by you; never grants access on its own — the
  /// endpoint validates it before returning the key.
  final String? crashModelLicenseKey;

  /// Serializes to a map.
  Map<String, Object?> toMap() => <String, Object?>{
    'enableCrashDetection': enableCrashDetection,
    'enableFallDetection': enableFallDetection,
    'crashGThreshold': crashGThreshold,
    'crashMinSpeedKmh': crashMinSpeedKmh,
    'fallGThreshold': fallGThreshold,
    'confirmWindowMs': confirmWindowMs,
    'minImpactConfidence': minImpactConfidence,
    'crashModelUrl': crashModelUrl,
    'crashModelSha256': crashModelSha256,
    'crashModelThreshold': crashModelThreshold,
    'crashModelUnlockUrl': crashModelUnlockUrl,
    'crashModelLicenseKey': crashModelLicenseKey,
  };

  /// Converts to Pigeon [TlImpactConfig].
  TlImpactConfig toTlConfig() => TlImpactConfig(
    enableCrashDetection: enableCrashDetection,
    enableFallDetection: enableFallDetection,
    crashGThreshold: crashGThreshold,
    crashMinSpeedKmh: crashMinSpeedKmh,
    fallGThreshold: fallGThreshold,
    confirmWindowMs: confirmWindowMs,
    minImpactConfidence: minImpactConfidence,
    crashModelUrl: crashModelUrl,
    crashModelSha256: crashModelSha256,
    crashModelThreshold: crashModelThreshold,
    crashModelUnlockUrl: crashModelUnlockUrl,
    crashModelLicenseKey: crashModelLicenseKey,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImpactConfig &&
          runtimeType == other.runtimeType &&
          enableCrashDetection == other.enableCrashDetection &&
          enableFallDetection == other.enableFallDetection &&
          crashGThreshold == other.crashGThreshold &&
          crashMinSpeedKmh == other.crashMinSpeedKmh &&
          fallGThreshold == other.fallGThreshold &&
          confirmWindowMs == other.confirmWindowMs &&
          minImpactConfidence == other.minImpactConfidence &&
          crashModelUrl == other.crashModelUrl &&
          crashModelSha256 == other.crashModelSha256 &&
          crashModelThreshold == other.crashModelThreshold &&
          crashModelUnlockUrl == other.crashModelUnlockUrl &&
          crashModelLicenseKey == other.crashModelLicenseKey;

  @override
  int get hashCode => Object.hash(
    enableCrashDetection,
    enableFallDetection,
    crashGThreshold,
    crashMinSpeedKmh,
    fallGThreshold,
    confirmWindowMs,
    minImpactConfidence,
    crashModelUrl,
    crashModelSha256,
    crashModelThreshold,
    crashModelUnlockUrl,
    crashModelLicenseKey,
  );
}
