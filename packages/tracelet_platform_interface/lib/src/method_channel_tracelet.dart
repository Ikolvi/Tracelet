import 'package:flutter/services.dart';
import 'package:tracelet_platform_interface/src/generated/tracelet_api.g.dart';

import 'package:tracelet_platform_interface/src/tracelet_platform.dart';

/// A [TraceletPlatform] implementation that uses MethodChannel and EventChannels.
///
/// This is the default implementation. Platform-specific packages (tracelet_android,
/// tracelet_ios) may override this with Pigeon-backed implementations.
class MethodChannelTracelet extends TraceletPlatform {
  /// The MethodChannel used for Dart → Native request/response calls.
  final MethodChannel _methodChannel = const MethodChannel(
    TraceletPlatform.methodChannelName,
  );

  /// Safely invoke a method that returns a map.
  ///
  /// Platform channels on iOS return `Map<Object?, Object?>` at runtime,
  /// so we cannot rely on `invokeMapMethod<String, Object?>` which does
  /// a direct cast. Instead, use `invokeMethod` and `Map.from()`.
  Future<Map<String, Object?>> _invokeMap(
    String method, [
    Object? arguments,
  ]) async {
    final result = await _methodChannel.invokeMethod<Object?>(
      method,
      arguments,
    );
    if (result is Map) {
      return Map<String, Object?>.from(result);
    }
    return <String, Object?>{};
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>> ready(TlConfig config) async {
    return _invokeMap('ready', _tlConfigToMap(config));
  }

  @override
  Future<Map<String, Object?>> start() async {
    return _invokeMap('start');
  }

  @override
  Future<Map<String, Object?>> stop() async {
    return _invokeMap('stop');
  }

  @override
  Future<Map<String, Object?>> startGeofences() async {
    return _invokeMap('startGeofences');
  }

  @override
  Future<Map<String, Object?>> startPeriodic() async {
    return _invokeMap('startPeriodic');
  }

  @override
  Future<Map<String, Object?>> getState() async {
    return _invokeMap('getState');
  }

  @override
  Future<Map<String, Object?>> setConfig(TlConfig config) async {
    return _invokeMap('setConfig', _tlConfigToMap(config));
  }

  @override
  Future<Map<String, Object?>> reset([TlConfig? config]) async {
    return _invokeMap('reset', config != null ? _tlConfigToMap(config) : null);
  }

  @override
  Future<void> updateNotification() async {
    await _methodChannel.invokeMethod<void>('updateNotification');
  }

  // ---------------------------------------------------------------------------
  // Location
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>> getCurrentPosition(
    TlCurrentPositionOptions options,
  ) async {
    return _invokeMap('getCurrentPosition', _optionsToMap(options));
  }

  @override
  Future<bool> cancelCurrentPosition(String requestId) async {
    final result = await _methodChannel.invokeMethod<bool>(
      'cancelCurrentPosition',
      requestId,
    );
    return result ?? false;
  }

  @override
  Future<Map<String, Object?>> getLastKnownLocation([
    TlCurrentPositionOptions? options,
  ]) async {
    return _invokeMap(
      'getLastKnownLocation',
      options != null ? _optionsToMap(options) : null,
    );
  }

  @override
  Future<int> watchPosition(TlCurrentPositionOptions options) async {
    final result = await _methodChannel.invokeMethod<int>(
      'watchPosition',
      _optionsToMap(options),
    );
    return result ?? -1;
  }

  @override
  Future<bool> stopWatchPosition(int watchId) async {
    final result = await _methodChannel.invokeMethod<bool>(
      'stopWatchPosition',
      watchId,
    );
    return result ?? false;
  }

  @override
  Future<bool> changePace(bool isMoving) async {
    final result = await _methodChannel.invokeMethod<bool>(
      'changePace',
      isMoving,
    );
    return result ?? false;
  }

  @override
  Future<double> getOdometer() async {
    final result = await _methodChannel.invokeMethod<double>('getOdometer');
    return result ?? 0.0;
  }

  @override
  Future<Map<String, Object?>> setOdometer(double value) async {
    return _invokeMap('setOdometer', value);
  }

  // ---------------------------------------------------------------------------
  // Geofencing
  // ---------------------------------------------------------------------------

  @override
  Future<bool> addGeofence(TlGeofence geofence) async {
    final result = await _methodChannel.invokeMethod<bool>(
      'addGeofence',
      _tlGeofenceToMap(geofence),
    );
    return result ?? false;
  }

  @override
  Future<bool> addGeofences(List<TlGeofence> geofences) async {
    final result = await _methodChannel.invokeMethod<bool>(
      'addGeofences',
      geofences.map(_tlGeofenceToMap).toList(),
    );
    return result ?? false;
  }

  // Serialize typed Pigeon inputs to the channel map shape. (Legacy
  // MethodChannel transport; the active path is PigeonTracelet, which passes
  // the typed objects straight through — see #206.)
  Map<String, Object?> _optionsToMap(
    TlCurrentPositionOptions o,
  ) => <String, Object?>{
    if (o.desiredAccuracy != null) 'desiredAccuracy': o.desiredAccuracy!.index,
    'timeout': o.timeout,
    'maximumAge': o.maximumAge,
    'persist': o.persist,
    'samples': o.samples,
    if (o.accuracyTarget != null) 'accuracyTarget': o.accuracyTarget,
    if (o.requestId != null) 'requestId': o.requestId,
    if (o.extras != null) 'extras': o.extras,
  };

  Map<String, Object?> _tlGeofenceToMap(TlGeofence g) => <String, Object?>{
    'identifier': g.identifier,
    'latitude': g.latitude,
    'longitude': g.longitude,
    'radius': g.radius,
    'notifyOnEntry': g.notifyOnEntry,
    'notifyOnExit': g.notifyOnExit,
    'notifyOnDwell': g.notifyOnDwell,
    'loiteringDelay': g.loiteringDelay,
    if (g.extras != null) 'extras': g.extras,
    if (g.vertices != null) 'vertices': g.vertices,
  };

  @override
  Future<bool> removeGeofence(String identifier) async {
    final result = await _methodChannel.invokeMethod<bool>(
      'removeGeofence',
      identifier,
    );
    return result ?? false;
  }

  @override
  Future<bool> removeGeofences() async {
    final result = await _methodChannel.invokeMethod<bool>('removeGeofences');
    return result ?? false;
  }

  @override
  Future<List<Map<String, Object?>>> getGeofences() async {
    final result = await _methodChannel.invokeListMethod<Map>('getGeofences');
    return result?.map(Map<String, Object?>.from).toList(growable: false) ?? [];
  }

  @override
  Future<Map<String, Object?>?> getGeofence(String identifier) async {
    final result = await _methodChannel.invokeMethod<Object?>(
      'getGeofence',
      identifier,
    );
    if (result is Map) return Map<String, Object?>.from(result);
    return null;
  }

  @override
  Future<bool> geofenceExists(String identifier) async {
    final result = await _methodChannel.invokeMethod<bool>(
      'geofenceExists',
      identifier,
    );
    return result ?? false;
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  @override
  Future<List<Map<String, Object?>>> getLocations([
    Map<String, Object?>? query,
  ]) async {
    final result = await _methodChannel.invokeListMethod<Map>(
      'getLocations',
      query,
    );
    return result?.map(Map<String, Object?>.from).toList(growable: false) ?? [];
  }

  @override
  Future<int> getCount([Map<String, Object?>? query]) async {
    final result = await _methodChannel.invokeMethod<int>('getCount', query);
    return result ?? 0;
  }

  @override
  Future<bool> destroyLocations() async {
    final result = await _methodChannel.invokeMethod<bool>('destroyLocations');
    return result ?? false;
  }

  @override
  Future<int> destroySyncedLocations() async {
    final result = await _methodChannel.invokeMethod<int>(
      'destroySyncedLocations',
    );
    return result ?? 0;
  }

  @override
  Future<bool> destroyLocation(String uuid) async {
    final result = await _methodChannel.invokeMethod<bool>(
      'destroyLocation',
      uuid,
    );
    return result ?? false;
  }

  @override
  Future<String> insertLocation(Map<String, Object?> params) async {
    final result = await _methodChannel.invokeMethod<String>(
      'insertLocation',
      params,
    );
    return result ?? '';
  }

  // ---------------------------------------------------------------------------
  // HTTP Sync
  // ---------------------------------------------------------------------------

  @override
  Future<List<Map<String, Object?>>> sync() async {
    final result = await _methodChannel.invokeListMethod<Map>('sync');
    return result?.map(Map<String, Object?>.from).toList(growable: false) ?? [];
  }

  @override
  Future<bool> setDynamicHeaders(Map<String, String> headers) async {
    final result = await _methodChannel.invokeMethod<bool>(
      'setDynamicHeaders',
      headers,
    );
    return result ?? false;
  }

  @override
  Future<bool> setRouteContext(Map<String, Object?> context) async {
    final result = await _methodChannel.invokeMethod<bool>(
      'setRouteContext',
      context,
    );
    return result ?? false;
  }

  @override
  Future<bool> clearRouteContext() async {
    final result = await _methodChannel.invokeMethod<bool>('clearRouteContext');
    return result ?? false;
  }

  @override
  Future<bool> registerHeadlessHeadersCallback(List<int> callbackIds) async {
    final result = await _methodChannel.invokeMethod<bool>(
      'registerHeadlessHeadersCallback',
      callbackIds,
    );
    return result ?? false;
  }

  @override
  Future<bool> registerHeadlessSyncBodyBuilder(List<int> callbackIds) async {
    final result = await _methodChannel.invokeMethod<bool>(
      'registerHeadlessSyncBodyBuilder',
      callbackIds,
    );
    return result ?? false;
  }

  // ---------------------------------------------------------------------------
  // Utility
  // ---------------------------------------------------------------------------

  @override
  Future<bool> isPowerSaveMode() async {
    final result = await _methodChannel.invokeMethod<bool>('isPowerSaveMode');
    return result ?? false;
  }

  @override
  Future<bool> canScheduleExactAlarms() async {
    final result = await _methodChannel.invokeMethod<bool>(
      'canScheduleExactAlarms',
    );
    return result ?? true; // Default: no restriction (pre-12 / iOS / web)
  }

  @override
  Future<bool> openExactAlarmSettings() async {
    final result = await _methodChannel.invokeMethod<bool>(
      'openExactAlarmSettings',
    );
    return result ?? false;
  }

  @override
  Future<int> requestTemporaryFullAccuracy(String purpose) async {
    final result = await _methodChannel.invokeMethod<int>(
      'requestTemporaryFullAccuracy',
      purpose,
    );
    return result ?? 0;
  }

  @override
  Future<Map<String, Object?>> getProviderState() async {
    return _invokeMap('getProviderState');
  }

  @override
  Future<Map<String, Object?>> getSensors() async {
    return _invokeMap('getSensors');
  }

  @override
  Future<Map<String, Object?>> getDeviceInfo() async {
    return _invokeMap('getDeviceInfo');
  }

  @override
  Future<bool> playSound(String name) async {
    final result = await _methodChannel.invokeMethod<bool>('playSound', name);
    return result ?? false;
  }

  @override
  Future<bool> isIgnoringBatteryOptimizations() async {
    final result = await _methodChannel.invokeMethod<bool>(
      'isIgnoringBatteryOptimizations',
    );
    return result ?? false;
  }

  @override
  Future<bool> requestSettings(String action) async {
    final result = await _methodChannel.invokeMethod<bool>(
      'requestSettings',
      action,
    );
    return result ?? false;
  }

  @override
  Future<bool> showSettings(String action) async {
    final result = await _methodChannel.invokeMethod<bool>(
      'showSettings',
      action,
    );
    return result ?? false;
  }

  // ---------------------------------------------------------------------------
  // OEM Compatibility
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>> getSettingsHealth() async {
    return _invokeMap('getSettingsHealth');
  }

  @override
  Future<bool> openOemSettings(String label) async {
    final result = await _methodChannel.invokeMethod<bool>(
      'openOemSettings',
      label,
    );
    return result ?? false;
  }

  // ---------------------------------------------------------------------------
  // Background Tasks
  // ---------------------------------------------------------------------------

  @override
  Future<int> startBackgroundTask() async {
    final result = await _methodChannel.invokeMethod<int>(
      'startBackgroundTask',
    );
    return result ?? 0;
  }

  @override
  Future<int> stopBackgroundTask(int taskId) async {
    final result = await _methodChannel.invokeMethod<int>(
      'stopBackgroundTask',
      taskId,
    );
    return result ?? taskId;
  }

  // ---------------------------------------------------------------------------
  // Logging
  // ---------------------------------------------------------------------------

  @override
  Future<String> getLog([Map<String, Object?>? query]) async {
    final result = await _methodChannel.invokeMethod<String>('getLog', query);
    return result ?? '';
  }

  @override
  Future<bool> destroyLog() async {
    final result = await _methodChannel.invokeMethod<bool>('destroyLog');
    return result ?? false;
  }

  @override
  Future<bool> emailLog(String email) async {
    final result = await _methodChannel.invokeMethod<bool>('emailLog', email);
    return result ?? false;
  }

  @override
  Future<bool> log(String level, String message) async {
    final result = await _methodChannel.invokeMethod<bool>('log', [
      level,
      message,
    ]);
    return result ?? false;
  }

  // ---------------------------------------------------------------------------
  // Scheduling
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>> startSchedule() async {
    return _invokeMap('startSchedule');
  }

  @override
  Future<Map<String, Object?>> stopSchedule() async {
    return _invokeMap('stopSchedule');
  }

  // ---------------------------------------------------------------------------
  // Headless
  // ---------------------------------------------------------------------------

  @override
  Future<bool> registerHeadlessTask(List<int> callbackIds) async {
    final result = await _methodChannel.invokeMethod<bool>(
      'registerHeadlessTask',
      callbackIds,
    );
    return result ?? false;
  }

  // ---------------------------------------------------------------------------
  // Audit Trail (Enterprise)
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>> verifyAuditTrail() async {
    return _invokeMap('verifyAuditTrail');
  }

  @override
  Future<Map<String, Object?>?> getAuditProof(String uuid) async {
    final result = await _methodChannel.invokeMapMethod<String, Object?>(
      'getAuditProof',
      uuid,
    );
    return result;
  }

  // ---------------------------------------------------------------------------
  // Privacy Zones (Enterprise)
  // ---------------------------------------------------------------------------

  @override
  Future<bool> addPrivacyZone(Map<String, Object?> zone) async {
    final result = await _methodChannel.invokeMethod<bool>(
      'addPrivacyZone',
      zone,
    );
    return result ?? false;
  }

  @override
  Future<bool> addPrivacyZones(List<Map<String, Object?>> zones) async {
    final result = await _methodChannel.invokeMethod<bool>(
      'addPrivacyZones',
      zones,
    );
    return result ?? false;
  }

  @override
  Future<bool> removePrivacyZone(String identifier) async {
    final result = await _methodChannel.invokeMethod<bool>(
      'removePrivacyZone',
      identifier,
    );
    return result ?? false;
  }

  @override
  Future<bool> removePrivacyZones() async {
    final result = await _methodChannel.invokeMethod<bool>(
      'removePrivacyZones',
    );
    return result ?? false;
  }

  @override
  Future<List<Map<String, Object?>>> getPrivacyZones() async {
    final result = await _methodChannel.invokeListMethod<Map>(
      'getPrivacyZones',
    );
    return result?.map(Map<String, Object?>.from).toList(growable: false) ?? [];
  }

  // ---------------------------------------------------------------------------
  // Encrypted Database (Enterprise)
  // ---------------------------------------------------------------------------

  @override
  Future<bool> isDatabaseEncrypted() async {
    final result = await _methodChannel.invokeMethod<bool>(
      'isDatabaseEncrypted',
    );
    return result ?? false;
  }

  @override
  Future<bool> encryptDatabase() async {
    final result = await _methodChannel.invokeMethod<bool>('encryptDatabase');
    return result ?? false;
  }

  // ---------------------------------------------------------------------------
  // Device Attestation (Enterprise)
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>?> getAttestationToken() async {
    final result = await _methodChannel.invokeMethod<Object?>(
      'getAttestationToken',
    );
    if (result is Map) {
      return Map<String, Object?>.from(result);
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Dead Reckoning (Enterprise)
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>?> getDeadReckoningState() async {
    final result = await _methodChannel.invokeMethod<Object?>(
      'getDeadReckoningState',
    );
    if (result is Map) {
      return Map<String, Object?>.from(result);
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Carbon Estimator (Enterprise)
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>> getCarbonReport([
    Map<String, Object?>? query,
  ]) async {
    return _invokeMap('getCarbonReport', query);
  }

  /// Convert [TlConfig] to a map for legacy [MethodChannel] transmission.
  Map<String, Object?> _tlConfigToMap(TlConfig config) {
    return {
      'geo': _geoToMap(config.geo),
      'app': _appToMap(config.app),
      'android': _androidToMap(config.android, config.geofence),
      'ios': _iosToMap(config.ios),
      'http': _httpToMap(config.http),
      'logger': _loggerToMap(config.logger),
      'motion': _motionToMap(config.motion),
      'geofence': _geofenceToMap(config.geofence, config.android),
      'persistence': _persistenceToMap(config.persistence),
      'audit': _auditToMap(config.audit),
      'privacyZone': _privacyZoneToMap(config.privacyZone),
      'security': _securityToMap(config.security),
      'attestation': _attestationToMap(config.attestation),
    };
  }

  Map<String, Object?> _geoToMap(TlGeoConfig c) => {
    if (c.desiredAccuracy != null) 'desiredAccuracy': c.desiredAccuracy!.index,
    if (c.distanceFilter != null) 'distanceFilter': c.distanceFilter,
    if (c.stationaryRadius != null) 'stationaryRadius': c.stationaryRadius,
    if (c.locationTimeout != null) 'locationTimeout': c.locationTimeout,
    if (c.disableElasticity != null) 'disableElasticity': c.disableElasticity,
    if (c.elasticityMultiplier != null)
      'elasticityMultiplier': c.elasticityMultiplier,
    if (c.stopAfterElapsedMinutes != null)
      'stopAfterElapsedMinutes': c.stopAfterElapsedMinutes,
    if (c.maxMonitoredGeofences != null)
      'maxMonitoredGeofences': c.maxMonitoredGeofences,
    if (c.enableTimestampMeta != null)
      'enableTimestampMeta': c.enableTimestampMeta,
    if (c.enableAdaptiveMode != null)
      'enableAdaptiveMode': c.enableAdaptiveMode,
    if (c.periodicLocationInterval != null)
      'periodicLocationInterval': c.periodicLocationInterval,
    if (c.periodicDesiredAccuracy != null)
      'periodicDesiredAccuracy': c.periodicDesiredAccuracy!.index,
    if (c.enableSparseUpdates != null)
      'enableSparseUpdates': c.enableSparseUpdates,
    if (c.sparseDistanceThreshold != null)
      'sparseDistanceThreshold': c.sparseDistanceThreshold,
    if (c.sparseMaxIdleSeconds != null)
      'sparseMaxIdleSeconds': c.sparseMaxIdleSeconds,
    if (c.enableDeadReckoning != null)
      'enableDeadReckoning': c.enableDeadReckoning,
    if (c.deadReckoningActivationDelay != null)
      'deadReckoningActivationDelay': c.deadReckoningActivationDelay,
    if (c.deadReckoningMaxDuration != null)
      'deadReckoningMaxDuration': c.deadReckoningMaxDuration,
    if (c.batteryBudgetPerHour != null)
      'batteryBudgetPerHour': c.batteryBudgetPerHour,
  };

  Map<String, Object?> _appToMap(TlAppConfig c) => {
    if (c.stopOnTerminate != null) 'stopOnTerminate': c.stopOnTerminate,
    if (c.startOnBoot != null) 'startOnBoot': c.startOnBoot,
    if (c.heartbeatInterval != null) 'heartbeatInterval': c.heartbeatInterval,
    if (c.schedule != null) 'schedule': c.schedule,
    if (c.remoteConfigUrl != null) 'remoteConfigUrl': c.remoteConfigUrl,
    if (c.remoteConfigHeaders != null)
      'remoteConfigHeaders': c.remoteConfigHeaders,
    if (c.remoteConfigTimeout != null)
      'remoteConfigTimeout': c.remoteConfigTimeout,
    if (c.remoteConfigRefreshInterval != null)
      'remoteConfigRefreshInterval': c.remoteConfigRefreshInterval,
  };

  /// [geofence] is threaded in only for `geofenceModeHighAccuracy`: the native
  /// side reads that key from the `android` block as well as the `geofence`
  /// one, and both must carry the same OR of the cross-platform flag with the
  /// deprecated Android-only one (#305).
  Map<String, Object?> _androidToMap(
    TlAndroidConfig c,
    TlGeofenceConfig geofence,
  ) => {
    if (c.locationUpdateInterval != null)
      'locationUpdateInterval': c.locationUpdateInterval,
    if (c.fastestLocationUpdateInterval != null)
      'fastestLocationUpdateInterval': c.fastestLocationUpdateInterval,
    if (c.deferTime != null) 'deferTime': c.deferTime,
    if (c.allowIdenticalLocations != null)
      'allowIdenticalLocations': c.allowIdenticalLocations,
    // Must be the same OR the geofence block carries: native reads this key
    // from both, so emitting the raw Android-only flag here would make
    // behavior depend on which block the platform happens to consult (#305).
    if (geofence.geofenceModeHighAccuracy != null ||
        c.geofenceModeHighAccuracy != null)
      'geofenceModeHighAccuracy':
          (geofence.geofenceModeHighAccuracy ?? false) ||
          (c.geofenceModeHighAccuracy ?? false),
    if (c.periodicUseForegroundService != null)
      'periodicUseForegroundService': c.periodicUseForegroundService,
    if (c.periodicUseExactAlarms != null)
      'periodicUseExactAlarms': c.periodicUseExactAlarms,
    if (c.scheduleUseAlarmManager != null)
      'scheduleUseAlarmManager': c.scheduleUseAlarmManager,
    if (c.foregroundService != null)
      'foregroundService': _fgToMap(c.foregroundService!),
  };

  /// Serializes the foreground-service section, omitting fields the caller
  /// never supplied.
  ///
  /// Every field is nullable and `null` means "not provided". The native merge
  /// skips absent keys, so a partial `setConfig()` leaves the persisted
  /// notification settings intact instead of overwriting them with defaults
  /// (#320).
  ///
  /// `showNotificationOnPauseOnly` was missing from this map altogether, so the
  /// flag never reached the platform over the method channel however it was
  /// configured — the same class of silent drop as the geofence flag in #305.
  Map<String, Object?> _fgToMap(TlForegroundServiceConfig c) => {
    if (c.enabled != null) 'enabled': c.enabled,
    if (c.channelId != null) 'channelId': c.channelId,
    if (c.channelName != null) 'channelName': c.channelName,
    if (c.notificationTitle != null) 'notificationTitle': c.notificationTitle,
    if (c.notificationText != null) 'notificationText': c.notificationText,
    if (c.notificationColor != null) 'notificationColor': c.notificationColor,
    if (c.notificationSmallIcon != null)
      if (c.notificationSmallIcon != null)
        'notificationSmallIcon': c.notificationSmallIcon,
    if (c.notificationLargeIcon != null)
      if (c.notificationLargeIcon != null)
        'notificationLargeIcon': c.notificationLargeIcon,
    if (c.notificationStartedAt != null)
      'notificationStartedAt': c.notificationStartedAt,
    if (c.notificationShowTimer != null)
      'notificationShowTimer': c.notificationShowTimer,
    if (c.notificationOnlyAlertOnce != null)
      'notificationOnlyAlertOnce': c.notificationOnlyAlertOnce,
    if (c.notificationPriority != null)
      'notificationPriority': c.notificationPriority!.index - 2,
    if (c.notificationOngoing != null)
      if (c.notificationOngoing != null)
        'notificationOngoing': c.notificationOngoing,
    if (c.showNotificationOnPauseOnly != null)
      if (c.showNotificationOnPauseOnly != null)
        'showNotificationOnPauseOnly': c.showNotificationOnPauseOnly,
    if (c.actions != null) 'actions': c.actions,
  };

  Map<String, Object?> _iosToMap(TlIosConfig c) => {
    if (c.activityType != null) 'activityType': c.activityType!.index,
    if (c.useSignificantChangesOnly != null)
      'useSignificantChangesOnly': c.useSignificantChangesOnly,
    if (c.showsBackgroundLocationIndicator != null)
      'showsBackgroundLocationIndicator': c.showsBackgroundLocationIndicator,
    if (c.pausesLocationUpdatesAutomatically != null)
      'pausesLocationUpdatesAutomatically':
          c.pausesLocationUpdatesAutomatically,
    'locationAuthorizationRequest':
        c.locationAuthorizationRequest == TlAuthorizationRequest.always
        ? 'Always'
        : 'WhenInUse',
    if (c.disableLocationAuthorizationAlert != null)
      'disableLocationAuthorizationAlert': c.disableLocationAuthorizationAlert,
    if (c.preventSuspend != null) 'preventSuspend': c.preventSuspend,
    if (c.liveActivityConfig != null)
      'liveActivityConfig': {
        if (c.liveActivityConfig!.title != null)
          'title': c.liveActivityConfig!.title,
        if (c.liveActivityConfig!.body != null)
          'body': c.liveActivityConfig!.body,
        if (c.liveActivityConfig!.startedAt != null)
          'startedAt': c.liveActivityConfig!.startedAt,
        if (c.liveActivityConfig!.showTimer != null)
          'showTimer': c.liveActivityConfig!.showTimer,
      },
  };

  Map<String, Object?> _httpToMap(TlHttpConfig c) => {
    if (c.url != null) 'url': c.url,
    if (c.method != null) 'method': c.method!.index,
    if (c.headers != null) 'headers': c.headers,
    if (c.httpRootProperty != null) 'httpRootProperty': c.httpRootProperty,
    if (c.batchSync != null) 'batchSync': c.batchSync,
    if (c.maxBatchSize != null) 'maxBatchSize': c.maxBatchSize,
    if (c.autoSync != null) 'autoSync': c.autoSync,
    if (c.autoSyncThreshold != null) 'autoSyncThreshold': c.autoSyncThreshold,
    if (c.syncInterval != null) 'syncInterval': c.syncInterval,
    if (c.httpTimeout != null) 'httpTimeout': c.httpTimeout,
    if (c.params != null) 'params': c.params,
    if (c.locationsOrderDirection != null)
      'locationsOrderDirection': c.locationsOrderDirection!.index,
    if (c.extras != null) 'extras': c.extras,
    if (c.disableAutoSyncOnCellular != null)
      'disableAutoSyncOnCellular': c.disableAutoSyncOnCellular,
    if (c.maxRetries != null) 'maxRetries': c.maxRetries,
    if (c.retryBackoffBase != null) 'retryBackoffBase': c.retryBackoffBase,
    if (c.retryBackoffCap != null) 'retryBackoffCap': c.retryBackoffCap,
    if (c.enableDeltaCompression != null)
      'enableDeltaCompression': c.enableDeltaCompression,
    if (c.deltaCoordinatePrecision != null)
      'deltaCoordinatePrecision': c.deltaCoordinatePrecision,
    if (c.sslPinningCertificates != null)
      'sslPinningCertificates': c.sslPinningCertificates,
    if (c.sslPinningFingerprints != null)
      'sslPinningFingerprints': c.sslPinningFingerprints,
  };

  Map<String, Object?> _loggerToMap(TlLoggerConfig c) => {
    if (c.logLevel != null) 'logLevel': c.logLevel!.index,
    if (c.logMaxDays != null) 'logMaxDays': c.logMaxDays,
    if (c.debug != null) 'debug': c.debug,
  };

  Map<String, Object?> _motionToMap(TlMotionConfig c) => {
    if (c.stopTimeout != null) 'stopTimeout': c.stopTimeout,
    if (c.motionTriggerDelay != null)
      'motionTriggerDelay': c.motionTriggerDelay,
    if (c.disableMotionActivityUpdates != null)
      'disableMotionActivityUpdates': c.disableMotionActivityUpdates,
    if (c.isMoving != null) 'isMoving': c.isMoving,
    if (c.activityRecognitionInterval != null)
      'activityRecognitionInterval': c.activityRecognitionInterval,
    'minimumActivityRecognitionConfidence':
        c.minimumActivityRecognitionConfidence,
    if (c.disableStopDetection != null)
      'disableStopDetection': c.disableStopDetection,
    if (c.stopDetectionDelay != null)
      'stopDetectionDelay': c.stopDetectionDelay,
    if (c.stopOnStationary != null) 'stopOnStationary': c.stopOnStationary,
    'activityTypes': c.activityTypes?.map((e) => e?.name).toList(),
  };

  /// #305: this previously emitted only two of the five geofence keys, silently
  /// dropping `geofenceModeHighAccuracy`, `geofenceInitialTrigger` and
  /// `geofenceExitAccuracyMax` (the #276 tunable) on the method-channel
  /// transport. High-accuracy mode is the cross-platform flag OR'd with the
  /// deprecated Android-only one, matching both Pigeon host implementations —
  /// hence [android] is needed here.
  Map<String, Object?> _geofenceToMap(
    TlGeofenceConfig c,
    TlAndroidConfig android,
  ) => {
    if (c.geofenceInitialTriggerEntry != null)
      'geofenceInitialTriggerEntry': c.geofenceInitialTriggerEntry,
    if (c.geofenceInitialTrigger != null)
      'geofenceInitialTrigger': c.geofenceInitialTrigger,
    if (c.geofenceProximityRadius != null)
      'geofenceProximityRadius': c.geofenceProximityRadius,
    if (c.geofenceModeHighAccuracy != null ||
        android.geofenceModeHighAccuracy != null)
      'geofenceModeHighAccuracy':
          (c.geofenceModeHighAccuracy ?? false) ||
          (android.geofenceModeHighAccuracy ?? false),
    if (c.geofenceExitAccuracyMax != null)
      'geofenceExitAccuracyMax': c.geofenceExitAccuracyMax,
  };

  Map<String, Object?> _persistenceToMap(TlPersistenceConfig c) => {
    if (c.persistMode != null) 'persistMode': c.persistMode!.index,
    if (c.maxDaysToPersist != null) 'maxDaysToPersist': c.maxDaysToPersist,
    if (c.maxRecordsToPersist != null)
      'maxRecordsToPersist': c.maxRecordsToPersist,
  };

  Map<String, Object?> _auditToMap(TlAuditConfig c) => {
    if (c.enabled != null) 'enabled': c.enabled,
    if (c.hashAlgorithm != null) 'hashAlgorithm': c.hashAlgorithm!.index,
  };

  Map<String, Object?> _privacyZoneToMap(TlPrivacyZoneConfig c) => {
    if (c.enabled != null) 'enabled': c.enabled,
  };

  Map<String, Object?> _securityToMap(TlSecurityConfig c) => {
    if (c.encryptDatabase != null) 'encryptDatabase': c.encryptDatabase,
  };

  Map<String, Object?> _attestationToMap(TlAttestationConfig c) => {
    if (c.enabled != null) 'enabled': c.enabled,
    if (c.refreshInterval != null) 'refreshInterval': c.refreshInterval,
  };
}
