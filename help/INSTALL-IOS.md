# iOS Setup Guide

This guide covers everything you need to configure in your Flutter app's iOS project to use Tracelet.

---

## 1. Minimum Requirements

| Requirement        | Value             |
|--------------------|-------------------|
| iOS Deployment Target | **14.0+** |
| Xcode              | **15.0+** |
| Swift               | **5.0+** |
| CocoaPods           | **1.12+** |

In your `ios/Podfile`:

```ruby
platform :ios, '14.0'
```

---

## 2. Info.plist — Required Keys

Add these entries to `ios/Runner/Info.plist`:

### Location Usage Descriptions (Required)

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location to track your route.</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>We need your location in the background to record your route even when the app is closed.</string>
```

> **Important:** Both keys are required. iOS will reject the app if either is missing.

### Motion Usage Description (Required for motion detection)

```xml
<key>NSMotionUsageDescription</key>
<string>We use motion data to detect when you start and stop moving, saving battery by pausing GPS when stationary.</string>
```

### Background Modes (Required)

```xml
<key>UIBackgroundModes</key>
<array>
    <string>location</string>
    <string>fetch</string>
    <string>processing</string>
</array>
```

| Mode | Purpose |
|---|---|
| `location` | Continuous background location updates |
| `fetch` | Background fetch for headless Dart execution |
| `processing` | `BGTaskScheduler` for scheduled tracking |

### Temporary Full Accuracy (iOS 14+, Optional)

To use `Tracelet.requestTemporaryFullAccuracy()`:

```xml
<key>NSLocationTemporaryUsageDescriptionDictionary</key>
<dict>
    <key>TemporaryFullAccuracy</key>
    <string>We need precise location for accurate route tracking.</string>
</dict>
```

The key name (`TemporaryFullAccuracy`) must match the `purpose` argument you pass:

```dart
await Tracelet.requestTemporaryFullAccuracy('TemporaryFullAccuracy');
```

---

## 3. Enabling Background Modes in Xcode

If you prefer to use Xcode instead of editing `Info.plist` directly:

1. Open `ios/Runner.xcworkspace` in Xcode
2. Select the **Runner** target
3. Go to **Signing & Capabilities**
4. Click **+ Capability**
5. Add **Background Modes**
6. Check:
   - ☑ **Location updates**
   - ☑ **Background fetch**
   - ☑ **Background processing**

---

## 4. Complete Info.plist Example

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Existing Flutter keys ... -->

    <!-- Location -->
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>We need your location to track your route.</string>

    <key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
    <string>We need your location in the background to record your route even when the app is closed.</string>

    <!-- Motion -->
    <key>NSMotionUsageDescription</key>
    <string>Motion detection allows battery-efficient tracking by pausing GPS when stationary.</string>

    <!-- Background Modes -->
    <key>UIBackgroundModes</key>
    <array>
        <string>location</string>
        <string>fetch</string>
        <string>processing</string>
    </array>

    <!-- Temporary Full Accuracy (optional) -->
    <key>NSLocationTemporaryUsageDescriptionDictionary</key>
    <dict>
        <key>TemporaryFullAccuracy</key>
        <string>Precise location is needed for accurate route tracking.</string>
    </dict>
</dict>
</plist>
```

---

## 5. Permission Flow

Tracelet handles the permission request flow when you call `Tracelet.requestPermission()`:

1. **When In Use** → Prompts the standard iOS location dialog
2. **Always** → If `Config` requires background tracking, prompts the "Allow Always" dialog

```dart
final status = await Tracelet.requestPermission();
// Returns AuthorizationStatus index: 0=notDetermined, 1=denied, 2=whenInUse, 3=always, 4=deniedForever
```

### iOS 13 vs 14+ Behavior

- **iOS 13:** "Always" can be granted directly from the first dialog
- **iOS 14+:** User must first grant "When In Use", then separately grant "Always" via a second prompt or Settings

---

## 6. Background Location Indicator

When Tracelet tracks location in the background, iOS shows the blue location indicator in the status bar. This is expected system behavior and cannot be suppressed. It assures users that location is being accessed.

---

## 7. Significant Location Changes

When the device is stationary and Tracelet enters its low-power mode, it uses `startMonitoringSignificantLocationChanges()` instead of continuous GPS. This wakes the app for major position changes (~500m) using cell tower triangulation — near-zero battery impact.

---

## 8. Start on Boot / After Termination

iOS does not have a "boot completed" event like Android. However, Tracelet uses two mechanisms to resume tracking:

1. **Significant location changes** — iOS will relaunch the app in the background when a significant location change occurs
2. **BGTaskScheduler** — Scheduled background tasks can relaunch the app

```dart
await Tracelet.ready(Config(
  app: AppConfig(
    stopOnTerminate: false,  // Resume tracking after app kill
  ),
));
```

---

## 9. Headless Mode

To execute Dart code when the app is launched in the background:

```dart
void headlessTask(HeadlessEvent event) {
  print('[Headless] ${event.name}: ${event.event}');
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Tracelet.registerHeadlessTask(headlessTask);
  runApp(MyApp());
}
```

When iOS relaunches the app in the background, Tracelet spins up a headless `FlutterEngine` and dispatches events to your registered callback.

---

## 10. Podfile Configuration

A minimal `ios/Podfile` for Tracelet:

```ruby
platform :ios, '14.0'

# CocoaPods analytics sends network stats synchronously
# affecting flutter build latency.
ENV['COCOAPODS_DISABLE_STATS'] = 'true'

target 'Runner' do
  use_frameworks!
  use_modular_headers!

  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'
    end
  end
end
```

---

## 11. App Store Submission

When submitting to the App Store, Apple requires justification for background location:

1. **Explain clearly** in your app description why background location is needed
2. **Provide a demo video** showing the feature in action
3. **Usage descriptions must be user-friendly** — explain the benefit to the user, not the technical reason
4. **Use only the background modes you need** — remove `processing` if you don't use scheduling

### Common Rejection Reasons

- Vague usage descriptions (e.g., "We need your location")
- Using "Always" permission without clear justification
- No visible benefit to the user for background tracking

---

## Troubleshooting

### Location updates stop when app is backgrounded
- Ensure `UIBackgroundModes` includes `location`
- Verify "Always" permission is granted (check Settings → Your App → Location)
- Enable `debug: true` in `LoggerConfig` to see logs

### "This app has crashed because it attempted to access privacy-sensitive data"
- You're missing an `NSLocation*UsageDescription` key in `Info.plist`
- Both `NSLocationWhenInUseUsageDescription` and `NSLocationAlwaysAndWhenInUseUsageDescription` are required

### "Unsupported OS" or build errors
- Ensure your `Podfile` has `platform :ios, '14.0'`
- Run `cd ios && pod install --repo-update`

### Motion detection not working
- Add `NSMotionUsageDescription` to `Info.plist`
- Motion is only available on physical devices (not simulator)

### Headless task not firing
- Ensure `registerHeadlessTask` is called in `main()` before `runApp()`
- The callback must be a top-level or static function
