import 'package:meta/meta.dart';
import 'package:tracelet/src/models/_helpers.dart';
import 'package:tracelet/src/models/audit_config.dart' show AuditConfig;
import 'package:tracelet/tracelet.dart' show AuditConfig;
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

/// A recorded location from the native platform.
///
/// Contains GPS coordinates, motion state, activity recognition data,
/// battery state, and metadata.
///
/// ```dart
/// Tracelet.onLocation((Location loc) {
///   print('${loc.coords.latitude}, ${loc.coords.longitude}');
///   print('Moving: ${loc.isMoving}');
/// });
/// ```
@immutable
class Location {
  /// Creates a new [Location].
  const Location({
    required this.coords,
    required this.timestamp,
    required this.isMoving,
    required this.uuid,
    required this.odometer,
    this.locationSource = 'unknown',
    this.reducedAccuracy = false,
    this.isMock = false,
    this.mockHeuristics,
    this.activity = const LocationActivity(),
    this.battery = const LocationBattery(),
    this.extras = const <String, Object?>{},
    this.event,
    this.auditHash,
    this.auditPreviousHash,
    this.auditChainIndex,
    this.address,
  });

  /// Creates a [Location] from a Pigeon [TlLocation] without map round-trip.
  factory Location.fromTl(TlLocation tl) {
    final c = tl.coords;
    final ext = tl.extras ?? const <String, Object?>{};

    // Extract metadata injected by EventDispatcher into extras because Pigeon
    // TlLocation doesn't natively support these fields.
    final synthesizedExtras = Map<String, Object?>.from(ext);
    final isMock = ensureBool(
      synthesizedExtras.remove('is_mock'),
      fallback: false,
    );
    final locationSource = _ensureLocationSource(
      synthesizedExtras.remove('locationSource'),
    );
    final reducedAccuracy = ensureBool(
      synthesizedExtras.remove('reducedAccuracy'),
      fallback: false,
    );
    final mockHeuristics = _parseMockHeuristics(
      synthesizedExtras.remove('mockHeuristics'),
    );
    final auditHash = synthesizedExtras.remove('audit_hash') as String?;
    final auditPreviousHash =
        synthesizedExtras.remove('audit_previous_hash') as String?;
    final auditChainIndex =
        (synthesizedExtras.remove('audit_chain_index') as num?)?.toInt();

    return Location(
      coords: Coords(
        latitude: c.latitude,
        longitude: c.longitude,
        accuracy: c.accuracy,
        speed: c.speed,
        heading: c.heading,
        altitude: c.altitude,
        altitudeAccuracy: c.altitudeAccuracy,
        speedAccuracy: c.speedAccuracy,
        headingAccuracy: c.headingAccuracy,
        floor: c.floor,
      ),
      timestamp: tl.timestamp,
      isMoving: tl.isMoving,
      uuid: tl.uuid,
      odometer: tl.odometer,
      event: tl.event,
      isMock: isMock,
      locationSource: locationSource,
      reducedAccuracy: reducedAccuracy,
      mockHeuristics: mockHeuristics,
      auditHash: auditHash,
      auditPreviousHash: auditPreviousHash,
      auditChainIndex: auditChainIndex,
      activity: tl.activity != null
          ? LocationActivity.fromTl(tl.activity!)
          : const LocationActivity(),
      battery: LocationBattery(
        level: tl.battery.level,
        isCharging: tl.battery.isCharging,
      ),
      extras: synthesizedExtras,
      address: tl.address != null ? Address.fromTl(tl.address!) : null,
    );
  }

