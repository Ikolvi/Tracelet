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
    bool? enableDrivingEvents,
    double? harshBrakingG,
    double? harshAccelerationG,
    double? harshCorneringG,
    double? speedLimitKmh,
    double? speedingToleranceKmh,
    int? speedingMinDurationMs,
    double? minSpeedForEventsKmh,
    int? eventDebounceMs,
  }) : _enableDrivingEvents = enableDrivingEvents,
       _harshBrakingG = harshBrakingG,
       _harshAccelerationG = harshAccelerationG,
       _harshCorneringG = harshCorneringG,
       _speedLimitKmh = speedLimitKmh,
       _speedingToleranceKmh = speedingToleranceKmh,
       _speedingMinDurationMs = speedingMinDurationMs,
       _minSpeedForEventsKmh = minSpeedForEventsKmh,
       _eventDebounceMs = eventDebounceMs;

  /// Creates a [TelematicsConfig] from a map.
  factory TelematicsConfig.fromMap(Map<String, Object?> map) {
    return TelematicsConfig(
      enableDrivingEvents: map.containsKey('enableDrivingEvents')
          ? ensureBool(map['enableDrivingEvents'], fallback: false)
          : null,
      harshBrakingG: map.containsKey('harshBrakingG')
          ? ensureDouble(map['harshBrakingG'], fallback: 0.40)
          : null,
      harshAccelerationG: map.containsKey('harshAccelerationG')
          ? ensureDouble(map['harshAccelerationG'], fallback: 0.35)
          : null,
      harshCorneringG: map.containsKey('harshCorneringG')
          ? ensureDouble(map['harshCorneringG'], fallback: 0.40)
          : null,
      speedLimitKmh: map.containsKey('speedLimitKmh')
          ? ensureDouble(map['speedLimitKmh'], fallback: 0)
          : null,
      speedingToleranceKmh: map.containsKey('speedingToleranceKmh')
          ? ensureDouble(map['speedingToleranceKmh'], fallback: 5)
          : null,
      speedingMinDurationMs: map.containsKey('speedingMinDurationMs')
          ? ensureInt(map['speedingMinDurationMs'], fallback: 3000)
          : null,
      minSpeedForEventsKmh: map.containsKey('minSpeedForEventsKmh')
          ? ensureDouble(map['minSpeedForEventsKmh'], fallback: 5)
          : null,
      eventDebounceMs: map.containsKey('eventDebounceMs')
          ? ensureInt(map['eventDebounceMs'], fallback: 2000)
          : null,
    );
  }

  // Backing fields. `null` means "the caller did not provide this",
  // which keeps the field out of the wire payload (#321). The getters
  // below resolve each one to its documented default.
  final bool? _enableDrivingEvents;
  final double? _harshBrakingG;
  final double? _harshAccelerationG;
  final double? _harshCorneringG;
  final double? _speedLimitKmh;
  final double? _speedingToleranceKmh;
  final int? _speedingMinDurationMs;
  final double? _minSpeedForEventsKmh;
  final int? _eventDebounceMs;

  /// Master switch. When `false` the telematics engine is never created.
  bool get enableDrivingEvents => _enableDrivingEvents ?? false;

  /// Deceleration (g) above which `harsh_braking` fires. Default `0.40`.
  double get harshBrakingG => _harshBrakingG ?? 0.40;

  /// Acceleration (g) above which `harsh_acceleration` fires. Default `0.35`.
  double get harshAccelerationG => _harshAccelerationG ?? 0.35;

  /// Lateral acceleration (g) above which `harsh_cornering` fires. Default `0.40`.
  double get harshCorneringG => _harshCorneringG ?? 0.40;

  /// Global speed limit (km/h); `0` disables threshold-based speeding. Default `0`.
  double get speedLimitKmh => _speedLimitKmh ?? 0.0;

  /// Grace over the limit (km/h) before speeding counts. Default `5`.
  double get speedingToleranceKmh => _speedingToleranceKmh ?? 5.0;

  /// Sustained time over the limit (ms) before `speeding` fires. Default `3000`.
  int get speedingMinDurationMs => _speedingMinDurationMs ?? 3000;

  /// Suppress brake/accel/corner events below this speed (km/h). Default `5`.
  double get minSpeedForEventsKmh => _minSpeedForEventsKmh ?? 5.0;

  /// Minimum time between same-kind events (ms). Default `2000`.
  int get eventDebounceMs => _eventDebounceMs ?? 2000;

  /// Applies every field [other] explicitly supplied on top of this config,
  /// leaving fields [other] left unset as they are here.
  ///
  /// This mirrors what the platform does with the serialized payload, and
  /// keeps `Tracelet.activeConfig` in step with the values actually persisted
  /// natively after a partial `setConfig()` (#321).
  TelematicsConfig mergedWith(TelematicsConfig other) => TelematicsConfig(
    enableDrivingEvents: other._enableDrivingEvents ?? _enableDrivingEvents,
    harshBrakingG: other._harshBrakingG ?? _harshBrakingG,
    harshAccelerationG: other._harshAccelerationG ?? _harshAccelerationG,
    harshCorneringG: other._harshCorneringG ?? _harshCorneringG,
    speedLimitKmh: other._speedLimitKmh ?? _speedLimitKmh,
    speedingToleranceKmh: other._speedingToleranceKmh ?? _speedingToleranceKmh,
    speedingMinDurationMs:
        other._speedingMinDurationMs ?? _speedingMinDurationMs,
    minSpeedForEventsKmh: other._minSpeedForEventsKmh ?? _minSpeedForEventsKmh,
    eventDebounceMs: other._eventDebounceMs ?? _eventDebounceMs,
  );

  /// Returns this config with every field pinned to its effective value.
  ///
  /// Used by `ready()`, which establishes a complete native baseline rather
  /// than a partial update — so the platform's own defaults never have to
  /// match Dart's for correctness (#321).
  TelematicsConfig resolved() => TelematicsConfig(
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

  /// Serializes to a map.
  Map<String, Object?> toMap() => <String, Object?>{
    if (_enableDrivingEvents != null)
      'enableDrivingEvents': _enableDrivingEvents,
    if (_harshBrakingG != null) 'harshBrakingG': _harshBrakingG,
    if (_harshAccelerationG != null) 'harshAccelerationG': _harshAccelerationG,
    if (_harshCorneringG != null) 'harshCorneringG': _harshCorneringG,
    if (_speedLimitKmh != null) 'speedLimitKmh': _speedLimitKmh,
    if (_speedingToleranceKmh != null)
      'speedingToleranceKmh': _speedingToleranceKmh,
    if (_speedingMinDurationMs != null)
      'speedingMinDurationMs': _speedingMinDurationMs,
    if (_minSpeedForEventsKmh != null)
      'minSpeedForEventsKmh': _minSpeedForEventsKmh,
    if (_eventDebounceMs != null) 'eventDebounceMs': _eventDebounceMs,
  };

  /// Converts to Pigeon [TlTelematicsConfig].
  TlTelematicsConfig toTlConfig() => TlTelematicsConfig(
    enableDrivingEvents: _enableDrivingEvents,
    harshBrakingG: _harshBrakingG,
    harshAccelerationG: _harshAccelerationG,
    harshCorneringG: _harshCorneringG,
    speedLimitKmh: _speedLimitKmh,
    speedingToleranceKmh: _speedingToleranceKmh,
    speedingMinDurationMs: _speedingMinDurationMs,
    minSpeedForEventsKmh: _minSpeedForEventsKmh,
    eventDebounceMs: _eventDebounceMs,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TelematicsConfig &&
          runtimeType == other.runtimeType &&
          _enableDrivingEvents == other._enableDrivingEvents &&
          _harshBrakingG == other._harshBrakingG &&
          _harshAccelerationG == other._harshAccelerationG &&
          _harshCorneringG == other._harshCorneringG &&
          _speedLimitKmh == other._speedLimitKmh &&
          _speedingToleranceKmh == other._speedingToleranceKmh &&
          _speedingMinDurationMs == other._speedingMinDurationMs &&
          _minSpeedForEventsKmh == other._minSpeedForEventsKmh &&
          _eventDebounceMs == other._eventDebounceMs;

  @override
  int get hashCode => Object.hash(
    _enableDrivingEvents,
    _harshBrakingG,
    _harshAccelerationG,
    _harshCorneringG,
    _speedLimitKmh,
    _speedingToleranceKmh,
    _speedingMinDurationMs,
    _minSpeedForEventsKmh,
    _eventDebounceMs,
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
    bool? enableFusedClassifier,
    bool? fusedClassifierAuthoritative,
    int? modeSwitchDwellMs,
    double? minModeConfidence,
    bool? autoTuneFromTransportMode,
  }) : _enableFusedClassifier = enableFusedClassifier,
       _fusedClassifierAuthoritative = fusedClassifierAuthoritative,
       _modeSwitchDwellMs = modeSwitchDwellMs,
       _minModeConfidence = minModeConfidence,
       _autoTuneFromTransportMode = autoTuneFromTransportMode;

  /// Creates a [ClassifierConfig] from a map.
  factory ClassifierConfig.fromMap(Map<String, Object?> map) {
    return ClassifierConfig(
      enableFusedClassifier: map.containsKey('enableFusedClassifier')
          ? ensureBool(map['enableFusedClassifier'], fallback: false)
          : null,
      fusedClassifierAuthoritative:
          map.containsKey('fusedClassifierAuthoritative')
          ? ensureBool(map['fusedClassifierAuthoritative'], fallback: false)
          : null,
      modeSwitchDwellMs: map.containsKey('modeSwitchDwellMs')
          ? ensureInt(map['modeSwitchDwellMs'], fallback: 8000)
          : null,
      minModeConfidence: map.containsKey('minModeConfidence')
          ? ensureDouble(map['minModeConfidence'], fallback: 0.6)
          : null,
      autoTuneFromTransportMode: map.containsKey('autoTuneFromTransportMode')
          ? ensureBool(map['autoTuneFromTransportMode'], fallback: false)
          : null,
    );
  }

  // Backing fields. `null` means "the caller did not provide this",
  // which keeps the field out of the wire payload (#321). The getters
  // below resolve each one to its documented default.
  final bool? _enableFusedClassifier;
  final bool? _fusedClassifierAuthoritative;
  final int? _modeSwitchDwellMs;
  final double? _minModeConfidence;
  final bool? _autoTuneFromTransportMode;

  /// Master switch. When `false` the classifier and accel feed never start.
  bool get enableFusedClassifier => _enableFusedClassifier ?? false;

  /// If `true`, the fused mode overrides the platform activity for sampling.
  bool get fusedClassifierAuthoritative =>
      _fusedClassifierAuthoritative ?? false;

  /// Dwell (ms) a candidate mode must persist before committing. Default `8000`.
  int get modeSwitchDwellMs => _modeSwitchDwellMs ?? 8000;

  /// Below this confidence the mode is reported as `unknown`. Default `0.6`.
  double get minModeConfidence => _minModeConfidence ?? 0.6;

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
  bool get autoTuneFromTransportMode => _autoTuneFromTransportMode ?? false;

  /// Applies every field [other] explicitly supplied on top of this config,
  /// leaving fields [other] left unset as they are here.
  ///
  /// This mirrors what the platform does with the serialized payload, and
  /// keeps `Tracelet.activeConfig` in step with the values actually persisted
  /// natively after a partial `setConfig()` (#321).
  ClassifierConfig mergedWith(ClassifierConfig other) => ClassifierConfig(
    enableFusedClassifier:
        other._enableFusedClassifier ?? _enableFusedClassifier,
    fusedClassifierAuthoritative:
        other._fusedClassifierAuthoritative ?? _fusedClassifierAuthoritative,
    modeSwitchDwellMs: other._modeSwitchDwellMs ?? _modeSwitchDwellMs,
    minModeConfidence: other._minModeConfidence ?? _minModeConfidence,
    autoTuneFromTransportMode:
        other._autoTuneFromTransportMode ?? _autoTuneFromTransportMode,
  );

  /// Returns this config with every field pinned to its effective value.
  ///
  /// Used by `ready()`, which establishes a complete native baseline rather
  /// than a partial update — so the platform's own defaults never have to
  /// match Dart's for correctness (#321).
  ClassifierConfig resolved() => ClassifierConfig(
    enableFusedClassifier: enableFusedClassifier,
    fusedClassifierAuthoritative: fusedClassifierAuthoritative,
    modeSwitchDwellMs: modeSwitchDwellMs,
    minModeConfidence: minModeConfidence,
    autoTuneFromTransportMode: autoTuneFromTransportMode,
  );

  /// Serializes to a map.
  Map<String, Object?> toMap() => <String, Object?>{
    if (_enableFusedClassifier != null)
      'enableFusedClassifier': _enableFusedClassifier,
    if (_fusedClassifierAuthoritative != null)
      'fusedClassifierAuthoritative': _fusedClassifierAuthoritative,
    if (_modeSwitchDwellMs != null) 'modeSwitchDwellMs': _modeSwitchDwellMs,
    if (_minModeConfidence != null) 'minModeConfidence': _minModeConfidence,
    if (_autoTuneFromTransportMode != null)
      'autoTuneFromTransportMode': _autoTuneFromTransportMode,
  };

  /// Converts to Pigeon [TlClassifierConfig].
  TlClassifierConfig toTlConfig() => TlClassifierConfig(
    enableFusedClassifier: _enableFusedClassifier,
    fusedClassifierAuthoritative: _fusedClassifierAuthoritative,
    modeSwitchDwellMs: _modeSwitchDwellMs,
    minModeConfidence: _minModeConfidence,
    autoTuneFromTransportMode: _autoTuneFromTransportMode,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClassifierConfig &&
          runtimeType == other.runtimeType &&
          _enableFusedClassifier == other._enableFusedClassifier &&
          _fusedClassifierAuthoritative ==
              other._fusedClassifierAuthoritative &&
          _modeSwitchDwellMs == other._modeSwitchDwellMs &&
          _minModeConfidence == other._minModeConfidence &&
          _autoTuneFromTransportMode == other._autoTuneFromTransportMode;

  @override
  int get hashCode => Object.hash(
    _enableFusedClassifier,
    _fusedClassifierAuthoritative,
    _modeSwitchDwellMs,
    _minModeConfidence,
    _autoTuneFromTransportMode,
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
    bool? enableCrashDetection,
    bool? enableFallDetection,
    double? crashGThreshold,
    double? crashMinSpeedKmh,
    double? fallGThreshold,
    int? confirmWindowMs,
    double? minImpactConfidence,
    this.crashModelUrl,
    this.crashModelSha256,
    double? crashModelThreshold,
    this.crashModelUnlockUrl,
    this.crashModelLicenseKey,
  }) : _enableCrashDetection = enableCrashDetection,
       _enableFallDetection = enableFallDetection,
       _crashGThreshold = crashGThreshold,
       _crashMinSpeedKmh = crashMinSpeedKmh,
       _fallGThreshold = fallGThreshold,
       _confirmWindowMs = confirmWindowMs,
       _minImpactConfidence = minImpactConfidence,
       _crashModelThreshold = crashModelThreshold;

  /// Creates an [ImpactConfig] from a map.
  factory ImpactConfig.fromMap(Map<String, Object?> map) {
    return ImpactConfig(
      enableCrashDetection: map.containsKey('enableCrashDetection')
          ? ensureBool(map['enableCrashDetection'], fallback: false)
          : null,
      enableFallDetection: map.containsKey('enableFallDetection')
          ? ensureBool(map['enableFallDetection'], fallback: false)
          : null,
      crashGThreshold: map.containsKey('crashGThreshold')
          ? ensureDouble(map['crashGThreshold'], fallback: 2)
          : null,
      crashMinSpeedKmh: map.containsKey('crashMinSpeedKmh')
          ? ensureDouble(map['crashMinSpeedKmh'], fallback: 25)
          : null,
      fallGThreshold: map.containsKey('fallGThreshold')
          ? ensureDouble(map['fallGThreshold'], fallback: 2.5)
          : null,
      confirmWindowMs: map.containsKey('confirmWindowMs')
          ? ensureInt(map['confirmWindowMs'], fallback: 15000)
          : null,
      minImpactConfidence: map.containsKey('minImpactConfidence')
          ? ensureDouble(map['minImpactConfidence'], fallback: 0.6)
          : null,
      crashModelUrl: map['crashModelUrl'] as String?,
      crashModelSha256: map['crashModelSha256'] as String?,
      crashModelThreshold: map.containsKey('crashModelThreshold')
          ? ensureDouble(map['crashModelThreshold'], fallback: 0.5)
          : null,
      crashModelUnlockUrl: map['crashModelUnlockUrl'] as String?,
      crashModelLicenseKey: map['crashModelLicenseKey'] as String?,
    );
  }

  // Backing fields. `null` means "the caller did not provide this",
  // which keeps the field out of the wire payload (#321). The getters
  // below resolve each one to its documented default.
  final bool? _enableCrashDetection;
  final bool? _enableFallDetection;
  final double? _crashGThreshold;
  final double? _crashMinSpeedKmh;
  final double? _fallGThreshold;
  final int? _confirmWindowMs;
  final double? _minImpactConfidence;
  final double? _crashModelThreshold;

  /// Master switch for vehicle crash detection.
  bool get enableCrashDetection => _enableCrashDetection ?? false;

  /// Personal fall detection (best-effort; default `false`).
  bool get enableFallDetection => _enableFallDetection ?? false;

  /// Impact magnitude (g) for a crash candidate. Default `2.0` (lowered from 3.0
  /// after a field-data study found 3.0 g missed ~half of real crashes; the
  /// cancel-countdown offsets the extra false alarms).
  double get crashGThreshold => _crashGThreshold ?? 2.0;

  /// Pre-impact speed (km/h) required to corroborate a crash. Default `25`.
  double get crashMinSpeedKmh => _crashMinSpeedKmh ?? 25.0;

  /// Impact magnitude (g) for a fall candidate. Default `2.5`.
  double get fallGThreshold => _fallGThreshold ?? 2.5;

  /// Countdown (ms) before a candidate auto-confirms. Default `15000`.
  int get confirmWindowMs => _confirmWindowMs ?? 15000;

  /// Suppress candidates below this confidence. Default `0.6`.
  double get minImpactConfidence => _minImpactConfidence ?? 0.6;

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
  ///
  /// Not required for cache invalidation: the on-disk cache is keyed by
  /// [crashModelUrl], so pointing at a new model is a cache miss on its own
  /// (#314).
  final String? crashModelSha256;

  /// Probability threshold (`0..1`) at which the ML model flags a crash. Default
  /// `0.5`. Use the `rf_probability_threshold` from the model's training report.
  double get crashModelThreshold => _crashModelThreshold ?? 0.5;

  /// Optional licensing **unlock endpoint** (e.g. a Cloudflare Worker). When set
  /// with [crashModelLicenseKey], the SDK POSTs the license to this URL to fetch
  /// the decryption key + model URL at runtime, instead of the host injecting the
  /// key manually. The key is held in memory only. `null` ⇒ no auto-unlock.
  final String? crashModelUnlockUrl;

  /// Customer license key presented to [crashModelUnlockUrl]. Bound to your app
  /// (package/bundle id) and signed by you; never grants access on its own — the
  /// endpoint validates it before returning the key.
  final String? crashModelLicenseKey;

  /// Applies every field [other] explicitly supplied on top of this config,
  /// leaving fields [other] left unset as they are here.
  ///
  /// This mirrors what the platform does with the serialized payload, and
  /// keeps `Tracelet.activeConfig` in step with the values actually persisted
  /// natively after a partial `setConfig()` (#321).
  ImpactConfig mergedWith(ImpactConfig other) => ImpactConfig(
    enableCrashDetection: other._enableCrashDetection ?? _enableCrashDetection,
    enableFallDetection: other._enableFallDetection ?? _enableFallDetection,
    crashGThreshold: other._crashGThreshold ?? _crashGThreshold,
    crashMinSpeedKmh: other._crashMinSpeedKmh ?? _crashMinSpeedKmh,
    fallGThreshold: other._fallGThreshold ?? _fallGThreshold,
    confirmWindowMs: other._confirmWindowMs ?? _confirmWindowMs,
    minImpactConfidence: other._minImpactConfidence ?? _minImpactConfidence,
    crashModelUrl: other.crashModelUrl ?? crashModelUrl,
    crashModelSha256: other.crashModelSha256 ?? crashModelSha256,
    crashModelThreshold: other._crashModelThreshold ?? _crashModelThreshold,
    crashModelUnlockUrl: other.crashModelUnlockUrl ?? crashModelUnlockUrl,
    crashModelLicenseKey: other.crashModelLicenseKey ?? crashModelLicenseKey,
  );

  /// Returns this config with every field pinned to its effective value.
  ///
  /// Used by `ready()`, which establishes a complete native baseline rather
  /// than a partial update — so the platform's own defaults never have to
  /// match Dart's for correctness (#321).
  ImpactConfig resolved() => ImpactConfig(
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

  /// Serializes to a map.
  Map<String, Object?> toMap() => <String, Object?>{
    if (_enableCrashDetection != null)
      'enableCrashDetection': _enableCrashDetection,
    if (_enableFallDetection != null)
      'enableFallDetection': _enableFallDetection,
    if (_crashGThreshold != null) 'crashGThreshold': _crashGThreshold,
    if (_crashMinSpeedKmh != null) 'crashMinSpeedKmh': _crashMinSpeedKmh,
    if (_fallGThreshold != null) 'fallGThreshold': _fallGThreshold,
    if (_confirmWindowMs != null) 'confirmWindowMs': _confirmWindowMs,
    if (_minImpactConfidence != null)
      'minImpactConfidence': _minImpactConfidence,
    if (crashModelUrl != null) 'crashModelUrl': crashModelUrl,
    if (crashModelSha256 != null) 'crashModelSha256': crashModelSha256,
    if (_crashModelThreshold != null)
      'crashModelThreshold': _crashModelThreshold,
    if (crashModelUnlockUrl != null) 'crashModelUnlockUrl': crashModelUnlockUrl,
    if (crashModelLicenseKey != null)
      'crashModelLicenseKey': crashModelLicenseKey,
  };

  /// Converts to Pigeon [TlImpactConfig].
  TlImpactConfig toTlConfig() => TlImpactConfig(
    enableCrashDetection: _enableCrashDetection,
    enableFallDetection: _enableFallDetection,
    crashGThreshold: _crashGThreshold,
    crashMinSpeedKmh: _crashMinSpeedKmh,
    fallGThreshold: _fallGThreshold,
    confirmWindowMs: _confirmWindowMs,
    minImpactConfidence: _minImpactConfidence,
    crashModelUrl: crashModelUrl,
    crashModelSha256: crashModelSha256,
    crashModelThreshold: _crashModelThreshold,
    crashModelUnlockUrl: crashModelUnlockUrl,
    crashModelLicenseKey: crashModelLicenseKey,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImpactConfig &&
          runtimeType == other.runtimeType &&
          _enableCrashDetection == other._enableCrashDetection &&
          _enableFallDetection == other._enableFallDetection &&
          _crashGThreshold == other._crashGThreshold &&
          _crashMinSpeedKmh == other._crashMinSpeedKmh &&
          _fallGThreshold == other._fallGThreshold &&
          _confirmWindowMs == other._confirmWindowMs &&
          _minImpactConfidence == other._minImpactConfidence &&
          crashModelUrl == other.crashModelUrl &&
          crashModelSha256 == other.crashModelSha256 &&
          _crashModelThreshold == other._crashModelThreshold &&
          crashModelUnlockUrl == other.crashModelUnlockUrl &&
          crashModelLicenseKey == other.crashModelLicenseKey;

  @override
  int get hashCode => Object.hash(
    _enableCrashDetection,
    _enableFallDetection,
    _crashGThreshold,
    _crashMinSpeedKmh,
    _fallGThreshold,
    _confirmWindowMs,
    _minImpactConfidence,
    crashModelUrl,
    crashModelSha256,
    _crashModelThreshold,
    crashModelUnlockUrl,
    crashModelLicenseKey,
  );
}
