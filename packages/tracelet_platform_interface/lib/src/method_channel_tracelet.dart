import 'package:flutter/services.dart';

import 'tracelet_platform.dart';

/// A [TraceletPlatform] implementation that uses MethodChannel and EventChannels.
///
/// This is the default implementation. Platform-specific packages (tracelet_android,
/// tracelet_ios) may override this with Pigeon-backed implementations.
class MethodChannelTracelet extends TraceletPlatform {
  /// The MethodChannel used for Dart → Native request/response calls.
  final MethodChannel _methodChannel =
      const MethodChannel(TraceletPlatform.methodChannelName);

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>> ready(Map<String, Object?> config) async {
    final result =
        await _methodChannel.invokeMapMethod<String, Object?>('ready', config);
    return result ?? {};
  }

  @override
  Future<Map<String, Object?>> start() async {
    final result =
        await _methodChannel.invokeMapMethod<String, Object?>('start');
    return result ?? {};
  }

  @override
  Future<Map<String, Object?>> stop() async {
    final result =
        await _methodChannel.invokeMapMethod<String, Object?>('stop');
    return result ?? {};
  }

  @override
  Future<Map<String, Object?>> startGeofences() async {
    final result =
        await _methodChannel.invokeMapMethod<String, Object?>('startGeofences');
    return result ?? {};
  }

  @override
  Future<Map<String, Object?>> getState() async {
    final result =
        await _methodChannel.invokeMapMethod<String, Object?>('getState');
    return result ?? {};
  }

  @override
  Future<Map<String, Object?>> setConfig(Map<String, Object?> config) async {
    final result = await _methodChannel.invokeMapMethod<String, Object?>(
        'setConfig', config);
    return result ?? {};
  }

  @override
  Future<Map<String, Object?>> reset([Map<String, Object?>? config]) async {
    final result = await _methodChannel.invokeMapMethod<String, Object?>(
        'reset', config);
    return result ?? {};
  }

  // ---------------------------------------------------------------------------
  // Location
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>> getCurrentPosition(
      Map<String, Object?> options) async {
    final result = await _methodChannel.invokeMapMethod<String, Object?>(
        'getCurrentPosition', options);
    return result ?? {};
  }

  @override
  Future<int> watchPosition(Map<String, Object?> options) async {
    final result =
        await _methodChannel.invokeMethod<int>('watchPosition', options);
    return result ?? -1;
  }

  @override
  Future<bool> stopWatchPosition(int watchId) async {
    final result =
        await _methodChannel.invokeMethod<bool>('stopWatchPosition', watchId);
    return result ?? false;
  }

  @override
  Future<bool> changePace(bool isMoving) async {
    final result =
        await _methodChannel.invokeMethod<bool>('changePace', isMoving);
    return result ?? false;
  }

  @override
  Future<double> getOdometer() async {
    final result = await _methodChannel.invokeMethod<double>('getOdometer');
    return result ?? 0.0;
  }

  @override
  Future<Map<String, Object?>> setOdometer(double value) async {
    final result = await _methodChannel.invokeMapMethod<String, Object?>(
        'setOdometer', value);
    return result ?? {};
  }

  // ---------------------------------------------------------------------------
  // Geofencing
  // ---------------------------------------------------------------------------

  @override
  Future<bool> addGeofence(Map<String, Object?> geofence) async {
    final result =
        await _methodChannel.invokeMethod<bool>('addGeofence', geofence);
    return result ?? false;
  }

  @override
  Future<bool> addGeofences(List<Map<String, Object?>> geofences) async {
    final result =
        await _methodChannel.invokeMethod<bool>('addGeofences', geofences);
    return result ?? false;
  }

  @override
  Future<bool> removeGeofence(String identifier) async {
    final result =
        await _methodChannel.invokeMethod<bool>('removeGeofence', identifier);
    return result ?? false;
  }

  @override
  Future<bool> removeGeofences() async {
    final result =
        await _methodChannel.invokeMethod<bool>('removeGeofences');
    return result ?? false;
  }

  @override
  Future<List<Map<String, Object?>>> getGeofences() async {
    final result = await _methodChannel.invokeListMethod<Map>('getGeofences');
    return result
            ?.map((e) => Map<String, Object?>.from(e))
            .toList(growable: false) ??
        [];
  }

  @override
  Future<Map<String, Object?>?> getGeofence(String identifier) async {
    final result = await _methodChannel.invokeMapMethod<String, Object?>(
        'getGeofence', identifier);
    return result;
  }

