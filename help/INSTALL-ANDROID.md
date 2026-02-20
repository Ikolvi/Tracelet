# Android Setup Guide

This guide covers everything you need to configure in your Flutter app's Android project to use Tracelet.

---

## 1. Minimum Requirements

| Requirement        | Value             |
|--------------------|-------------------|
| `minSdk`           | **26** (Android 8.0 Oreo) |
| `compileSdk`       | **34+** (recommended 36) |
| `targetSdk`        | **34+** |
| Kotlin             | **1.9+** |
| Gradle AGP         | **8.0+** |

In your app's `android/app/build.gradle`:

```groovy
android {
    compileSdk = 36   // or 34+

    defaultConfig {
        minSdk = 26
        targetSdk = 36
    }
}
```

---

## 2. Permissions

Tracelet's plugin AndroidManifest automatically merges the following permissions into your app:

| Permission | Purpose |
|---|---|
| `ACCESS_FINE_LOCATION` | GPS location |
| `ACCESS_COARSE_LOCATION` | Network location |
| `ACCESS_BACKGROUND_LOCATION` | Background tracking (Android 10+) |
| `FOREGROUND_SERVICE` | Foreground service |
| `FOREGROUND_SERVICE_LOCATION` | Location-type foreground service (Android 14+) |
| `ACTIVITY_RECOGNITION` | Motion activity detection |
| `RECEIVE_BOOT_COMPLETED` | Start on boot |
| `WAKE_LOCK` | Background processing |
| `ACCESS_NETWORK_STATE` | Connectivity monitoring |
| `INTERNET` | HTTP sync |
| `POST_NOTIFICATIONS` | Notification (Android 13+) |

**You do not need to add these to your app's `AndroidManifest.xml`** — they are merged automatically from the plugin.

### Runtime Permissions

The plugin requests permissions at runtime when you call `Tracelet.requestPermission()`. The flow is:

1. `ACCESS_FINE_LOCATION` (or `ACCESS_COARSE_LOCATION`)
2. `ACCESS_BACKGROUND_LOCATION` (separate dialog on Android 11+)
3. `ACTIVITY_RECOGNITION` (Android 10+)
4. `POST_NOTIFICATIONS` (Android 13+)

---

## 3. Foreground Service Notification

When background tracking is active, Android requires a persistent notification. Configure it in your `Config`:

```dart
await Tracelet.ready(Config(
  app: AppConfig(
    foregroundService: ForegroundServiceConfig(
      channelId: 'tracelet_channel',
      channelName: 'Location Tracking',
      notificationTitle: 'My App',
      notificationText: 'Tracking your route',
      notificationSmallIcon: 'drawable/ic_notification',
      notificationPriority: 0,  // DEFAULT
    ),
  ),
));
```

### Custom Notification Icon

Place your icon in `android/app/src/main/res/drawable/`:

```
android/app/src/main/res/
  drawable/
    ic_notification.png      (24×24dp)
  drawable-hdpi/
    ic_notification.png      (36×36px)
  drawable-xhdpi/
    ic_notification.png      (48×48px)
  drawable-xxhdpi/
    ic_notification.png      (72×72px)
```

Reference it as `'drawable/ic_notification'` (without the extension).

---

## 4. Background Location on Android 11+

Starting with Android 11 (API 30), **background location must be granted separately** from foreground location. The user must:

1. Grant "While using the app" first
2. Then go to Settings → grant "Allow all the time"

Tracelet handles this flow automatically when you call `Tracelet.requestPermission()`.

---

## 5. Battery Optimization

Some OEMs (Samsung, Xiaomi, Huawei, OnePlus, etc.) aggressively kill background apps. To ensure reliable tracking:

```dart
// Check if app is whitelisted
final ignored = await Tracelet.isIgnoringBatteryOptimizations();

if (!ignored) {
  // Prompt user to whitelist the app
  await Tracelet.requestSettings('ignoreBackgroundOptimizations');
}
```

> **Tip:** Visit [dontkillmyapp.com](https://dontkillmyapp.com) for device-specific guidance.

---

## 6. ProGuard / R8 Rules

Tracelet uses Google Play Services and OkHttp, which have their own ProGuard rules bundled with their AARs. No additional ProGuard configuration is needed for release builds.

If you encounter issues, add to `android/app/proguard-rules.pro`:

```proguard
-keep class com.tracelet.** { *; }
-keep class com.google.android.gms.location.** { *; }
```

And in `android/app/build.gradle`:

```groovy
buildTypes {
    release {
        minifyEnabled true
        proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'),
                      'proguard-rules.pro'
    }
}
```

---

## 7. Google Play Services

Tracelet uses the **Fused Location Provider** from Google Play Services. This is available on all Google-certified devices. If you need to support devices without Google Play Services (e.g., Huawei HMS), custom integration would be required.

The plugin dependency (automatically included):
```
com.google.android.gms:play-services-location:21.3.0
```

---

## 8. Start on Boot

To resume tracking after a device reboot:

```dart
await Tracelet.ready(Config(
  app: AppConfig(
    stopOnTerminate: false,  // Keep tracking when app is killed
    startOnBoot: true,       // Resume after reboot
  ),
));
```

The plugin automatically registers a `BOOT_COMPLETED` broadcast receiver.

---

## 9. Headless Mode

To execute Dart code in the background when the app is terminated:

```dart
// Must be a top-level or static function
void headlessTask(HeadlessEvent event) {
  print('[Headless] ${event.name}: ${event.event}');
}

// Register in your main()
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Tracelet.registerHeadlessTask(headlessTask);
  runApp(MyApp());
}
```

---

## 10. Example AndroidManifest.xml

Here is a minimal `AndroidManifest.xml` for your app. Tracelet's permissions are merged automatically — you only need your app-specific entries:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="My App"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
                android:name="io.flutter.embedding.android.NormalTheme"
                android:resource="@style/NormalTheme" />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>

        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
</manifest>
```

---

## Troubleshooting

### Location updates stop after a few minutes
- Ensure `stopOnTerminate: false`
- Check battery optimization settings
- Enable `debug: true` in `LoggerConfig` to see logs

### "App is running in the background" notification
- This is the required foreground service notification
- Customize it via `ForegroundServiceConfig`

### Permission denied errors
- Call `Tracelet.requestPermission()` before `Tracelet.start()`
- On Android 11+, background location requires a separate grant

### Build errors with Google Play Services
- Ensure your `compileSdk` is 34+
- Run `./gradlew dependencies` to check for version conflicts
