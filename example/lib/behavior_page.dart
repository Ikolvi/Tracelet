import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:tracelet/tracelet.dart' as tl;
// FRB engine handles — drive the real Rust detection logic with synthetic
// input so the features can be demoed without actually driving/crashing.
// ignore_for_file: implementation_imports
import 'package:tracelet_platform_interface/src/rust/api_dart/telematics.dart';
import 'package:tracelet_platform_interface/src/rust/api_dart/impact.dart';
import 'package:tracelet_platform_interface/src/rust/api_dart/transport_mode.dart';
import 'package:tracelet_platform_interface/src/rust/algorithms/impact.dart'
    as frb
    show ImpactConfig;
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

/// Demo page for the 3.3.0 behavior features: driving telematics, crash/fall
/// detection, and the fused transport-mode classifier.
///
/// Kept on its own page so the (already large) dashboard/issues pages stay lean.
/// Toggling a feature calls `Tracelet.setConfig` on the running instance and
/// subscribes to the corresponding event stream.
class BehaviorPage extends StatefulWidget {
  const BehaviorPage({super.key});

  @override
  State<BehaviorPage> createState() => _BehaviorPageState();
}

class _BehaviorPageState extends State<BehaviorPage> {
  bool _driving = false;
  bool _crash = false;
  bool _classifier = false;

  // ML crash model (licensed). A working dev license for this example app
  // (com.ikolvi.tracelet.example) is hardcoded below so the encrypted model
  // downloads and on-device crash/fall inference can be tested out-of-the-box.
  // Replace with your own key from https://licenses.ikolvi.com for your app id.
  static const String _unlockUrl = 'https://unlock.ikolvi.com/unlock';
  static const double _crashModelThreshold = 0.5074575792;
  // Dev key for com.ikolvi.tracelet.example; expires 2027-10-22. The previous
  // one lapsed on 2026-08-18 and every unlock failed with `expired` (#439).
  static const String _demoLicenseKey =
      'eyJleHAiOjE4MjQxOTk3OTYsImlhdCI6MTc5MjY2Mzc5NiwibGljIjoiM2Q0NTdmYTctNDc2NC00Yjk4LTk5YzgtNDEwMmExYzk5ZjliIiwicGtnIjoiY29tLmlrb2x2aS50cmFjZWxldC5leGFtcGxlIiwicGxhbiI6InBybyIsInNjb3BlIjoiZGV2In0.99MzdeKRNEGs_Stwt1B_7zik_BjO2EsFfABUy_v5oLdwXNjDMV64D6A-izguoXqlfBFBacE02hVnx7qZyCNTCg';
  bool _useMlModel = true;

  // Bench-test mode: crash detection is normally speed-gated at 25 km/h (GPS
  // speed), so a phone thrown onto a bed (~0 km/h) never fires even with a huge
  // g-spike. Enable this to drop the gate to 0 km/h so a physical throw can
  // trigger the model on a stationary device. Leave OFF for real driving.
  bool _throwTestMode = false;

  final TextEditingController _licenseCtrl = TextEditingController(
    text: _demoLicenseKey,
  );

  final List<String> _log = [];
  String _mode = 'unknown';
  tl.ImpactEvent? _pendingImpact;

  // Current ML crash-model lifecycle state for the on-screen status indicator.
  // null ⇒ not started yet (idle).
  tl.CrashModelStatus? _crashModelStatus;
  String? _crashModelDetail;

  StreamSubscription<tl.DrivingEvent>? _drivingSub;
  StreamSubscription<tl.ImpactEvent>? _impactSub;
  StreamSubscription<tl.ModeChangeEvent>? _modeSub;
  StreamSubscription<tl.CrashModelStatusEvent>? _crashModelSub;

  @override
  void dispose() {
    _drivingSub?.cancel();
    _impactSub?.cancel();
    _modeSub?.cancel();
    _crashModelSub?.cancel();
    _licenseCtrl.dispose();
    super.dispose();
  }

  void _logLine(String s) {
    setState(() {
      _log.insert(0, '${TimeOfDay.now().format(context)}  $s');
      if (_log.length > 40) _log.removeLast();
    });
  }

  bool _ready = false;

