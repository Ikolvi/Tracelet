import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:tracelet_platform_interface/tracelet_platform_interface.dart'
    show DeltaEncoder;
import 'package:web/web.dart' as web;

import 'web_event_dispatcher.dart';
import 'web_storage_engine.dart';

/// HTTP sync engine for Tracelet web using the `fetch()` API.
///
/// Uploads persisted locations to the configured server endpoint.
class WebHttpEngine {
  WebHttpEngine(this._events, this._storage);

  final WebEventDispatcher _events;
  final WebStorageEngine _storage;

  /// HTTP config values.
  String _url = '';
  String _method = 'POST';
  Map<String, String> _headers = <String, String>{};
  String _httpRootProperty = 'location';
  bool _batchSync = false;
  int _maxBatchSize = 250;
  int _httpTimeout = 60000;
  bool _autoSync = true;
  int _autoSyncThreshold = 0;
  bool _disableAutoSyncOnCellular = false;
  bool _enableDeltaCompression = false;
  int _deltaCoordinatePrecision = 6;

  void applyConfig(Map<String, Object?> config) {
    final http = config['http'];
    if (http is Map) {
      final hm = Map<String, Object?>.from(http);
      _url = (hm['url'] as String?) ?? _url;
      final m = hm['method'] as int?;
      if (m == 1) {
        _method = 'PUT';
      } else {
        _method = 'POST';
      }
      final hdrs = hm['headers'];
      if (hdrs is Map) {
        _headers = hdrs.map<String, String>(
          (Object? k, Object? v) => MapEntry(k.toString(), v.toString()),
        );
      }
      _httpRootProperty =
          (hm['httpRootProperty'] as String?) ?? _httpRootProperty;
      _batchSync = (hm['batchSync'] as bool?) ?? _batchSync;
      _maxBatchSize = (hm['maxBatchSize'] as int?) ?? _maxBatchSize;
      _httpTimeout = (hm['httpTimeout'] as int?) ?? _httpTimeout;
      _autoSync = (hm['autoSync'] as bool?) ?? _autoSync;
      _autoSyncThreshold =
          (hm['autoSyncThreshold'] as int?) ?? _autoSyncThreshold;
      _disableAutoSyncOnCellular =
          (hm['disableAutoSyncOnCellular'] as bool?) ??
          _disableAutoSyncOnCellular;
      _enableDeltaCompression =
          (hm['enableDeltaCompression'] as bool?) ?? _enableDeltaCompression;
      _deltaCoordinatePrecision =
          (hm['deltaCoordinatePrecision'] as int?) ?? _deltaCoordinatePrecision;
    }
  }

  /// Trigger auto-sync if conditions are met. Called after each location
  /// insert to mirror the native platform behaviour.
  void onLocationInserted() {
    if (!_autoSync) return;
    if (_url.isEmpty) return;
    // Note: `_disableAutoSyncOnCellular` cannot be reliably enforced on
    // web because the Network Information API has limited adoption.
    // We skip that guard here.
    if (_autoSyncThreshold > 0) {
      // Approximate un-synced count via storage.
      _storage.getCount().then((count) {
        if (count >= _autoSyncThreshold) {
          sync();
        }
      });
      return;
    }
    sync();
  }

  // ---------------------------------------------------------------------------
  // Sync
  // ---------------------------------------------------------------------------

  Future<List<Map<String, Object?>>> sync() async {
    if (_url.isEmpty) {
      _events.log('warning', '[HTTP] No URL configured for sync');
      return <Map<String, Object?>>[];
    }

    final locations = _storage.drainLocations();
    if (locations.isEmpty) {
      _events.log('info', '[HTTP] No locations to sync');
      return <Map<String, Object?>>[];
    }

    final synced = <Map<String, Object?>>[];

    if (_batchSync) {
      // Send in batches.
      for (var i = 0; i < locations.length; i += _maxBatchSize) {
        final batch = locations.sublist(
          i,
          i + _maxBatchSize > locations.length
              ? locations.length
              : i + _maxBatchSize,
        );
        final success = await _sendBatch(batch);
        if (success) {
          synced.addAll(batch);
        } else {
          // Re-insert failed locations back into storage.
          for (final loc in batch) {
            await _storage.insertLocation(loc);
          }
        }
      }
    } else {
      // Send one at a time.
      for (final loc in locations) {
        final success = await _sendSingle(loc);
        if (success) {
          synced.add(loc);
        } else {
          await _storage.insertLocation(loc);
        }
      }
    }

    return synced;
  }

  Future<bool> _sendSingle(Map<String, Object?> location) async {
    try {
      final body = <String, Object?>{_httpRootProperty: location};
      final response = await _doFetch(jsonEncode(body));

      final status = response.status;
      final success = status >= 200 && status < 300;
      final responseText = (await response.text().toDart);

      _events.emitHttp(<String, Object?>{
        'success': success,
        'status': status,
        'responseText': responseText,
      });

      // Handle authorization errors.
      if (status == 401 || status == 403) {
        _events.emitAuthorization(<String, Object?>{
          'success': false,
          'status': status,
          'response': responseText,
        });
      }

      return success;
    } catch (e) {
      _events.emitHttp(<String, Object?>{
        'success': false,
        'status': 0,
        'responseText': e.toString(),
      });
      _events.log('error', '[HTTP] Sync failed: $e');
      return false;
    }
  }

  Future<bool> _sendBatch(List<Map<String, Object?>> locations) async {
    try {
      final payload = (_enableDeltaCompression && locations.length > 1)
          ? DeltaEncoder.encode(locations, precision: _deltaCoordinatePrecision)
          : locations;
      final body = <String, Object?>{_httpRootProperty: payload};
      final response = await _doFetch(jsonEncode(body));

      final status = response.status;
      final success = status >= 200 && status < 300;
      final responseText = (await response.text().toDart);

      _events.emitHttp(<String, Object?>{
        'success': success,
        'status': status,
        'responseText': responseText,
      });

      if (status == 401 || status == 403) {
        _events.emitAuthorization(<String, Object?>{
          'success': false,
          'status': status,
          'response': responseText,
        });
      }

      return success;
    } catch (e) {
      _events.emitHttp(<String, Object?>{
        'success': false,
        'status': 0,
        'responseText': e.toString(),
      });
      _events.log('error', '[HTTP] Batch sync failed: $e');
      return false;
    }
  }

  Future<web.Response> _doFetch(String body) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      ..._headers,
    };

    final webHeaders = web.Headers();
    for (final entry in headers.entries) {
      webHeaders.append(entry.key, entry.value);
    }

    final init = web.RequestInit(
      method: _method,
      headers: webHeaders,
      body: body.toJS,
    );

    final responseFuture = web.window.fetch(_url.toJS, init).toDart;

    // Timeout.
    return Future.any([
      responseFuture,
      Future<web.Response>.delayed(
        Duration(milliseconds: _httpTimeout),
        () => throw TimeoutException(
          'HTTP request timed out',
          Duration(milliseconds: _httpTimeout),
        ),
      ),
    ]);
  }
}
