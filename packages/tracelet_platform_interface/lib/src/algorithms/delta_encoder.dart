import 'dart:math' as math;

/// Encodes a batch of location maps into delta-compressed format.
///
/// Instead of sending full location objects for every record, sends one full
/// "reference" location followed by deltas: `{ Δlat, Δlng, Δspeed, ... }`.
///
/// Achieves 60–80% payload size reduction for high-frequency tracking batches.
///
/// **Delta field mapping:**
///
/// | Short | Full | Encoding |
/// |-------|------|----------|
/// | `u` | uuid | Full string (always unique) |
/// | `t` | Δtime | Seconds since previous location |
/// | `la` | Δlatitude | Integer: `(lat - prevLat) × 10^precision` |
/// | `lo` | Δlongitude | Integer: `(lng - prevLng) × 10^precision` |
/// | `s` | Δspeed | Float: `speed - prevSpeed` |
/// | `h` | Δheading | Float: `heading - prevHeading` (shortest arc) |
/// | `a` | Δaccuracy | Float: `accuracy - prevAccuracy` |
/// | `al` | Δaltitude | Float: `altitude - prevAltitude` |
/// | `b` | Δbattery | Float: `level - prevLevel` |
class DeltaEncoder {
  DeltaEncoder._();

  /// Encode a batch of location maps into delta-compressed format.
  ///
  /// The first location is emitted as a full reference (`ref: true`).
  /// Subsequent locations are encoded as deltas relative to the previous.
  ///
  /// [locations] must be non-empty and ordered (typically by timestamp).
  /// [precision] controls coordinate decimal places (5 = ~1.1m, 6 = ~0.11m).
  ///
  /// Returns a list of maps ready for JSON serialization.
  static List<Map<String, Object?>> encode(
    List<Map<String, Object?>> locations, {
    int precision = 6,
  }) {
    if (locations.isEmpty) return const [];
    if (locations.length == 1) {
      return [
        <String, Object?>{'ref': true, ...locations.first},
      ];
    }

    final factor = math.pow(10, precision).toInt();
    final result = <Map<String, Object?>>[];

    // First location: full reference.
    result.add(<String, Object?>{'ref': true, ...locations.first});

    var prev = locations.first;
    var prevTs = _parseTimestamp(prev['timestamp']);

    for (var i = 1; i < locations.length; i++) {
      final curr = locations[i];
      final currTs = _parseTimestamp(curr['timestamp']);
      final delta = _encodeDelta(prev, curr, factor, prevTs, currTs);
      result.add(<String, Object?>{'d': delta});
      prev = curr;
      prevTs = currTs;
    }

    return result;
  }

  /// Decode a delta-compressed batch back into full location maps.
  ///
  /// The inverse of [encode]. Returns a list of full location maps.
  static List<Map<String, Object?>> decode(
    List<Map<String, Object?>> batch, {
    int precision = 6,
  }) {
    if (batch.isEmpty) return const [];

    final factor = math.pow(10, precision).toInt();
    final result = <Map<String, Object?>>[];

    // First item is the reference.
    final ref = Map<String, Object?>.from(batch.first);
    ref.remove('ref');
    result.add(ref);

    var prev = ref;
    var prevTs = _parseTimestamp(prev['timestamp']);

    for (var i = 1; i < batch.length; i++) {
      final item = batch[i];
      final delta = item['d'] as Map<String, Object?>?;
      if (delta == null) continue;

      final decodedTs = _reconstructTimestamp(prevTs, delta['t']);
      final decoded = _decodeDelta(prev, delta, factor, decodedTs);
      result.add(decoded);
      prev = decoded;
      prevTs = decodedTs;
    }

    return result;
  }