  /// Ensures the SDK is initialized so config/streams/simulation work even if
  /// the user opened this page before pressing Initialize on the main screen.
  ///
  /// Non-clobbering: re-applies the *current* active config, which is a no-op
  /// when already initialized and surfaces `NOT_READY` otherwise — in which case
  /// we initialize with that same (default) config.
  Future<void> _ensureReady() async {
    if (_ready) return;
    try {
      await tl.Tracelet.setConfig(tl.Tracelet.activeConfig);
    } on PlatformException catch (e) {
      if (e.code == 'NOT_READY') {
        await tl.Tracelet.ready(tl.Tracelet.activeConfig);
        _logLine('ℹ️ Initialized Tracelet for this demo');
      } else {
        rethrow;
      }
    }
    _ready = true;
  }

  Future<void> _applyConfig() async {
    await _ensureReady();
    final licenseKey = _licenseCtrl.text.trim();
    // Throw-test mode forces the rule engine: the ML model scores `speed_max`
    // and `dv` (pre-impact speed drop), both zero on a stationary phone, so it
    // can never classify a bench throw as a crash (by design). The g-threshold
    // rule fires on raw peak-g alone, which is what a physical throw can drive.
    final useMl = _useMlModel && licenseKey.isNotEmpty && !_throwTestMode;
    await tl.Tracelet.setConfig(
      tl.Config(
        // Debug logging so the crash-model lifecycle (unlock → download →
        // decrypt → "Crash ML model active.") is visible in logcat/Console.
        // Filter with: adb logcat -s Tracelet   (Android)
        //              log stream --predicate 'subsystem == "Tracelet"' (iOS)
        logger: const tl.LoggerConfig(logLevel: tl.LogLevel.debug),
        telematics: tl.TelematicsConfig(
          enableDrivingEvents: _driving,
          // A modest limit so speeding is demoable without a highway.
          speedLimitKmh: _driving ? 30 : 0,
        ),
        classifier: tl.ClassifierConfig(enableFusedClassifier: _classifier),
        impact: tl.ImpactConfig(
          enableCrashDetection: _crash,
          crashModelUnlockUrl: useMl ? _unlockUrl : null,
          crashModelLicenseKey: useMl ? licenseKey : null,
          crashModelThreshold: _crashModelThreshold,
          // Drop the speed gate for a stationary bench test (throw-on-bed).
          crashMinSpeedKmh: _throwTestMode ? 0 : 25,
        ),
      ),
    );
  }

  Future<void> _toggleDriving(bool v) async {
    setState(() => _driving = v);
    await _applyConfig();
    if (v) {
      _drivingSub ??= tl.Tracelet.drivingEventStream.listen((e) {
        _logLine(
          '🚗 ${e.kind}  sev=${e.severity.toStringAsFixed(2)}  '
          'val=${e.value.toStringAsFixed(2)}',
        );
      });
    } else {
      _drivingSub?.cancel();
      _drivingSub = null;
    }
  }

  Future<void> _toggleCrash(bool v) async {
    setState(() => _crash = v);
    await _applyConfig();
    if (v) {
      // Surface ML crash-model download/load progress so the user knows the
      // model is being prepared before crash detection becomes active. Drives
      // both the scrolling log and the persistent status indicator.
      _crashModelSub ??= tl.Tracelet.crashModelStatusStream.listen((e) {
        setState(() {
          _crashModelStatus = e.status;
          _crashModelDetail = e.detail;
        });
        final detail = e.detail != null ? '  (${e.detail})' : '';
        switch (e.status) {
          case tl.CrashModelStatus.unlocking:
            _logLine('🔑 crash model: unlocking license…');
          case tl.CrashModelStatus.downloading:
            _logLine('⬇️ crash model: downloading…');
          case tl.CrashModelStatus.decrypting:
            _logLine('🔓 crash model: decrypting…');
          case tl.CrashModelStatus.ready:
            _logLine('✅ crash model ready$detail');
          case tl.CrashModelStatus.failed:
            _logLine('❌ crash model failed$detail');
          case tl.CrashModelStatus.disabled:
            _logLine('⏸️ crash model disabled');
          case tl.CrashModelStatus.unknown:
            _logLine('crash model: ${e.status.name}$detail');
        }
      });
      _impactSub ??= tl.Tracelet.impactStream.listen((e) {
        if (e.isPotential) {
          setState(() => _pendingImpact = e);
          _logLine(
            '⚠️ ${e.kind}  peak=${e.peakG.toStringAsFixed(1)}g  '
            '(cancel within window)',
          );
        } else {
          setState(() => _pendingImpact = null);
          _logLine(
            '🆘 CONFIRMED ${e.kind}  peak=${e.peakG.toStringAsFixed(1)}g',
          );
        }
      });
    } else {
      _impactSub?.cancel();
      _impactSub = null;
      _crashModelSub?.cancel();
      _crashModelSub = null;
      setState(() {
        _pendingImpact = null;
        _crashModelStatus = null;
        _crashModelDetail = null;
      });
    }
  }