  /// Creates a [Location] from a platform map.
  factory Location.fromMap(Map<String, Object?> map) {
    final coordsMap = safeMap(map['coords']) ?? const <String, Object?>{};
    final activityMap = safeMap(map['activity']);
    final batteryMap = safeMap(map['battery']);
    final addressMap = safeMap(map['address']);
    final extrasRaw = map['extras'];

    return Location(
      coords: Coords.fromMap(coordsMap.isEmpty ? map : coordsMap),
      timestamp: ensureString(map['timestamp']),
      isMoving: ensureBool(
        map['is_moving'] ?? map['isMoving'],
        fallback: false,
      ),
      uuid: ensureString(map['uuid']),
      odometer: ensureDouble(map['odometer'], fallback: 0),
      locationSource: _ensureLocationSource(
        map['locationSource'] ?? map['location_source'],
      ),
      reducedAccuracy: ensureBool(
        map['reducedAccuracy'] ?? map['reduced_accuracy'],
        fallback: false,
      ),
      isMock: ensureBool(
        map['is_mock'] ?? map['isMock'] ?? map['mock'],
        fallback: false,
      ),
      mockHeuristics: _parseMockHeuristics(map['mockHeuristics']),
      activity: activityMap != null
          ? LocationActivity.fromMap(activityMap)
          : const LocationActivity(),
      battery: batteryMap != null
          ? LocationBattery.fromMap(batteryMap)
          : const LocationBattery(),
      address: addressMap != null ? Address.fromMap(addressMap) : null,
      // Use Map.from() to avoid per-entry MapEntry allocation (D-L4).
      extras: extrasRaw is Map
          ? Map<String, Object?>.from(extrasRaw)
          : const <String, Object?>{},
      event: map['event'] is String
          ? map['event']! as String
          : map['event']?.toString(),
      auditHash: (map['audit_hash'] ?? map['auditHash']) as String?,
      auditPreviousHash:
          (map['audit_previous_hash'] ?? map['auditPreviousHash']) as String?,
      auditChainIndex:
          (map['audit_chain_index'] ?? map['auditChainIndex']) is num
          ? ((map['audit_chain_index'] ?? map['auditChainIndex'])! as num)
                .toInt()
          : null,
    );
  }

  /// Geographic coordinates and accuracy metrics.
  final Coords coords;

  /// ISO 8601 timestamp of when this location was recorded.
  final String timestamp;

  /// Whether the device was in a moving state when this location was recorded.
  final bool isMoving;

  /// Unique identifier for this location record.
  final String uuid;

  /// Distance (in meters) traveled since tracking started.
  final double odometer;

  /// The source that provided this location fix.
  ///
  /// Possible values:
  /// - `'gps'` — GPS/GNSS satellite fix (accuracy typically ≤ 50m).
  /// - `'wifi'` — Wi-Fi positioning (accuracy typically 50–200m).
  /// - `'cell'` — Cell tower triangulation (accuracy typically > 200m).
  /// - `'network'` — Android network provider (Wi-Fi or cell, unspecified).
  /// - `'unknown'` — Source could not be determined.
  ///
  /// On **Android**, the classification uses the provider name from
  /// `FusedLocationProviderClient` combined with horizontal accuracy.
  /// On **iOS**, iOS does not expose provider names, so the classification
  /// is based on `horizontalAccuracy` alone.
  final String locationSource;

  /// Whether this location was obtained under iOS 14+ reduced accuracy
  /// authorization (approximate location, ~5 km).
  ///
  /// Always `false` on Android and pre-iOS 14 devices.
  final bool reducedAccuracy;

  /// Whether this location was generated by a mock/spoofing provider.
  ///
  /// - **Android**: Uses `Location.isFromMockProvider()` (API < 31) or
  ///   `Location.isMock()` (API 31+).
  /// - **iOS 15+**: Uses `CLLocation.sourceInformation?.isSimulatedBySoftware`.
  /// - **iOS < 15 / Web**: Always `false` (API not available).
  ///
  /// When `Config.geo.filter.rejectMockLocations` is `true`, locations with
  /// `isMock == true` are automatically rejected and never delivered.
  final bool isMock;

  /// Detailed heuristic analysis data from the native mock detection engine.
  ///
  /// Only populated when `Config.geo.filter.mockDetectionLevel` is set to
  /// [MockDetectionLevel.heuristic]. When detection is `disabled` or `basic`,
  /// this is always `null`.
  ///
  /// Contains platform-specific signals such as satellite count (Android),
  /// elapsed realtime drift (Android), timestamp drift (iOS), and the raw
  /// platform mock flag. Useful for logging, analytics, or server-side
  /// anti-spoofing validation.
  final MockHeuristics? mockHeuristics;

  /// The detected activity at the time of this location.
  final LocationActivity activity;

  /// Battery state at the time of this location.
  final LocationBattery battery;

  /// Arbitrary extra data attached to this location.
  final Map<String, Object?> extras;

  /// The event that triggered this location (e.g. `'motionchange'`,
  /// `'providerchange'`, `'heartbeat'`).
  final String? event;

  /// **Enterprise** — SHA-256 audit hash for this location record.
  ///
  /// Only populated when [AuditConfig.enabled] is `true`. Part of the
  /// tamper-proof audit chain — computed from the previous hash and
  /// the canonical fields of this record.
  final String? auditHash;