  static Map<String, Object?> _encodeDelta(
    Map<String, Object?> prev,
    Map<String, Object?> curr,
    int factor,
    DateTime? prevTs,
    DateTime? currTs,
  ) {
    final delta = <String, Object?>{};

    // UUID — always full.
    delta['u'] = curr['uuid'];

    // Δ timestamp (seconds).
    if (prevTs != null && currTs != null) {
      delta['t'] = currTs.difference(prevTs).inSeconds;
    }

    // Coordinates (integer-encoded deltas).
    final prevCoords = prev['coords'] as Map<String, Object?>?;
    final currCoords = curr['coords'] as Map<String, Object?>?;
    if (prevCoords != null && currCoords != null) {
      final prevLat = _toDouble(prevCoords['latitude']);
      final currLat = _toDouble(currCoords['latitude']);
      delta['la'] = ((currLat - prevLat) * factor).round();

      final prevLng = _toDouble(prevCoords['longitude']);
      final currLng = _toDouble(currCoords['longitude']);
      delta['lo'] = ((currLng - prevLng) * factor).round();

      // Speed delta.
      final prevSpeed = _toDouble(prevCoords['speed']);
      final currSpeed = _toDouble(currCoords['speed']);
      delta['s'] = _round(currSpeed - prevSpeed, 2);

      // Heading delta (shortest arc).
      final prevHeading = _toDouble(prevCoords['heading']);
      final currHeading = _toDouble(currCoords['heading']);
      delta['h'] = _round(_shortestArc(prevHeading, currHeading), 2);

      // Accuracy delta.
      final prevAcc = _toDouble(prevCoords['accuracy']);
      final currAcc = _toDouble(currCoords['accuracy']);
      delta['a'] = _round(currAcc - prevAcc, 2);

      // Altitude delta.
      final prevAlt = _toDouble(prevCoords['altitude']);
      final currAlt = _toDouble(currCoords['altitude']);
      delta['al'] = _round(currAlt - prevAlt, 2);
    }

    // Battery delta.
    final prevBattery = prev['battery'] as Map<String, Object?>?;
    final currBattery = curr['battery'] as Map<String, Object?>?;
    if (prevBattery != null && currBattery != null) {
      final prevLevel = _toDouble(prevBattery['level']);
      final currLevel = _toDouble(currBattery['level']);
      delta['b'] = _round(currLevel - prevLevel, 4);
    }

    return delta;
  }

  static Map<String, Object?> _decodeDelta(
    Map<String, Object?> prev,
    Map<String, Object?> delta,
    int factor,
    DateTime? decodedTs,
  ) {
    final decoded = <String, Object?>{};

    decoded['uuid'] = delta['u'];

    // Reconstruct timestamp.
    if (decodedTs != null) {
      decoded['timestamp'] = decodedTs.toIso8601String();
    }

    // Reconstruct coordinates.
    final prevCoords = prev['coords'] as Map<String, Object?>?;
    if (prevCoords != null) {
      final lat =
          _toDouble(prevCoords['latitude']) +
          (delta['la'] as num? ?? 0) / factor;
      final lng =
          _toDouble(prevCoords['longitude']) +
          (delta['lo'] as num? ?? 0) / factor;
      final speed = _toDouble(prevCoords['speed']) + _toDouble(delta['s']);
      var heading = _toDouble(prevCoords['heading']) + _toDouble(delta['h']);
      heading = ((heading % 360) + 360) % 360; // Normalize to 0–360.
      final accuracy =
          _toDouble(prevCoords['accuracy']) + _toDouble(delta['a']);
      final altitude =
          _toDouble(prevCoords['altitude']) + _toDouble(delta['al']);

      decoded['coords'] = <String, Object?>{
        'latitude': lat,
        'longitude': lng,
        'speed': speed,
        'heading': heading,
        'accuracy': accuracy,
        'altitude': altitude,
        // Preserve altitude_accuracy if present.
        if (prevCoords.containsKey('altitude_accuracy'))
          'altitude_accuracy': prevCoords['altitude_accuracy'],
      };
    }

    // Reconstruct battery.
    final prevBattery = prev['battery'] as Map<String, Object?>?;
    if (prevBattery != null) {
      final level = _toDouble(prevBattery['level']) + _toDouble(delta['b']);
      decoded['battery'] = <String, Object?>{
        'level': level,
        'is_charging': prevBattery['is_charging'],
      };
    }

    // Copy through fields not delta-encoded.
    for (final key in prev.keys) {
      if (!decoded.containsKey(key) &&
          key != 'coords' &&
          key != 'battery' &&
          key != 'uuid' &&
          key != 'timestamp') {
        decoded[key] = prev[key];
      }
    }

    return decoded;
  }

  static DateTime? _parseTimestamp(Object? value) {
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static double _toDouble(Object? value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return 0.0;
  }

  /// Precomputed rounding factors for common precisions.
  static const int _factor2 = 100;
  static const int _factor4 = 10000;

  /// Round to [places] decimal places.
  static double _round(double value, int places) {
    final f = places == 2
        ? _factor2
        : (places == 4 ? _factor4 : math.pow(10, places));
    return (value * f).roundToDouble() / f;
  }

  /// Reconstruct a DateTime from prevTs + delta seconds without re-parsing.
  static DateTime? _reconstructTimestamp(DateTime? prevTs, Object? dt) {
    if (prevTs == null || dt == null) return null;
    final seconds = dt is int ? dt : (dt as num).toInt();
    return prevTs.add(Duration(seconds: seconds));
  }

  /// Compute the shortest arc between two headings (0–360°).
  /// Returns a value in [-180, 180].
  static double _shortestArc(double from, double to) {
    var diff = to - from;
    while (diff > 180) {
      diff -= 360;
    }
    while (diff < -180) {
      diff += 360;
    }
    return diff;
  }
}
