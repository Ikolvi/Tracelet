import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'package:tracelet_web/src/web_utils.dart';

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

  /// Max records to persist (from config). `<= 0` means unlimited.
  int _maxRecords = 10000;

  /// Max age in days for persisted locations (from config). `<= 0` means
  /// unlimited (#361).
  int _maxDays = -1;
  int _maxLogDays = 7;

  /// Applies the given configuration to the storage engine.
  void applyConfig(Map<String, Object?> config) {
    final persistence = config['persistence'];
    if (persistence is Map) {
      final pm = Map<String, Object?>.from(persistence);
      _maxRecords = (pm['maxRecordsToPersist'] as int?) ?? _maxRecords;
      _maxDays = (pm['maxDaysToPersist'] as int?) ?? _maxDays;
    }
    final logger = config['logger'];
    if (logger is Map) {
      final lm = Map<String, Object?>.from(logger);
      _maxLogDays = (lm['logMaxDays'] as int?) ?? _maxLogDays;
    }
    final audit = config['audit'];
    if (audit is Map) {
      _auditEnabled = (audit['enabled'] as bool?) ?? _auditEnabled;
    }
  }

  // Audit properties
  bool _auditEnabled = false;
  String _lastHash = '';

  // ---------------------------------------------------------------------------
  // Location persistence
  // ---------------------------------------------------------------------------

  /// Retrieves persisted locations, optionally filtered and sorted.
  Future<List<Map<String, Object?>>> getLocations([
    Map<String, Object?>? query,
  ]) async {
    if (query == null || query.isEmpty) {
      return List<Map<String, Object?>>.from(_locations);
    }

    // Use lazy Iterable chaining to avoid intermediate list copies (D-M3).
    Iterable<Map<String, Object?>> results = _locations;

    // Filter by time range (start/end are millisecondsSinceEpoch ints).
    final startMs = query['start'] as int?;
    final endMs = query['end'] as int?;
    if (startMs != null) {
      final startDt = DateTime.fromMillisecondsSinceEpoch(startMs);
      results = results.where((loc) {
        final ts = _parseTimestamp(loc['timestamp']);
        return ts != null && !ts.isBefore(startDt);
      });
    }
    if (endMs != null) {
      final endDt = DateTime.fromMillisecondsSinceEpoch(endMs);
      results = results.where((loc) {
        final ts = _parseTimestamp(loc['timestamp']);
        return ts != null && !ts.isAfter(endDt);
      });
    }

    // Materialize once for sort/limit operations.
    var materialized = results.toList();

    // Order.
    final order = query['order'] as int?;
    if (order == 1) {
      // desc — newest first
      materialized.sort((a, b) {
        final aTs = a['timestamp'] as String? ?? '';
        final bTs = b['timestamp'] as String? ?? '';
        return bTs.compareTo(aTs);
      });
    }

    // Limit.
    final limit = query['limit'] as int?;
    if (limit != null && limit > 0 && materialized.length > limit) {
      materialized = materialized.sublist(0, limit);
    }

    return materialized;
  }

  /// Returns the total number of persisted locations, optionally filtered.
  Future<int> getCount([Map<String, Object?>? query]) async {
    if (query == null || query.isEmpty) {
      return _locations.length;
    }
    final startMs = query['start'] as int?;
    final endMs = query['end'] as int?;
    if (startMs == null && endMs == null) {
      return _locations.length;
    }
    final startDt = startMs != null
        ? DateTime.fromMillisecondsSinceEpoch(startMs)
        : null;
    final endDt = endMs != null
        ? DateTime.fromMillisecondsSinceEpoch(endMs)
        : null;
    return _locations.where((loc) {
      final ts = _parseTimestamp(loc['timestamp']);
      if (ts == null) return false;
      if (startDt != null && ts.isBefore(startDt)) return false;
      if (endDt != null && ts.isAfter(endDt)) return false;
      return true;
    }).length;
  }

  /// Parses a timestamp value that may be an ISO 8601 string or millis int.
  static DateTime? _parseTimestamp(Object? value) {
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  /// Deletes all persisted locations.
  Future<bool> destroyLocations() async {
    _locations.clear();
    _lastHash = '';
    return true;
  }

  /// Deletes all persisted locations that have already been synced.
  Future<int> destroySyncedLocations() async {
    final before = _locations.length;
    _locations.removeWhere(
      (loc) => loc['synced'] == true || loc['synced'] == 1,
    );
    return before - _locations.length;
  }

  /// Deletes a specific location by its UUID.
  Future<bool> destroyLocation(String uuid) async {
    final before = _locations.length;
    _locations.removeWhere((loc) => loc['uuid'] == uuid);
    return _locations.length < before;
  }

  /// Inserts a new location into the store and returns its UUID.
  Future<String> insertLocation(Map<String, Object?> params) async {
    final uuid = params['uuid'] as String? ?? generateUuid();
    final record = Map<String, Object?>.from(params);
    record['uuid'] = uuid;
    if (!record.containsKey('timestamp')) {
      record['timestamp'] = DateTime.now().toIso8601String();
    }

    if (_auditEnabled) {
      final dataStr = jsonEncode(record);
      final raw = '$_lastHash$dataStr';
      final newHash = sha256.convert(utf8.encode(raw)).toString();
      record['_audit_hash'] = newHash;
      record['_audit_prev_hash'] = _lastHash;
      _lastHash = newHash;
    }

    _locations.add(record);
    _enforceRetentionCaps();

    return uuid;
  }

  /// Applies `maxRecordsToPersist` and `maxDaysToPersist` to the store (#361,
  /// #362).
  ///
  /// The record cap was previously `while (length > _maxRecords) removeAt(0)`,
  /// which read the documented `-1` "unlimited" sentinel as a cap of minus one:
  /// it emptied the store and then threw `RangeError` off the end of it. Because
  /// `ready()` resolves every field before it crosses the channel, `-1` is what
  /// the default config actually sends — so the cap crashed the first insert of
  /// every web session rather than merely being ignored. Non-positive now means
  /// unlimited on both caps, matching the native side and the public docs.
  ///
  /// Age pruning is new here: `maxDaysToPersist` was read by nothing on web.
  /// Records with an unparseable or absent `timestamp` are kept, not guessed at;
  /// the record cap bounds those.
  void _enforceRetentionCaps() {
    if (_maxDays > 0) {
      final cutoff = DateTime.now().toUtc().subtract(Duration(days: _maxDays));
      _locations.removeWhere((loc) {
        final raw = loc['timestamp'];
        if (raw is! String) return false;
        final ts = DateTime.tryParse(raw);
        return ts != null && ts.toUtc().isBefore(cutoff);
      });
    }
    if (_maxRecords > 0) {
      while (_locations.length > _maxRecords) {
        _locations.removeAt(0);
      }
    }
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

  /// Appends a new log message.
  Future<bool> log(String level, String message) async {
    final ts = DateTime.now().toIso8601String();
    _logs.add('[$ts] [$level] $message');

    // Trim old entries.
    if (_logs.length > 50000) {
      _logs.removeRange(0, _logs.length - 50000);
    }

    return true;
  }

  /// Retrieves the full log string, optionally filtered.
  Future<String> getLog([Map<String, Object?>? query]) async {
    return _logs.join('\n');
  }

  /// Deletes all logs.
  Future<bool> destroyLog() async {
    _logs.clear();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Audit Trail
  // ---------------------------------------------------------------------------

  /// Verifies the cryptographic integrity of the audit trail.
  Future<Map<String, Object?>> verifyAuditTrail() async {
    if (!_auditEnabled) {
      return <String, Object?>{
        'is_valid': false,
        'total_records': _locations.length,
        'verified_records': 0,
      };
    }

    var currentHash = '';
    var verifiedCount = 0;
    for (final loc in _locations) {
      final prevHash = loc['_audit_prev_hash'] as String? ?? '';
      final storedHash = loc['_audit_hash'] as String? ?? '';

      if (prevHash != currentHash) {
        return <String, Object?>{
          'is_valid': false,
          'total_records': _locations.length,
          'verified_records': verifiedCount,
        };
      }

      // Re-compute hash (temporarily removing audit fields)
      final temp = Map<String, Object?>.from(loc);
      temp.remove('_audit_hash');
      temp.remove('_audit_prev_hash');

      final dataStr = jsonEncode(temp);
      final raw = '$currentHash$dataStr';
      final computed = sha256.convert(utf8.encode(raw)).toString();

      if (computed != storedHash) {
        return <String, Object?>{
          'is_valid': false,
          'total_records': _locations.length,
          'verified_records': verifiedCount,
        };
      }

      currentHash = computed;
      verifiedCount++;
    }

    return <String, Object?>{
      'is_valid': true,
      'total_records': _locations.length,
      'verified_records': verifiedCount,
    };
  }

  /// Retrieves the audit proof for a specific location.
  Future<Map<String, Object?>?> getAuditProof(String uuid) async {
    try {
      final loc = _locations.firstWhere((element) => element['uuid'] == uuid);
      final hash = loc['_audit_hash'] as String?;
      final prev = loc['_audit_prev_hash'] as String?;
      if (hash != null) {
        return {'hash': hash, 'previous_hash': prev ?? ''};
      }
    } catch (_) {}
    return null;
  }
}