  Future<void> _toggleClassifier(bool v) async {
    setState(() => _classifier = v);
    await _applyConfig();
    if (v) {
      _modeSub ??= tl.Tracelet.modeChangeStream.listen((e) {
        setState(() => _mode = e.mode);
        _logLine('🚶 mode → ${e.mode}  (${e.confidence.toStringAsFixed(2)})');
      });
    } else {
      _modeSub?.cancel();
      _modeSub = null;
    }
  }

  Future<void> _cancelImpact() async {
    final e = _pendingImpact;
    if (e == null) return;
    await tl.Tracelet.cancelImpact(e.id);
    setState(() => _pendingImpact = null);
    _logLine('✋ cancelled impact #${e.id}');
  }

  /// Runs the real Rust engines (via flutter_rust_bridge) with synthetic input
  /// so each detection can be demoed on-device without actually driving. This
  /// is a self-contained demo: it does not require tracking to be started, but
  /// it does need the Rust library initialized — [_ensureReady] handles that.
  Future<void> _simulate(String scenario) async {
    await _ensureReady();
    try {
      switch (scenario) {
        case 'brake':
          final e = TelematicsEngineDart();
          e.processFix(
            speed: 22,
            heading: 90,
            latitude: 0,
            longitude: 0,
            timestampMs: PlatformInt64Util.from(0),
          );
          for (final ev in e.processFix(
            speed: 5,
            heading: 90,
            latitude: 0,
            longitude: 0,
            timestampMs: PlatformInt64Util.from(1000),
          )) {
            _logLine(
              '🚗 ${ev.kind}  val=${ev.value.toStringAsFixed(2)}g (sim)',
            );
          }
        case 'accel':
          final e = TelematicsEngineDart();
          e.processFix(
            speed: 4,
            heading: 90,
            latitude: 0,
            longitude: 0,
            timestampMs: PlatformInt64Util.from(0),
          );
          for (final ev in e.processFix(
            speed: 15,
            heading: 90,
            latitude: 0,
            longitude: 0,
            timestampMs: PlatformInt64Util.from(1000),
          )) {
            _logLine(
              '🚗 ${ev.kind}  val=${ev.value.toStringAsFixed(2)}g (sim)',
            );
          }
        case 'corner':
          final e = TelematicsEngineDart();
          e.processFix(
            speed: 15,
            heading: 0,
            latitude: 0,
            longitude: 0,
            timestampMs: PlatformInt64Util.from(0),
          );
          for (final ev in e.processFix(
            speed: 15,
            heading: 45,
            latitude: 0,
            longitude: 0,
            timestampMs: PlatformInt64Util.from(1000),
          )) {
            _logLine(
              '🚗 ${ev.kind}  val=${ev.value.toStringAsFixed(2)}g (sim)',
            );
          }
        case 'crash':
          final d = ImpactDetectorDart(
            config: frb.ImpactConfig(
              enableCrash: true,
              enableFall: false,
              crashGThreshold: 3,
              crashMinSpeedKmh: 25,
              fallGThreshold: 2.5,
              confirmWindowMs: PlatformInt64Util.from(15000),
              minConfidence: 0.6,
            ),
          );
          final c = d.onImpactWindow(
            peakG: 5,
            speedBeforeMps: 60 / 3.6,
            gyroPeakDps: 0,
            wasInFreeFall: false,
            postImpactStill: false,
            isOnFoot: false,
            latitude: 0,
            longitude: 0,
            nowMs: PlatformInt64Util.from(0),
          );
          if (c != null) {
            _logLine(
              '🆘 ${c.kind}  peak=${c.peakG.toStringAsFixed(1)}g (sim) '
              '→ would auto-confirm in ${((c.confirmDeadlineMs is BigInt ? (c.confirmDeadlineMs as dynamic).toInt() : c.confirmDeadlineMs) / 1000).round()}s',
            );
          }
        case 'baro':
          // Crash candidate corroborated by a cabin-pressure spike (#173) — the
          // airbag/severe-collision pressure transient one of the signals
          // Apple's Crash Detection fuses. The cue only raises confidence and
          // never suppresses, so phones without a barometer are unaffected.
          final d = ImpactDetectorDart(
            config: frb.ImpactConfig(
              enableCrash: true,
              enableFall: false,
              crashGThreshold: 3,
              crashMinSpeedKmh: 25,
              fallGThreshold: 2.5,
              confirmWindowMs: PlatformInt64Util.from(15000),
              minConfidence: 0.6,
            ),
          );
          final c = d.onImpactWindow(
            peakG: 5,
            speedBeforeMps: 60 / 3.6,
            gyroPeakDps: 0,
            wasInFreeFall: false,
            postImpactStill: false,
            isOnFoot: false,
            latitude: 0,
            longitude: 0,
            nowMs: PlatformInt64Util.from(0),
          );
          if (c != null) {
            _logLine('🆘 ${c.kind}  peak=${c.peakG.toStringAsFixed(1)}g (sim)');
            // Concurrent 3 hPa cabin-pressure swing → corroborated.
            final matched = d.corroborateBarometric(
              pressureDeltaHpa: 3,
              nowMs: PlatformInt64Util.from(500),
            );
            _logLine(
              matched
                  ? '🌡️ barometer: 3 hPa cabin-pressure spike → confidence raised'
                  : '🌡️ barometer: no pressure swing → unchanged',
            );
          }
        case 'mlcrash':
        case 'mlbenign':
          // Runs the REAL SDK pipeline (loaded ML model + live ImpactDetector),
          // unlike 'crash' which uses a throwaway rule-based detector.
          // 'mlcrash' feeds a real crash profile (rotation + speed + sudden
          // deceleration); 'mlbenign' feeds a bare g-spike the model rejects.
          final crashLike = scenario == 'mlcrash';
          final r = await tl.Tracelet.debugRunCrashModelInference(
            peakG: 6,
            speedKmh: 80,
            crashLike: crashLike,
          );
          if (r['error'] != null) {
            _logLine('🤖 ML inference unavailable: ${r['error']}');
          } else {
            final ran = r['modelRan'] == true;
            final proba = (r['proba'] as num?)?.toDouble() ?? -1.0;
            final thr = (r['threshold'] as num?)?.toDouble() ?? 0.0;
            final fired = r['fired'] == true;
            final label = crashLike ? 'crash-like input' : 'benign bump';
            if (ran) {
              _logLine(
                '🤖 ML model ran ($label): proba=${proba.toStringAsFixed(3)} '
                'thr=${thr.toStringAsFixed(3)} → '
                '${fired ? "🆘 CRASH fired (${r['kind']})" : "below threshold (no crash)"}',
              );
            } else {
              _logLine(
                '⚠️ No ML model loaded — rule engine only '
                '(${fired ? "fired ${r['kind']}" : "no crash"}). '
                'Enable "Use licensed ML crash model".',
              );
            }
          }
        case 'vehicle':
          final cl = TransportModeClassifierDart();
          final steady = List<double>.filled(10, 0.05);
          cl.classifySamples(
            magnitudesG: steady,
            durationMs: PlatformInt64Util.from(1000),
            speedMps: 60 / 3.6,
            nowMs: PlatformInt64Util.from(0),
          );
          final r = cl.classifySamples(
            magnitudesG: steady,
            durationMs: PlatformInt64Util.from(1000),
            speedMps: 60 / 3.6,
            nowMs: PlatformInt64Util.from(9000),
          );
          _logLine(
            '🚦 mode → ${r.mode.name} (${r.confidence.toStringAsFixed(2)}) (sim)',
          );
      }
    } catch (e) {
      _logLine('⚠️ simulate failed: $e (is the SDK initialized?)');
    }
  }