  /// **Enterprise** — The hash of the previous record in the audit chain.
  ///
  /// For the first record, this is the genesis hash. `null` when audit
  /// trail is disabled.
  final String? auditPreviousHash;

  /// **Enterprise** — Sequential index in the audit chain (0-based).
  ///
  /// `null` when audit trail is disabled.
  final int? auditChainIndex;

  /// The reverse geocoded human-readable address.
  ///
  /// Only populated when `Config.geo.resolveAddress` is `true`.
  final Address? address;

  /// Serializes to a map.
  /// Serializes to a JSON-compatible map.
  Map<String, Object?> toJson() => toMap();

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'coords': coords.toMap(),
      'timestamp': timestamp,
      'is_moving': isMoving,
      'uuid': uuid,
      'odometer': odometer,
      'locationSource': locationSource,
      'reducedAccuracy': reducedAccuracy,
      'is_mock': isMock,
      'mockHeuristics': mockHeuristics?.toMap(),
      'activity': activity.toMap(),
      'battery': battery.toMap(),
      'extras': extras,
      'event': event,
      if (auditHash != null) 'audit_hash': auditHash,
      if (auditPreviousHash != null) 'audit_previous_hash': auditPreviousHash,
      if (auditChainIndex != null) 'audit_chain_index': auditChainIndex,
      if (address != null) 'address': address?.toMap(),
    };
  }

  @override
  String toString() =>
      'Location(lat: ${coords.latitude}, lng: ${coords.longitude}, '
      'isMoving: $isMoving, isMock: $isMock, '
      'mockHeuristics: $mockHeuristics, uuid: $uuid)';

  /// Returns a copy of this [Location] with updated coordinates.
  ///
  /// Used by the Kalman filter to produce a smoothed location without
  /// the overhead of full `toMap()/fromMap()` round-trip serialization.
  Location copyWithCoords({
    double? latitude,
    double? longitude,
    double? speed,
  }) {
    return Location(
      coords: Coords(
        latitude: latitude ?? coords.latitude,
        longitude: longitude ?? coords.longitude,
        altitude: coords.altitude,
        speed: speed ?? coords.speed,
        heading: coords.heading,
        accuracy: coords.accuracy,
        speedAccuracy: coords.speedAccuracy,
        headingAccuracy: coords.headingAccuracy,
        altitudeAccuracy: coords.altitudeAccuracy,
        floor: coords.floor,
      ),
      timestamp: timestamp,
      isMoving: isMoving,
      uuid: uuid,
      odometer: odometer,
      locationSource: locationSource,
      reducedAccuracy: reducedAccuracy,
      isMock: isMock,
      mockHeuristics: mockHeuristics,
      activity: activity,
      battery: battery,
      extras: extras,
      event: event,
      auditHash: auditHash,
      auditPreviousHash: auditPreviousHash,
      auditChainIndex: auditChainIndex,
      address: address,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Location &&
          runtimeType == other.runtimeType &&
          uuid == other.uuid &&
          address == other.address;

  @override
  int get hashCode => Object.hash(uuid, address);
}

// ---------------------------------------------------------------------------
// Address
// ---------------------------------------------------------------------------

/// A reverse geocoded human-readable address.
@immutable
class Address {
  /// Creates a new [Address].
  const Address({
    this.street,
    this.city,
    this.state,
    this.postalCode,
    this.country,
  });

  /// Creates an [Address] from a Pigeon [TlAddress].
  factory Address.fromTl(TlAddress tl) {
    return Address(
      street: tl.street,
      city: tl.city,
      state: tl.state,
      postalCode: tl.postalCode,
      country: tl.country,
    );
  }

  /// Creates an [Address] from a platform map.
  factory Address.fromMap(Map<String, Object?> map) {
    return Address(
      street: map['street'] as String?,
      city: map['city'] as String?,
      state: map['state'] as String?,
      postalCode: map['postal_code'] as String? ?? map['postalCode'] as String?,
      country: map['country'] as String?,
    );
  }

  /// The street name and number.
  final String? street;

  /// The city or locality.
  final String? city;

  /// The state, province, or administrative area.
  final String? state;

  /// The postal code or ZIP code.
  final String? postalCode;

  /// The country name.
  final String? country;

  /// Serializes to a map.
  /// Serializes to a JSON-compatible map.
  Map<String, Object?> toJson() => toMap();

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (street != null) 'street': street,
      if (city != null) 'city': city,
      if (state != null) 'state': state,
      if (postalCode != null) 'postal_code': postalCode,
      if (country != null) 'country': country,
    };
  }

  @override
  String toString() {
    final parts = [
      street,
      city,
      state,
      postalCode,
      country,
    ].where((e) => e != null);
    return 'Address(${parts.join(', ')})';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Address &&
          runtimeType == other.runtimeType &&
          street == other.street &&
          city == other.city &&
          state == other.state &&
          postalCode == other.postalCode &&
          country == other.country;

  @override
  int get hashCode => Object.hash(street, city, state, postalCode, country);
}

