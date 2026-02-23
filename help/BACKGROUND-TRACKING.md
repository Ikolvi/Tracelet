# Background Tracking

---

## With Foreground Notification (Recommended)

The foreground service keeps the app alive reliably in the background on Android.
A persistent notification is shown while tracking.

> **Android 13+:** You must request notification permission (`POST_NOTIFICATIONS`)
> before starting the foreground service, otherwise the notification will be
> hidden. See [Permissions Guide](PERMISSIONS.md#notification-permission-android-13).

> **iOS:** Foreground service config is ignored — iOS uses its own
> background-mode mechanisms (BackgroundTasks, CoreLocation significant
> changes). No notification permission is needed for background location.

```dart
// 1. Request notification permission (Android 13+)
if (Platform.isAndroid) {
  final notifStatus = await tl.Tracelet.getNotificationPermissionStatus();
  if (notifStatus != 3) {
    await tl.Tracelet.requestNotificationPermission();
  }
}

// 2. Configure and start
await tl.Tracelet.ready(tl.Config(
  app: tl.AppConfig(
    stopOnTerminate: false,
    startOnBoot: true,
    foregroundService: tl.ForegroundServiceConfig(
      notificationTitle: 'My App',
      notificationText: 'Tracking your location',
    ),
  ),
));
await tl.Tracelet.start();
```

### Custom Notification Icon

By default the notification uses the app launcher icon. To use a custom icon,
add a drawable resource to your Android project and reference it by name
(without the file extension or `res/drawable` prefix):

**1. Add the icon file:**

```
android/app/src/main/res/
├── drawable-mdpi/my_notification_icon.png      (24×24)
├── drawable-hdpi/my_notification_icon.png      (36×36)
├── drawable-xhdpi/my_notification_icon.png     (48×48)
├── drawable-xxhdpi/my_notification_icon.png    (72×72)
└── drawable-xxxhdpi/my_notification_icon.png   (96×96)
```

> **Tip:** Notification icons must be **monochrome white on transparent** per
> Material Design guidelines. Android tints them with the system accent color.
> Using a colorful icon will appear as a solid white square.

**2. Reference it in config:**

```dart
foregroundService: tl.ForegroundServiceConfig(
  notificationTitle: 'My App',
  notificationText: 'Tracking your location',
  notificationSmallIcon: 'my_notification_icon', // drawable resource name
),
```

> On iOS, foreground service configuration is ignored entirely — no
> notification icon is needed.

---

## Without Foreground Notification

No notification is shown. Suitable for short-lived tasks like check-ins,
one-shot location fetches, or foreground-only use. The OS may kill the app
in the background at any time.

```dart
await tl.Tracelet.ready(tl.Config(
  app: tl.AppConfig(
    stopOnTerminate: true,
    foregroundService: tl.ForegroundServiceConfig(enabled: false),
  ),
));
await tl.Tracelet.start();
```

---

## Switching at Runtime

You can switch between modes at runtime using `setConfig()`:

```dart
// Switch to background tracking with notification
await tl.Tracelet.setConfig(tl.Config(
  app: tl.AppConfig(
    stopOnTerminate: false,
    startOnBoot: true,
    foregroundService: tl.ForegroundServiceConfig(
      notificationTitle: 'My App',
      notificationText: 'Background tracking active',
    ),
  ),
));
await tl.Tracelet.start();

// Switch to no-notification mode
await tl.Tracelet.setConfig(tl.Config(
  app: tl.AppConfig(
    stopOnTerminate: true,
    foregroundService: tl.ForegroundServiceConfig(enabled: false),
  ),
));
await tl.Tracelet.start();
```