  /// Exercises the telematics SQLite log: persist a test event, read it back,
  /// or clear it. This is the path used by Tracelet Doctor and verifies that
  /// `getTelematicsEvents` / `simulateTelematicsEvent` / `destroyTelematicsEvents`
  /// round-trip through the real on-device database.
  Future<void> _dbAction(String action) async {
    await _ensureReady();
    try {
      switch (action) {
        case 'persist':
          final ok = await tl.Tracelet.simulateTelematicsEvent(
            eventType: 'harsh_braking',
            severity: 0.85,
            latitude: 37.422,
            longitude: -122.084,
          );
          _logLine('💾 persisted test event → DB (ok=$ok)');
        case 'load':
          final events = await tl.Tracelet.getTelematicsEvents(50);
          _logLine('💾 DB has ${events.length} event(s)');
          for (final e in events.take(5)) {
            _logLine(
              '   • ${e.eventType}  sev=${e.severity.toStringAsFixed(2)}  '
              '@${e.latitude.toStringAsFixed(3)},${e.longitude.toStringAsFixed(3)}',
            );
          }
        case 'clear':
          final ok = await tl.Tracelet.destroyTelematicsEvents();
          _logLine('💾 cleared telematics DB (ok=$ok)');
      }
    } catch (e) {
      _logLine('⚠️ DB action failed: $e');
    }
  }