MockHeuristics? _parseMockHeuristics(Object? raw) {
  if (raw == null) return null;
  if (raw is Map) {
    return MockHeuristics.fromMap(
      raw.map<String, Object?>(
        (Object? k, Object? v) => MapEntry(k.toString(), v),
      ),
    );
  }
  return null;
}

/// Returns a valid location source string, defaulting to `'unknown'`.
String _ensureLocationSource(Object? value) {
  if (value is String && value.isNotEmpty) return value;
  return 'unknown';
}

// ---------------------------------------------------------------------------
// MockHeuristics
// ---------------------------------------------------------------------------

/// Detailed heuristic data from the native mock-location detection engine.
///
/// Only populated when [MockDetectionLevel.heuristic] is active. Contains
/// platform-specific signals that indicate whether a location might be
/// spoofed, even when the platform API flag (`isMock`) is not set.
///
/// The exact set of populated fields depends on the platform:
///
/// | Field                     | Android | iOS |
/// |---------------------------|---------|-----|
/// | `satellites`              | ✅       | ❌   |
/// | `elapsedRealtimeDriftMs`  | ✅       | ❌   |
/// | `timestampDriftMs`        | ❌       | ✅   |
/// | `platformFlagMock`        | ✅       | ✅   |
///
/// ```dart
/// Tracelet.onLocation((Location loc) {
///   if (loc.mockHeuristics != null) {
///     print('Satellites: ${loc.mockHeuristics!.satellites}');
///     print('Drift: ${loc.mockHeuristics!.elapsedRealtimeDriftMs}ms');
///   }
/// });
/// ```
@immutable
class MockHeuristics {
  /// Creates a new [MockHeuristics].
  const MockHeuristics({
    this.satellites,
    this.elapsedRealtimeDriftMs,
    this.timestampDriftMs,
    this.platformFlagMock,
  });

  /// Creates a [MockHeuristics] from a platform map.
  factory MockHeuristics.fromMap(Map<String, Object?> map) {
    return MockHeuristics(
      satellites: map['satellites'] is num
          ? (map['satellites']! as num).toInt()
          : null,
      elapsedRealtimeDriftMs: map['elapsedRealtimeDriftMs'] is num
          ? (map['elapsedRealtimeDriftMs']! as num).toDouble()
          : null,
      timestampDriftMs: map['timestampDriftMs'] is num
          ? (map['timestampDriftMs']! as num).toDouble()
          : null,
      platformFlagMock: map['platformFlagMock'] is bool
          ? map['platformFlagMock']! as bool
          : null,
    );
  }

  /// Number of GPS satellites used for this fix (Android only).
  ///
  /// Real GPS fixes outdoors typically report 4–30 satellites. Mock locations
  /// from spoofing apps often report `0`. A value of `-1` means the satellite
  /// count was not available in the location extras.
  final int? satellites;

  /// Difference in milliseconds between the location's
  /// `elapsedRealtimeNanos` and `SystemClock.elapsedRealtimeNanos()`
  /// (Android only).
  ///
  /// Real GPS hardware sets `elapsedRealtimeNanos` using the monotonic clock,
  /// so drift should be very small (< 1 second). Large positive values
  /// (> 10 seconds) suggest the location was injected or replayed. Negative
  /// values (location claims to be from the future) are also suspicious.
  final double? elapsedRealtimeDriftMs;

  /// Wall-clock timestamp drift in milliseconds (iOS only).
  ///
  /// Difference between `Date()` and `location.timestamp`. Real locations
  /// have small drift (< 1 second). Large drift suggests spoofing or replay.
  final double? timestampDriftMs;

