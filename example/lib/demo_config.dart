import 'package:flutter/foundation.dart';
import 'package:tracelet/tracelet.dart' as tl;

bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// The canonical Tracelet configuration for this demo app.
///
/// Used by the home page's `ready()` **and** by the issue cards' run harness
/// (`prepareIssueRun`), which is the reason it lives here rather than on
/// `_MyHomePageState`.
///
/// Config is *merged*, not replaced — `ready()` and `setConfig()` both land in
/// the same `ConfigManager.setConfig`, and a field the caller leaves null keeps
/// whatever was there before. So whatever was applied last stays in force, and
/// a card that sets two keys inherits every other key from whoever configured
/// the SDK before it. When that was "the home page, if the user happened to
/// press Initialize" the cards were reading a different SDK depending on how
/// the app had been driven — and after a card that changed a key, depending on
/// which cards had already been run. Handing every run this one baseline first
/// makes each card start from the same documented state; cards that need
/// something else still say so afterwards and win.
tl.Config buildDemoConfig() {
  return tl.Config(
    classifier: const tl.ClassifierConfig(
      enableFusedClassifier: true, // required — classifier must be running
      autoTuneFromTransportMode: true,
    ),
    geo: const tl.GeoConfig(
      distanceFilter: 0,
      resolveAddress: true,
      filter: tl.LocationFilter(
        useKalmanFilter: true,
        mockDetectionLevel: 2, // 2 = HEURISTIC
      ),
      // ── Battery budget (auto-adjusts tracking to save battery) ──
      batteryBudgetPerHour: 3, // 3% max drain per hour
    ),
    app: const tl.AppConfig(
      stopOnTerminate: false,
      startOnBoot: true,
      heartbeatInterval: 10,
    ),
    android: tl.AndroidConfig(
      periodicUseForegroundService: true, // KEEP NOTIFICATION ALIVE
      locationUpdateInterval: 2000, // 2s
      deferTime: 1000, // 10s — batches ~5 locations every 10s
      foregroundService: _isAndroid
          ? const tl.ForegroundServiceConfig(
              notificationTitle: '📍 Tracelet Demo Active',
              notificationText:
                  'Smart Notifications — disappears when app is open!',
              channelId: 'tracelet_demo_channel',
              channelName: 'Tracelet Demo Background',
              notificationPriority: tl.NotificationPriority.high,
              showNotificationOnPauseOnly:
                  true, // ✨ Smart Visibility — hide while app is foregrounded
            )
          : const tl.ForegroundServiceConfig(enabled: false),
      scheduleUseAlarmManager: _isAndroid, // Android-only: exact alarms
    ),
    ios: tl.IosConfig(
      activityType: _isAndroid
          ? tl.LocationActivityType.other
          : tl.LocationActivityType.otherNavigation,
      preventSuspend: !_isAndroid, // iOS-only: silent-audio keep-alive
      useBackgroundActivitySession: !_isAndroid, // iOS 17+: Dynamic Island
      liveActivityConfig: !_isAndroid
          ? const tl.LiveActivityConfig(
              title: 'Tracelet Active',
              body: 'Tracking your route in background',
            )
          : null,
    ),
    motion: const tl.MotionConfig(
      stopTimeout: 1, // 1 minute for fast stop-timeout testing
      motionDetectionMode: tl.MotionDetectionMode.smart,
      shakeThreshold: 2, // prevent ultra-sensitive motion triggering
      speedStationaryDelay: 30, // Make it quicker for demo testing
      stationaryPeriodicInterval: 60, // Quick checks when stationary
    ),
    http: tl.HttpConfig(
      url:
          tl.Tracelet.activeConfig.http.url ??
          'http://192.168.20.103:8099/locations',
      autoSyncDelay: 5000,
    ),
    audit: const tl.AuditConfig(enabled: true),
    security: const tl.SecurityConfig(encryptDatabase: true),
    persistence: const tl.PersistenceConfig(
      maxDaysToPersist: 7,
      maxRecordsToPersist: 5000,
    ),
    logger: const tl.LoggerConfig(logLevel: tl.LogLevel.verbose, debug: true),
  );
}