  /// Persistent ML crash-model status indicator. Always visible while crash
  /// detection is on, so the user can see every stage from unlock → download →
  /// decrypt → ready (or failed). Shows a spinner during in-progress stages.
  Widget _crashModelStatusTile() {
    final status = _crashModelStatus;
    final (
      IconData icon,
      Color color,
      String label,
      bool busy,
    ) = switch (status) {
      null => (Icons.hourglass_empty, Colors.grey, 'Idle — not started', false),
      tl.CrashModelStatus.unlocking => (
        Icons.vpn_key,
        Colors.blue,
        'Unlocking license…',
        true,
      ),
      tl.CrashModelStatus.downloading => (
        Icons.cloud_download,
        Colors.blue,
        'Downloading model…',
        true,
      ),
      tl.CrashModelStatus.decrypting => (
        Icons.lock_open,
        Colors.blue,
        'Decrypting model…',
        true,
      ),
      tl.CrashModelStatus.ready => (
        Icons.check_circle,
        Colors.green,
        'Model ready',
        false,
      ),
      tl.CrashModelStatus.failed => (
        Icons.error,
        Colors.red,
        'Download failed',
        false,
      ),
      tl.CrashModelStatus.disabled => (
        Icons.pause_circle,
        Colors.grey,
        'Disabled (rule engine)',
        false,
      ),
      tl.CrashModelStatus.unknown => (
        Icons.help,
        Colors.orange,
        'Unknown',
        false,
      ),
    };
    final detail = _crashModelDetail;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: busy
                ? CircularProgressIndicator(strokeWidth: 2, color: color)
                : Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Model status: $label',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: color,
                    fontSize: 13,
                  ),
                ),
                if (detail != null)
                  Text(
                    detail,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Driving & Safety (3.3.0)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Opt-in behavior engines. Enable, then start tracking and move or '
            'drive. All default OFF — they never run unless switched on here.',
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Driving events'),
            subtitle: const Text(
              'harsh braking / acceleration / cornering / speeding (limit 30 km/h)',
            ),
            value: _driving,
            onChanged: _toggleDriving,
          ),
          SwitchListTile(
            title: const Text('Crash detection'),
            subtitle: const Text(
              'high-g impact while moving → cancel countdown',
            ),
            value: _crash,
            onChanged: _toggleCrash,
          ),
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Use licensed ML crash model'),
                    subtitle: const Text(
                      'Gate crashes on the trained model instead of the rule '
                      'engine. Needs a license key.',
                    ),
                    value: _useMlModel,
                    onChanged: (v) async {
                      setState(() {
                        _useMlModel = v;
                        // Reset the indicator; fresh statuses arrive on reload.
                        _crashModelStatus = null;
                        _crashModelDetail = null;
                      });
                      await _applyConfig();
                      _logLine(
                        v && _licenseCtrl.text.trim().isNotEmpty
                            ? '🤖 ML crash model enabled'
                            : v
                            ? 'ℹ️ Paste a license key to activate the ML model'
                            : '🤖 ML crash model disabled (rule engine)',
                      );
                    },
                  ),
                  TextField(
                    controller: _licenseCtrl,
                    decoration: const InputDecoration(
                      labelText: 'License key',
                      hintText: 'Paste from licenses.ikolvi.com',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    maxLines: 2,
                    minLines: 1,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    onChanged: (_) {
                      if (_useMlModel) _applyConfig();
                    },
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Get a key: licenses.ikolvi.com  ·  unlock: $_unlockUrl',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  // Live download/load status of the licensed model. Visible
                  // only when crash detection + ML model are both on.
                  if (_crash && _useMlModel) _crashModelStatusTile(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Throw-test mode (bench)'),
                    subtitle: const Text(
                      'Physical bench test: drops the 25 km/h speed gate AND '
                      'uses the rule engine (fires on raw g-force ≥ 2g). The ML '
                      'model can\'t score a stationary throw — use the "Crash '
                      '(ML model)" button to test the model itself.',
                    ),
                    value: _throwTestMode,
                    onChanged: (v) async {
                      setState(() => _throwTestMode = v);
                      await _applyConfig();
                      _logLine(
                        v
                            ? '🧪 Throw-test mode ON — rule engine + speed gate '
                                  'off. Throw the phone onto a bed; watch for '
                                  '"potential_crash".'
                            : '🧪 Throw-test mode OFF — ML model + 25 km/h gate '
                                  'restored',
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Transport-mode classifier'),
            subtitle: Text('fused accel + GPS — current mode: $_mode'),
            value: _classifier,
            onChanged: _toggleClassifier,
          ),
          if (_pendingImpact != null)
            Card(
              color: Colors.red.shade100,
              child: ListTile(
                leading: const Icon(Icons.warning, color: Colors.red),
                title: Text('Possible ${_pendingImpact!.kind}'),
                subtitle: Text(
                  'peak ${_pendingImpact!.peakG.toStringAsFixed(1)}g — '
                  'auto-confirms unless cancelled',
                ),
                trailing: FilledButton(
                  onPressed: _cancelImpact,
                  child: const Text("I'm fine"),
                ),
              ),
            ),
          const Divider(height: 32),
          const Text(
            'Simulate (runs the real Rust engines with synthetic input)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => _simulate('brake'),
                child: const Text('Hard brake'),
              ),
              OutlinedButton(
                onPressed: () => _simulate('accel'),
                child: const Text('Rapid accel'),
              ),
              OutlinedButton(
                onPressed: () => _simulate('corner'),
                child: const Text('Sharp turn'),
              ),
              OutlinedButton(
                onPressed: () => _simulate('crash'),
                child: const Text('Crash'),
              ),
              OutlinedButton(
                onPressed: () => _simulate('baro'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.indigo),
                child: const Text('Crash + barometer'),
              ),
              OutlinedButton(
                onPressed: () => _simulate('mlcrash'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.purple),
                child: const Text('Crash (ML model)'),
              ),
              OutlinedButton(
                onPressed: () => _simulate('mlbenign'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.teal),
                child: const Text('Benign bump (ML)'),
              ),
              OutlinedButton(
                onPressed: () => _simulate('vehicle'),
                child: const Text('Vehicle mode'),
              ),
            ],
          ),
          const Divider(height: 32),
          const Text(
            'Stored telematics (SQLite DB)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => _dbAction('persist'),
                child: const Text('Persist test event'),
              ),
              OutlinedButton(
                onPressed: () => _dbAction('load'),
                child: const Text('Load from DB'),
              ),
              OutlinedButton(
                onPressed: () => _dbAction('clear'),
                child: const Text('Clear DB'),
              ),
            ],
          ),
          const Divider(height: 32),
          const Text(
            'Event log',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_log.isEmpty) const Text('— no events yet —'),
          ..._log.map(
            (l) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(l, style: const TextStyle(fontFamily: 'monospace')),
            ),
          ),
        ],
      ),
    );
  }
}