  /// Raw platform API mock flag value.
  ///
  /// - **Android**: `Location.isMock()` (API 31+) or
  ///   `Location.isFromMockProvider()` (API < 31).
  /// - **iOS 15+**: `CLLocation.sourceInformation?.isSimulatedBySoftware`.
  ///
  /// This is the same value as [Location.isMock] at detection level `basic`,
  /// but exposed here for logging/analytics alongside the heuristic signals.
  final bool? platformFlagMock;

  /// Serializes to a map.
  /// Serializes to a JSON-compatible map.
  Map<String, Object?> toJson() => toMap();

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (satellites != null) 'satellites': satellites,
      if (elapsedRealtimeDriftMs != null)
        'elapsedRealtimeDriftMs': elapsedRealtimeDriftMs,
      if (timestampDriftMs != null) 'timestampDriftMs': timestampDriftMs,
      if (platformFlagMock != null) 'platformFlagMock': platformFlagMock,
    };
  }

  @override
  String toString() =>
      'MockHeuristics(satellites: $satellites, '
      'elapsedRealtimeDriftMs: $elapsedRealtimeDriftMs, '
      'timestampDriftMs: $timestampDriftMs, '
      'platformFlagMock: $platformFlagMock)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MockHeuristics &&
          runtimeType == other.runtimeType &&
          satellites == other.satellites &&
          elapsedRealtimeDriftMs == other.elapsedRealtimeDriftMs &&
          timestampDriftMs == other.timestampDriftMs &&
          platformFlagMock == other.platformFlagMock;

  @override
  int get hashCode => Object.hash(
    satellites,
    elapsedRealtimeDriftMs,
    timestampDriftMs,
    platformFlagMock,
  );
}

// ---------------------------------------------------------------------------
// Coords
// ---------------------------------------------------------------------------

/// Geographic coordinates with accuracy metrics.
@immutable
class Coords {
  /// Creates a new [Coords].
  const Coords({
    required this.latitude,
    required this.longitude,
    this.altitude = 0.0,
    this.speed = 0.0,
    this.heading = 0.0,
    this.accuracy = 0.0,
    this.speedAccuracy = 0.0,
    this.headingAccuracy = 0.0,
    this.altitudeAccuracy = 0.0,
    this.floor,
  });

  /// Creates [Coords] from a platform map.
  factory Coords.fromMap(Map<String, Object?> map) {
    return Coords(
      latitude: ensureDouble(map['latitude'], fallback: 0),
      longitude: ensureDouble(map['longitude'], fallback: 0),
      altitude: ensureDouble(map['altitude'], fallback: 0),
      speed: ensureDouble(map['speed'], fallback: 0),
      heading: ensureDouble(map['heading'], fallback: 0),
      accuracy: ensureDouble(map['accuracy'], fallback: 0),
      speedAccuracy: ensureDouble(
        map['speed_accuracy'] ?? map['speedAccuracy'],
        fallback: 0,
      ),
      headingAccuracy: ensureDouble(
        map['heading_accuracy'] ?? map['headingAccuracy'],
        fallback: 0,
      ),
      altitudeAccuracy: ensureDouble(
        map['altitude_accuracy'] ?? map['altitudeAccuracy'],
        fallback: 0,
      ),
      floor: map['floor'] as int?,
    );
  }

  /// Latitude in degrees.
  final double latitude;

  /// Longitude in degrees.
  final double longitude;

  /// Altitude in meters above sea level.
  final double altitude;

  /// Speed in meters per second.
  final double speed;

  /// Heading/bearing in degrees (0–360).
  final double heading;

  /// Horizontal accuracy in meters.
  final double accuracy;

  /// Speed accuracy in meters per second (Android only).
  final double speedAccuracy;

  /// Heading accuracy in degrees.
  final double headingAccuracy;

  /// Altitude accuracy in meters.
  final double altitudeAccuracy;

  /// The floor of the building (iOS only).
  final int? floor;

  /// Serializes to a map.
  /// Serializes to a JSON-compatible map.
  Map<String, Object?> toJson() => toMap();

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'speed': speed,
      'heading': heading,
      'accuracy': accuracy,
      'speed_accuracy': speedAccuracy,
      'heading_accuracy': headingAccuracy,
      'altitude_accuracy': altitudeAccuracy,
      'floor': floor,
    };
  }

  @override
  String toString() => 'Coords($latitude, $longitude ±${accuracy}m)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Coords &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

