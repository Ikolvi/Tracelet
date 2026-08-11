import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet/tracelet.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

void main() {
  late _NotificationPlatform platform;

  setUp(() {
    platform = _NotificationPlatform();
    TraceletPlatform.instance = platform;
  });

  test('all-null update does not call the platform', () async {
    await Tracelet.setNotification();

    expect(platform.updates, isEmpty);
  });

  test('partial update sends only supplied fields', () async {
    await Tracelet.setNotification(text: 'Uploading', showTimer: false);

    expect(platform.updates, hasLength(1));
    final update = platform.updates.single;
    expect(update.title, isNull);
    expect(update.text, 'Uploading');
    expect(update.startedAt, isNull);
    expect(update.showTimer, isFalse);
  });

  test(
    'activeConfig mirrors merged Android and iOS notification state',
    () async {
      const initial = Config(
        android: AndroidConfig(
          foregroundService: ForegroundServiceConfig(
            channelId: 'tracking',
            notificationTitle: 'Old title',
            notificationText: 'Old body',
          ),
        ),
        ios: IosConfig(
          liveActivityConfig: LiveActivityConfig(
            title: 'Old title',
            body: 'Old body',
          ),
        ),
        http: HttpConfig(url: 'https://example.test/locations'),
      );
      await Tracelet.ready(initial);

      await Tracelet.setNotification(
        title: 'New title',
        text: 'New body',
        startedAt: 4294967296,
        showTimer: true,
      );

      final active = Tracelet.activeConfig;
      expect(active.http.url, 'https://example.test/locations');
      expect(active.android.foregroundService.channelId, 'tracking');
      expect(active.android.foregroundService.notificationTitle, 'New title');
      expect(active.android.foregroundService.notificationText, 'New body');
      expect(
        active.android.foregroundService.notificationStartedAt,
        4294967296,
      );
      expect(active.android.foregroundService.notificationShowTimer, isTrue);
      expect(active.ios.liveActivityConfig?.title, 'New title');
      expect(active.ios.liveActivityConfig?.body, 'New body');
      expect(active.ios.liveActivityConfig?.startedAt, 4294967296);
      expect(active.ios.liveActivityConfig?.showTimer, isTrue);
    },
  );

  test(
    'iOS mirror stays absent when no Live Activity was configured',
    () async {
      await Tracelet.ready(
        const Config(http: HttpConfig(url: 'https://example.test/locations')),
      );

      await Tracelet.setNotification(title: 'Android only');

      expect(Tracelet.activeConfig.ios.liveActivityConfig, isNull);
      expect(
        Tracelet.activeConfig.android.foregroundService.notificationTitle,
        'Android only',
      );
      expect(Tracelet.activeConfig.http.url, 'https://example.test/locations');
    },
  );
}

class _NotificationPlatform extends TraceletPlatform {
  final List<TlNotificationUpdate> updates = <TlNotificationUpdate>[];

  final Map<String, Object?> _state = <String, Object?>{
    'enabled': false,
    'trackingMode': 0,
    'isMoving': false,
    'schedulerEnabled': false,
    'odometer': 0.0,
  };

  @override
  Future<Map<String, Object?>> ready(TlConfig config) async =>
      Map<String, Object?>.from(_state);

  @override
  Future<void> setNotification(TlNotificationUpdate update) async {
    updates.add(update);
  }

  @override
  Stream<Map<String?, Object?>> get remoteConfigEvents => const Stream.empty();
}
