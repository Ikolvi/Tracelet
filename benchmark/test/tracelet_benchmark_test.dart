// ignore_for_file: avoid_print
/// Tracelet Performance Benchmark Suite
///
/// Measures throughput and latency of the core Dart algorithms that run
/// on every GPS fix. Results are printed as a machine-parseable table
/// and can be committed to BENCHMARK.md by the CI workflow.
///
/// Run:
///   cd benchmark && flutter test test/tracelet_benchmark_test.dart
///
/// The benchmark uses raw [Stopwatch] instead of adding a dependency on
/// `package:benchmark_harness` — keeping the dep footprint minimal.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';
import 'package:tracelet/tracelet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// A single benchmark result with name, iterations, and elapsed time.
class _BenchResult {
  _BenchResult(this.name, this.iterations, this.elapsedUs);
  final String name;
  final int iterations;
  final int elapsedUs;

  double get opsPerSec => iterations / (elapsedUs / 1e6);
  double get usPerOp => elapsedUs / iterations;
}

final _results = <_BenchResult>[];

/// Runs [fn] for at least [minDurationMs] ms, then records ops/sec.
void _bench(String name, void Function() fn, {int minDurationMs = 2000}) {
  // Warm-up
  for (var i = 0; i < 1000; i++) {
    fn();
  }

  final sw = Stopwatch()..start();
  var iterations = 0;
  final minUs = minDurationMs * 1000;
  while (sw.elapsedMicroseconds < minUs) {
    fn();
    iterations++;
  }
  sw.stop();
  _results.add(_BenchResult(name, iterations, sw.elapsedMicroseconds));
}

// ─────────────────────────────────────────────────────────────────────────────
// Data generators
// ─────────────────────────────────────────────────────────────────────────────

final _rng = math.Random(42);

/// Generate a GPS track of [n] points with realistic jitter around a center.
List<({double lat, double lng, double acc, int ts})> _generateTrack(int n) {
  var lat = 37.4220;
  var lng = -122.0841;
  final points = <({double lat, double lng, double acc, int ts})>[];
  var ts = 1700000000000; // milliseconds since epoch
  for (var i = 0; i < n; i++) {
    lat += (_rng.nextDouble() - 0.5) * 0.0002;
    lng += (_rng.nextDouble() - 0.5) * 0.0002;
    final acc = 5.0 + _rng.nextDouble() * 50.0;
    points.add((lat: lat, lng: lng, acc: acc, ts: ts));
    ts += 1000; // 1 Hz
  }
  return points;
}

/// Generate a polygon with [n] vertices (regular polygon around center).
List<List<double>> _generatePolygon(
  int n, {
  double centerLat = 37.422,
  double centerLng = -122.084,
  double r = 0.002,
}) {
  final vertices = <List<double>>[];
  for (var i = 0; i < n; i++) {
    final angle = 2 * math.pi * i / n;
    vertices.add([
      centerLat + r * math.cos(angle),
      centerLng + r * math.sin(angle),
    ]);
  }
  return vertices;
}