  @override
  Future<bool> geofenceExists(String identifier) async {
    final result = await _methodChannel.invokeMethod<bool>(
        'geofenceExists', identifier);
    return result ?? false;
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  @override
  Future<List<Map<String, Object?>>> getLocations(
      [Map<String, Object?>? query]) async {
    final result =
        await _methodChannel.invokeListMethod<Map>('getLocations', query);
    return result
            ?.map((e) => Map<String, Object?>.from(e))
            .toList(growable: false) ??
        [];
  }

  @override
  Future<int> getCount() async {
    final result = await _methodChannel.invokeMethod<int>('getCount');
    return result ?? 0;
  }

  @override
  Future<bool> destroyLocations() async {
    final result =
        await _methodChannel.invokeMethod<bool>('destroyLocations');
    return result ?? false;
  }

  @override
  Future<bool> destroyLocation(String uuid) async {
    final result =
        await _methodChannel.invokeMethod<bool>('destroyLocation', uuid);
    return result ?? false;
  }

  @override
  Future<String> insertLocation(Map<String, Object?> params) async {
    final result =
        await _methodChannel.invokeMethod<String>('insertLocation', params);
    return result ?? '';
  }

  // ---------------------------------------------------------------------------
  // HTTP Sync
  // ---------------------------------------------------------------------------

  @override
  Future<List<Map<String, Object?>>> sync() async {
    final result = await _methodChannel.invokeListMethod<Map>('sync');
    return result
            ?.map((e) => Map<String, Object?>.from(e))
            .toList(growable: false) ??
        [];
  }

  // ---------------------------------------------------------------------------
  // Utility
  // ---------------------------------------------------------------------------

  @override
  Future<bool> isPowerSaveMode() async {
    final result =
        await _methodChannel.invokeMethod<bool>('isPowerSaveMode');
    return result ?? false;
  }

  @override
  Future<int> requestPermission() async {
    final result =
        await _methodChannel.invokeMethod<int>('requestPermission');
    return result ?? 0;
  }

  @override
  Future<int> requestTemporaryFullAccuracy(String purpose) async {
    final result = await _methodChannel.invokeMethod<int>(
        'requestTemporaryFullAccuracy', purpose);
    return result ?? 0;
  }

  @override
  Future<Map<String, Object?>> getProviderState() async {
    final result =
        await _methodChannel.invokeMapMethod<String, Object?>('getProviderState');
    return result ?? {};
  }

  @override
  Future<Map<String, Object?>> getSensors() async {
    final result =
        await _methodChannel.invokeMapMethod<String, Object?>('getSensors');
    return result ?? {};
  }

  @override
  Future<Map<String, Object?>> getDeviceInfo() async {
    final result =
        await _methodChannel.invokeMapMethod<String, Object?>('getDeviceInfo');
    return result ?? {};
  }

  @override
  Future<bool> playSound(String name) async {
    final result =
        await _methodChannel.invokeMethod<bool>('playSound', name);
    return result ?? false;
  }

  @override
  Future<bool> isIgnoringBatteryOptimizations() async {
    final result = await _methodChannel
        .invokeMethod<bool>('isIgnoringBatteryOptimizations');
    return result ?? false;
  }

  @override
  Future<bool> requestSettings(String action) async {
    final result =
        await _methodChannel.invokeMethod<bool>('requestSettings', action);
    return result ?? false;
  }

  @override
  Future<bool> showSettings(String action) async {
    final result =
        await _methodChannel.invokeMethod<bool>('showSettings', action);
    return result ?? false;
  }

  // ---------------------------------------------------------------------------
  // Background Tasks
  // ---------------------------------------------------------------------------

  @override
  Future<int> startBackgroundTask() async {
    final result =
        await _methodChannel.invokeMethod<int>('startBackgroundTask');
    return result ?? 0;
  }

  @override
  Future<int> stopBackgroundTask(int taskId) async {
    final result =
        await _methodChannel.invokeMethod<int>('stopBackgroundTask', taskId);
    return result ?? taskId;
  }

  // ---------------------------------------------------------------------------
  // Logging
  // ---------------------------------------------------------------------------

  @override
  Future<String> getLog([Map<String, Object?>? query]) async {
    final result =
        await _methodChannel.invokeMethod<String>('getLog', query);
    return result ?? '';
  }

  @override
  Future<bool> destroyLog() async {
    final result = await _methodChannel.invokeMethod<bool>('destroyLog');
    return result ?? false;
  }

  @override
  Future<bool> emailLog(String email) async {
    final result =
        await _methodChannel.invokeMethod<bool>('emailLog', email);
    return result ?? false;
  }

  @override
  Future<bool> log(String level, String message) async {
    final result =
        await _methodChannel.invokeMethod<bool>('log', [level, message]);
    return result ?? false;
  }

  // ---------------------------------------------------------------------------
  // Scheduling
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>> startSchedule() async {
    final result =
        await _methodChannel.invokeMapMethod<String, Object?>('startSchedule');
    return result ?? {};
  }

  @override
  Future<Map<String, Object?>> stopSchedule() async {
    final result =
        await _methodChannel.invokeMapMethod<String, Object?>('stopSchedule');
    return result ?? {};
  }

  // ---------------------------------------------------------------------------
  // Headless
  // ---------------------------------------------------------------------------

  @override
  Future<bool> registerHeadlessTask(List<int> callbackIds) async {
    final result = await _methodChannel.invokeMethod<bool>(
        'registerHeadlessTask', callbackIds);
    return result ?? false;
  }
}