// ---------------------------------------------------------------------------
// LocationActivity
// ---------------------------------------------------------------------------

/// Activity recognition data associated with a location.
@immutable
class LocationActivity {
  /// Creates a new [LocationActivity].
  const LocationActivity({
    this.type = ActivityType.unknown,
    this.confidence = ActivityConfidence.low,
  });

  /// Creates a [LocationActivity] from a Pigeon [TlActivity].
  factory LocationActivity.fromTl(TlActivity tl) {
    var conf = ActivityConfidence.low;
    if (tl.confidence >= 75) {
      conf = ActivityConfidence.high;
    } else if (tl.confidence >= 50) {
      conf = ActivityConfidence.medium;
    }
    return LocationActivity(type: parseActivityType(tl.type), confidence: conf);
  }

  /// Creates a [LocationActivity] from a platform map.
  factory LocationActivity.fromMap(Map<String, Object?> map) {
    // Activity type can be sent as string or int
    var actType = ActivityType.unknown;
    final rawType = map['type'];
    if (rawType is int) {
      actType =
          ActivityType.values[rawType.clamp(0, ActivityType.values.length - 1)];
    } else if (rawType is String) {
      actType = parseActivityType(rawType);
    }

    var conf = ActivityConfidence.low;
    final rawConf = map['confidence'];
    if (rawConf is int) {
      // Native can send 0-100 confidence → map to enum
      if (rawConf >= 75) {
        conf = ActivityConfidence.high;
      } else if (rawConf >= 50) {
        conf = ActivityConfidence.medium;
      } else {
        conf = ActivityConfidence.low;
      }
    } else if (rawConf is String) {
      conf = ActivityConfidence.values.firstWhere(
        (e) => e.name == rawConf,
        orElse: () => ActivityConfidence.low,
      );
    }

    return LocationActivity(type: actType, confidence: conf);
  }

  /// Parses a native activity type string into an [ActivityType].
  ///
  /// Native layers emit snake_case (`in_vehicle`, `on_bicycle`, `on_foot`),
  /// which never matched the camelCase Dart enum names — those types silently
  /// collapsed to [ActivityType.unknown]. Accepts both spellings.
  static ActivityType parseActivityType(String raw) {
    switch (raw) {
      case 'in_vehicle':
        return ActivityType.inVehicle;
      case 'on_bicycle':
        return ActivityType.onBicycle;
      case 'on_foot':
        return ActivityType.onFoot;
      default:
        return ActivityType.values.firstWhere(
          (e) => e.name == raw,
          orElse: () => ActivityType.unknown,
        );
    }
  }

  /// The detected activity type.
  final ActivityType type;

  /// The confidence level of the detection.
  final ActivityConfidence confidence;

  /// Serializes to a map.
  /// Serializes to a JSON-compatible map.
  Map<String, Object?> toJson() => toMap();

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{'type': type.name, 'confidence': confidence.name};
  }

  @override
  String toString() => 'LocationActivity($type, $confidence)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocationActivity &&
          type == other.type &&
          confidence == other.confidence;

  @override
  int get hashCode => Object.hash(type, confidence);
}

// ---------------------------------------------------------------------------
// LocationBattery
// ---------------------------------------------------------------------------

/// Battery state associated with a location.
@immutable
class LocationBattery {
  /// Creates a new [LocationBattery].
  const LocationBattery({this.level = -1.0, this.isCharging = false});

  /// Creates a [LocationBattery] from a platform map.
  factory LocationBattery.fromMap(Map<String, Object?> map) {
    return LocationBattery(
      level: ensureDouble(map['level'], fallback: -1),
      isCharging: ensureBool(
        map['is_charging'] ?? map['isCharging'],
        fallback: false,
      ),
    );
  }

  /// Battery level from `0.0` to `1.0`, or `-1.0` if unknown.
  final double level;

  /// Whether the device is currently charging.
  final bool isCharging;

  /// Serializes to a map.
  /// Serializes to a JSON-compatible map.
  Map<String, Object?> toJson() => toMap();

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{'level': level, 'is_charging': isCharging};
  }

  @override
  String toString() =>
      'LocationBattery(level: ${(level * 100).toStringAsFixed(0)}%, '
      'charging: $isCharging)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocationBattery &&
          level == other.level &&
          isCharging == other.isCharging;

  @override
  int get hashCode => Object.hash(level, isCharging);
}