/// Generate a location map for serialization benchmarks.
Map<String, Object?> _generateLocationMap() {
  return <String, Object?>{
    'uuid': 'loc_${_rng.nextInt(1000000)}',
    'timestamp': '2024-11-01T12:34:56.789Z',
    'event': 'motionchange',
    'is_moving': true,
    'odometer': 12345.6,
    'coords': <String, Object?>{
      'latitude': 37.4220 + _rng.nextDouble() * 0.001,
      'longitude': -122.0841 + _rng.nextDouble() * 0.001,
      'accuracy': 16.0,
      'speed': 1.5,
      'speed_accuracy': 0.5,
      'heading': 90.0,
      'heading_accuracy': 5.0,
      'altitude': 30.0,
      'altitude_accuracy': 10.0,
      'floor': null,
      'ellipsoidal_altitude': null,
    },
    'activity': <String, Object?>{'type': 'walking', 'confidence': 85},
    'battery': <String, Object?>{'level': 0.75, 'is_charging': false},
    'extras': <String, Object?>{},
    'is_mock': false,
    'mock_heuristics': null,
    'locationSource': 'gps',
    'reducedAccuracy': false,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Benchmark: Kalman Filter
// ─────────────────────────────────────────────────────────────────────────────

void _benchKalmanFilter() {
  final track = _generateTrack(100);

  // Single process() call
  _bench('kalman_process_single', () {
    final kf = KalmanLocationFilter();
    kf.process(
      latitude: track[0].lat,
      longitude: track[0].lng,
      accuracy: track[0].acc,
      timestampMs: track[0].ts,
    );
  });

  // Process 100 sequential fixes
  _bench('kalman_process_100_fixes', () {
    final kf = KalmanLocationFilter();
    for (final p in track) {
      kf.process(
        latitude: p.lat,
        longitude: p.lng,
        accuracy: p.acc,
        timestampMs: p.ts,
      );
    }
  });

  // Process 1000 sequential fixes
  final track1k = _generateTrack(1000);
  _bench('kalman_process_1k_fixes', () {
    final kf = KalmanLocationFilter();
    for (final p in track1k) {
      kf.process(
        latitude: p.lat,
        longitude: p.lng,
        accuracy: p.acc,
        timestampMs: p.ts,
      );
    }
  });

  // Reset
  _bench('kalman_reset', () {
    final kf = KalmanLocationFilter();
    kf.process(
      latitude: 37.422,
      longitude: -122.084,
      accuracy: 16.0,
      timestampMs: 1700000000000,
    );
    kf.reset();
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Benchmark: Haversine
// ─────────────────────────────────────────────────────────────────────────────

void _benchHaversine() {
  _bench('haversine_single', () {
    GeoUtils.haversine(37.422, -122.084, 37.423, -122.083);
  });

  // 1000 sequential distance calls
  final track = _generateTrack(1001);
  _bench('haversine_1k_pairs', () {
    for (var i = 0; i < 1000; i++) {
      GeoUtils.haversine(
        track[i].lat,
        track[i].lng,
        track[i + 1].lat,
        track[i + 1].lng,
      );
    }
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Benchmark: Point-in-Polygon
// ─────────────────────────────────────────────────────────────────────────────

void _benchPointInPolygon() {
  for (final vertexCount in [4, 10, 50, 100, 500]) {
    final poly = _generatePolygon(vertexCount);
    _bench('pip_${vertexCount}v', () {
      GeoUtils.isPointInPolygon(lat: 37.422, lng: -122.084, vertices: poly);
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Benchmark: Geofence Evaluator
// ─────────────────────────────────────────────────────────────────────────────

void _benchGeofenceEvaluator() {
  // Circular geofences
  for (final count in [10, 100, 500]) {
    final geofences = <Map<String, Object?>>[];
    for (var i = 0; i < count; i++) {
      geofences.add({
        'identifier': 'geo_$i',
        'latitude': 37.422 + _rng.nextDouble() * 0.01,
        'longitude': -122.084 + _rng.nextDouble() * 0.01,
        'radius': 100.0 + _rng.nextDouble() * 500,
      });
    }
    _bench('geofence_eval_${count}_circular', () {
      final eval = GeofenceEvaluator();
      eval.evaluateProximity(
        latitude: 37.4225,
        longitude: -122.0835,
        geofences: geofences,
      );
    });
  }

  // Polygon geofences
  for (final count in [10, 50]) {
    final geofences = <Map<String, Object?>>[];
    for (var i = 0; i < count; i++) {
      final lat = 37.422 + _rng.nextDouble() * 0.01;
      final lng = -122.084 + _rng.nextDouble() * 0.01;
      geofences.add({
        'identifier': 'poly_$i',
        'latitude': lat,
        'longitude': lng,
        'radius': 0,
        'vertices': _generatePolygon(6, centerLat: lat, centerLng: lng),
      });
    }
    _bench('geofence_eval_${count}_polygon_6v', () {
      final eval = GeofenceEvaluator();
      eval.evaluateProximity(
        latitude: 37.4225,
        longitude: -122.0835,
        geofences: geofences,
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Benchmark: Location Processor
// ─────────────────────────────────────────────────────────────────────────────

void _benchLocationProcessor() {
  final track = _generateTrack(1000);

  // Full pipeline, 1000 fixes
  _bench('processor_1k_fixes', () {
    final proc = LocationProcessor(distanceFilter: 10);
    for (final p in track) {
      proc.process(
        latitude: p.lat,
        longitude: p.lng,
        accuracy: p.acc,
        speed: 1.5,
        timestampMs: p.ts,
      );
    }
  });

  // With adaptive mode
  _bench('processor_1k_adaptive', () {
    final proc = LocationProcessor(
      distanceFilter: 10,
      enableAdaptiveMode: true,
    );
    for (final p in track) {
      proc.process(
        latitude: p.lat,
        longitude: p.lng,
        accuracy: p.acc,
        speed: 1.5,
        timestampMs: p.ts,
        adaptiveContext: const AdaptiveContext(
          batteryLevel: 0.75,
          activityType: ActivityType.walking,
          activityConfidence: ActivityConfidence.high,
          speed: 1.5,
        ),
      );
    }
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Benchmark: Trip Manager
// ─────────────────────────────────────────────────────────────────────────────

void _benchTripManager() {
  final track = _generateTrack(5000);

  _bench('trip_manager_5k_waypoints', () {
    final tm = TripManager();
    tm.onMotionStateChanged(
      isMoving: true,
      latitude: track[0].lat,
      longitude: track[0].lng,
      timestamp: DateTime.fromMillisecondsSinceEpoch(track[0].ts),
    );
    for (final p in track) {
      tm.onLocationReceived(
        latitude: p.lat,
        longitude: p.lng,
        timestamp: DateTime.fromMillisecondsSinceEpoch(p.ts),
      );
    }
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Benchmark: Schedule Parser
// ─────────────────────────────────────────────────────────────────────────────

void _benchScheduleParser() {
  _bench('schedule_parse', () {
    ScheduleParser.parse('1-5 09:00-17:00');
  });

  _bench('schedule_matches', () {
    ScheduleParser.matchesSchedule(
      '1-5 09:00-17:00',
      DateTime(2024, 3, 13, 12, 0), // Wednesday noon
    );
  });

  _bench('schedule_isWithin_5_entries', () {
    ScheduleParser.isWithinSchedule([
      '1-5 06:00-09:00',
      '1-5 09:00-17:00',
      '1-5 17:00-22:00',
      '6-7 08:00-20:00',
      '1-7 22:00-06:00',
    ], DateTime(2024, 3, 13, 12, 0));
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Benchmark: Adaptive Sampling Engine
// ─────────────────────────────────────────────────────────────────────────────

void _benchAdaptiveSampling() {
  final engine = AdaptiveSamplingEngine(
    baseDistanceFilter: 10,
    elasticityMultiplier: 1.0,
  );

  _bench('adaptive_compute', () {
    engine.compute(
      const AdaptiveContext(
        batteryLevel: 0.5,
        activityType: ActivityType.inVehicle,
        activityConfidence: ActivityConfidence.high,
        speed: 20.0,
      ),
    );
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Benchmark: Location Serialization
// ─────────────────────────────────────────────────────────────────────────────

void _benchLocationSerialization() {
  final map = _generateLocationMap();

  _bench('location_fromMap', () {
    Location.fromMap(map);
  });

  final loc = Location.fromMap(map);
  _bench('location_toMap', () {
    loc.toMap();
  });

  _bench('location_fromMap_toMap_roundtrip', () {
    Location.fromMap(map).toMap();
  });

  _bench('location_copyWithCoords', () {
    loc.copyWithCoords(latitude: 37.4225, longitude: -122.0835);
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Benchmark: Geofence Serialization
// ─────────────────────────────────────────────────────────────────────────────

void _benchGeofenceSerialization() {
  final circularMap = <String, Object?>{
    'identifier': 'geo_1',
    'latitude': 37.422,
    'longitude': -122.084,
    'radius': 200.0,
    'notifyOnEntry': true,
    'notifyOnExit': true,
    'notifyOnDwell': false,
    'loiteringDelay': 0,
    'extras': <String, Object?>{},
    'vertices': <List<double>>[],
  };

  _bench('geofence_fromMap_circular', () {
    Geofence.fromMap(circularMap);
  });

  final polygonMap = <String, Object?>{
    ...circularMap,
    'identifier': 'poly_1',
    'radius': 0,
    'vertices': [
      [37.423, -122.085],
      [37.423, -122.083],
      [37.421, -122.083],
      [37.421, -122.085],
    ],
  };

  _bench('geofence_fromMap_polygon', () {
    Geofence.fromMap(polygonMap);
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Benchmark: Delta Encoder
// ─────────────────────────────────────────────────────────────────────────────

void _benchDeltaEncoder() {
  // Generate realistic location batches
  List<Map<String, Object?>> generateBatch(int n) {
    final batch = <Map<String, Object?>>[];
    var lat = 37.4220;
    var lng = -122.0841;
    var ts = 1700000000000;
    for (var i = 0; i < n; i++) {
      lat += (_rng.nextDouble() - 0.5) * 0.0002;
      lng += (_rng.nextDouble() - 0.5) * 0.0002;
      batch.add(<String, Object?>{
        'coords': <String, Object?>{
          'latitude': lat,
          'longitude': lng,
          'accuracy': 10.0 + _rng.nextDouble() * 20,
          'speed': 1.0 + _rng.nextDouble() * 5,
          'heading': _rng.nextDouble() * 360,
          'altitude': 30.0 + _rng.nextDouble() * 5,
          'speed_accuracy': 0.5,
          'heading_accuracy': 5.0,
          'altitude_accuracy': 10.0,
        },
        'timestamp': '2024-11-01T12:34:${(56 + i) % 60}.000Z',
        'battery': <String, Object?>{'level': 0.75, 'is_charging': false},
      });
      ts += 1000;
    }
    return batch;
  }

  for (final size in [10, 100, 500]) {
    final batch = generateBatch(size);
    _bench('delta_encode_$size', () {
      DeltaEncoder.encode(batch);
    });

    final encoded = DeltaEncoder.encode(batch);
    _bench('delta_decode_$size', () {
      DeltaEncoder.decode(encoded);
    });
  }

  // Round-trip
  final batch100 = generateBatch(100);
  _bench('delta_roundtrip_100', () {
    DeltaEncoder.decode(DeltaEncoder.encode(batch100));
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Benchmark: Battery Budget Engine
// ─────────────────────────────────────────────────────────────────────────────

void _benchBatteryBudget() {
  // Single sample processing
  _bench('battery_budget_single_sample', () {
    final engine = BatteryBudgetEngine(targetBudgetPerHour: 5.0);
    engine.processSample(0.75);
  });

  // Simulate 1-hour drain: 60 samples (1 per minute) with decreasing battery
  _bench('battery_budget_60_samples', () {
    final engine = BatteryBudgetEngine(targetBudgetPerHour: 5.0);
    for (var i = 0; i < 60; i++) {
      engine.processSample(1.0 - i * 0.01);
    }
  });

  // Heavy drain scenario — engine must adjust aggressively
  _bench('battery_budget_heavy_drain', () {
    final engine = BatteryBudgetEngine(
      targetBudgetPerHour: 3.0,
      initialDistanceFilter: 10.0,
    );
    for (var i = 0; i < 120; i++) {
      engine.processSample(1.0 - i * 0.005);
    }
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Benchmark: Carbon Estimator
// ─────────────────────────────────────────────────────────────────────────────

void _benchCarbonEstimator() {
  final track = _generateTrack(100);

  // Single trip with 100 locations
  _bench('carbon_trip_100_locations', () {
    final est = CarbonEstimator();
    est.startTrip();
    est.setActivity('in_vehicle');
    for (final p in track) {
      est.onLocationReceived(p.lat, p.lng);
    }
    est.endTrip();
  });

  // Per-location cost (hot path)
  _bench('carbon_onLocation', () {
    final est = CarbonEstimator();
    est.startTrip();
    est.setActivity('walking');
    est.onLocationReceived(37.422, -122.084);
    est.onLocationReceived(37.4221, -122.0841);
  });

  // Activity switching
  _bench('carbon_setActivity', () {
    final est = CarbonEstimator();
    est.startTrip();
    est.setActivity('walking');
    est.setActivity('in_vehicle');
    est.setActivity('on_bicycle');
  });

  // Cumulative report generation
  final est = CarbonEstimator();
  for (var trip = 0; trip < 10; trip++) {
    est.startTrip();
    est.setActivity('in_vehicle');
    for (final p in track) {
      est.onLocationReceived(p.lat, p.lng);
    }
    est.endTrip();
  }
  _bench('carbon_cumulative_report', () {
    est.getCumulativeReport();
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Benchmark: Persist Decider
// ─────────────────────────────────────────────────────────────────────────────

void _benchPersistDecider() {
  _bench('persist_decider_location', () {
    PersistDecider.shouldPersistLocation(0, event: 'motionchange');
    PersistDecider.shouldPersistLocation(1, event: 'motionchange');
    PersistDecider.shouldPersistLocation(2, event: 'geofence');
    PersistDecider.shouldPersistLocation(3, event: 'heartbeat');
  });

  _bench('persist_decider_geofence', () {
    PersistDecider.shouldPersistGeofence(0);
    PersistDecider.shouldPersistGeofence(1);
    PersistDecider.shouldPersistGeofence(2);
    PersistDecider.shouldPersistGeofence(3);
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Benchmark: Config Serialization
// ─────────────────────────────────────────────────────────────────────────────

void _benchConfigSerialization() {
  final configMap = const Config().toMap();

  _bench('config_fromMap', () {
    Config.fromMap(configMap);
  });

  final config = const Config();
  _bench('config_toMap', () {
    config.toMap();
  });

  _bench('config_roundtrip', () {
    Config.fromMap(const Config().toMap());
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Benchmark: State Serialization
// ─────────────────────────────────────────────────────────────────────────────

void _benchStateSerialization() {
  final stateMap = <String, Object?>{
    'enabled': true,
    'trackingMode': 1,
    'isMoving': true,
    'schedulerEnabled': false,
    'odometer': 12345.6,
    'didLaunchInBackground': false,
    'didDeviceReboot': false,
    'config': const Config().toMap(),
  };

  _bench('state_fromMap', () {
    State.fromMap(stateMap);
  });

  final state = State.fromMap(stateMap);
  _bench('state_toMap', () {
    state.toMap();
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Benchmark: RouteContext Serialization
// ─────────────────────────────────────────────────────────────────────────────

void _benchRouteContext() {
  const ctx = RouteContext(
    ownerId: 'owner-1',
    driverId: 'driver-7',
    taskId: 'delivery-42',
    trackingSessionId: 'sess-abc',
    startedAt: '2025-01-01T00:00:00Z',
    custom: {'region': 'eu-west', 'zone': 'A1'},
  );

  _bench('route_context_toMap', () {
    ctx.toMap();
  });

  final map = ctx.toMap();
  _bench('route_context_fromMap', () {
    RouteContext.fromMap(map);
  });

  _bench('route_context_roundtrip', () {
    RouteContext.fromMap(ctx.toMap());
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Benchmark: SyncBodyContext Serialization
// ─────────────────────────────────────────────────────────────────────────────

void _benchSyncBodyContext() {
  // 50-location batch (realistic sync payload)
  final locations = <Map<String, Object?>>[];
  for (var i = 0; i < 50; i++) {
    locations.add(_generateLocationMap());
  }
  final ctx = SyncBodyContext(locations: locations);

  _bench('sync_body_context_toMap_50', () {
    ctx.toMap();
  });

  final map = ctx.toMap();
  _bench('sync_body_context_fromMap_50', () {
    SyncBodyContext.fromMap(map);
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Benchmark: HttpConfig with SSL Pinning
// ─────────────────────────────────────────────────────────────────────────────

void _benchHttpConfigSsl() {
  const http = HttpConfig(
    url: 'https://api.example.com/locations',
    method: HttpMethod.post,
    headers: {'Authorization': 'Bearer tok', 'X-Device': 'abc'},
    sslPinningCertificates: ['MIIBcert1base64==', 'MIIBcert2base64=='],
    sslPinningFingerprints: ['sha256/AAAA', 'sha256/BBBB'],
  );

  _bench('http_config_ssl_toMap', () {
    http.toMap();
  });

  final map = http.toMap();
  _bench('http_config_ssl_fromMap', () {
    HttpConfig.fromMap(map);
  });

  _bench('http_config_ssl_roundtrip', () {
    HttpConfig.fromMap(http.toMap());
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  test('Tracelet Performance Benchmark', () {
    print('Tracelet Performance Benchmark');
    print('Dart ${Platform.version.split(' ').first}');
    print(
      'Date: ${DateTime.now().toUtc().toIso8601String().substring(0, 19)}Z',
    );
    print('');

    _benchKalmanFilter();
    _benchHaversine();
    _benchPointInPolygon();
    _benchGeofenceEvaluator();
    _benchLocationProcessor();
    _benchTripManager();
    _benchScheduleParser();
    _benchAdaptiveSampling();
    _benchLocationSerialization();
    _benchGeofenceSerialization();
    _benchDeltaEncoder();
    _benchBatteryBudget();
    _benchCarbonEstimator();
    _benchPersistDecider();
    _benchConfigSerialization();
    _benchStateSerialization();
    _benchRouteContext();
    _benchSyncBodyContext();
    _benchHttpConfigSsl();

    // Print results table
    print('');
    print('| Benchmark | ops/sec | µs/op |');
    print('|---|---:|---:|');
    for (final r in _results) {
      print(
        '| ${r.name} | ${r.opsPerSec.toStringAsFixed(0)} | ${r.usPerOp.toStringAsFixed(2)} |',
      );
    }

    // Print JSON for CI
    print('');
    print('--- JSON ---');
    print('{');
    for (var i = 0; i < _results.length; i++) {
      final r = _results[i];
      final comma = i < _results.length - 1 ? ',' : '';
      print('  "${r.name}": ${r.usPerOp.toStringAsFixed(2)}$comma');
    }
    print('}');

    // Verify all benchmarks produced results
    expect(_results.length, greaterThanOrEqualTo(48));
    for (final r in _results) {
      expect(
        r.opsPerSec,
        greaterThan(0),
        reason: '${r.name} should have >0 ops/sec',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
