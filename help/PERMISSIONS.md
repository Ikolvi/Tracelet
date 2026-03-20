# Permissions Guide

Tracelet does **not** show any native permission dialogs — only the OS
permission prompt is triggered. Permission flow is fully controlled from Dart,
giving you complete freedom to customize the UI, translations, animations,
and behavior.

---

## Permission API

| Method | Returns | Description |
|---|---|---|
| `Tracelet.getPermissionStatus()` | `Future<int>` | Read-only check — no dialog triggered |
| `Tracelet.requestPermission()` | `Future<int>` | Triggers OS dialog, returns **actual** result |
| `Tracelet.getNotificationPermissionStatus()` | `Future<int>` | Notification permission status (Android 13+) |
| `Tracelet.requestNotificationPermission()` | `Future<int>` | Request POST_NOTIFICATIONS (Android 13+) |
| `Tracelet.getMotionPermissionStatus()` | `Future<int>` | Motion/activity recognition status |
| `Tracelet.requestMotionPermission()` | `Future<int>` | Request motion permission |
| `Tracelet.openAppSettings()` | `Future<bool>` | Opens the app's system settings page |
| `Tracelet.openLocationSettings()` | `Future<bool>` | Opens device location settings |
| `Tracelet.openBatterySettings()` | `Future<bool>` | Opens battery optimization settings (Android) |

---

## Authorization Status Codes

| Code | Enum Value | Meaning |
|------|------------|---------|
| `0` | `notDetermined` | Permission has never been requested |
| `1` | `denied` | User denied, but can ask again (Android only) |
| `2` | `whenInUse` | Foreground location granted |
| `3` | `always` | Background location granted |
| `4` | `deniedForever` | Permanently denied — must open Settings |

---

## Escalation Logic

`requestPermission()` automatically escalates to the next level:

| Current Status | Action Taken |
|----------------|-------------|
| `notDetermined` / `denied` | Requests **foreground** (When In Use) permission |
| `whenInUse` | Requests **background** (Always) permission |
| `always` / `deniedForever` | Returns immediately — no dialog shown |

---

## Recommended Permission Flow

```dart
import 'package:tracelet/tracelet.dart' as tl;
import 'package:flutter/material.dart';

Future<void> initializeWithPermissions(BuildContext context) async {
  // 1. Check current status (no dialog)
  final status = await tl.Tracelet.getPermissionStatus();

  // 2. Handle each case
  switch (status) {
    case 0: // notDetermined
    case 1: // denied (can ask again)
      final result = await tl.Tracelet.requestPermission();
      if (result == 4) {
        // Permanently denied — show YOUR dialog
        _showDeniedDialog(context);
        return;
      }
      if (result == 2) {
        // Foreground granted — show rationale then request background
        final upgrade = await _showBackgroundRationale(context);
        if (upgrade) await tl.Tracelet.requestPermission();
      }
      break;

    case 2: // whenInUse — offer background upgrade
      final upgrade = await _showBackgroundRationale(context);
      if (upgrade) await tl.Tracelet.requestPermission();
      break;

    case 4: // deniedForever
      _showDeniedDialog(context);
      return;
  }

  // 3. Now safe to initialize and start
  await tl.Tracelet.ready(tl.Config(/* ... */));
  await tl.Tracelet.start();
}
```

---

## Dart-Side Permission Dialogs (Example Implementations)

### Permanently Denied Dialog

Show when `getPermissionStatus()` or `requestPermission()` returns `4` (deniedForever):

```dart
void _showDeniedDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.location_off, color: Colors.red, size: 48),
      title: const Text('Location Permission Required'),
      content: const Text(
        'Location permission has been permanently denied. '
        'Tracelet cannot track your location without it.\n\n'
        'Please open Settings and enable location access '
        'for this app to resume tracking.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Not Now'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(ctx);
            tl.Tracelet.openAppSettings();
          },
          icon: const Icon(Icons.settings),
          label: const Text('Open Settings'),
        ),
      ],
    ),
  );
}
```

### Background Permission Rationale Dialog

Show **before** requesting background (Always) permission to explain why it's needed:

```dart
Future<bool> _showBackgroundRationale(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.share_location, color: Colors.indigo, size: 48),
      title: const Text('Background Location Access'),
      content: const Text(
        'This app needs background location access to continue '
        'recording your location when the app is not in the foreground.\n\n'
        'On the next screen, select "Allow all the time" to enable '
        'background tracking.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Keep Foreground Only'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.upgrade),
          label: const Text('Change to "Allow all the time"'),
        ),
      ],
    ),
  );
  return result ?? false;
}
```

> **Tip:** You can replace these `AlertDialog` widgets with any Flutter widget —
> bottom sheets, custom pages, Cupertino dialogs, or animated overlays.
> The permission API is UI-agnostic.

---

## Notification Permission (Android 13+)

Starting with Android 13 (API 33), the `POST_NOTIFICATIONS` runtime permission
is required for the foreground service notification to be visible. Without it,
the service still runs but the notification is hidden — and some OEMs may then
kill the background process.

`getNotificationPermissionStatus()` and `requestNotificationPermission()` return
the same status codes as the location permission API:

| Code | Meaning |
|------|------|
| `0` | Never asked |
| `1` | Denied, can ask again |
| `3` | Granted |
| `4` | Permanently denied |

On Android < 13 and on iOS, both methods always return `3` (granted).

### Recommended Flow

```dart
// Before starting a foreground service with notification:
if (Platform.isAndroid) {
  final status = await tl.Tracelet.getNotificationPermissionStatus();
  if (status != 3) {
    // Show YOUR rationale dialog first, then:
    final result = await tl.Tracelet.requestNotificationPermission();
    if (result == 4) {
      // Permanently denied — show dialog with "Open Settings" button
      await tl.Tracelet.openAppSettings();
    }
  }
}
```

### Notification Rationale Dialog (Example)

```dart
Future<bool> _showNotificationRationale(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.notifications_active,
          color: Colors.deepOrange, size: 48),
      title: const Text('Enable Notifications'),
      content: const Text(
        'This app uses a persistent notification to keep background '
        'tracking alive on Android.\n\n'
        'Without notification permission, the foreground service '
        'still runs but the notification will be hidden.\n\n'
        'Allow notifications for the most reliable tracking.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Skip'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.notifications),
          label: const Text('Allow Notifications'),
        ),
      ],
    ),
  );
  return result ?? false;
}
```

---

## Motion Permission

Motion/activity recognition permission is required for automatic motion
detection (stationary ↔ moving transitions) **only when using full activity
recognition mode** (the default).

| Platform | Permission | Required Since |
|----------|-----------|----------------|
| Android | `ACTIVITY_RECOGNITION` | API 29 (Android 10) |
| iOS | Motion & Fitness | Always (auto-prompted by OS) |

On Android < 10, both methods return `3` (granted — no runtime permission needed).

### Opting Out of Motion Permission

If you don't want to prompt users for physical activity permission, set
`disableMotionActivityUpdates: true` in `MotionConfig`:

```dart
final config = Config(
  motion: MotionConfig(
    disableMotionActivityUpdates: true,
    isMoving: true, // start in moving mode
  ),
);
```

When disabled, the plugin automatically falls back to **accelerometer-only
motion detection** — a permission-free mode that uses raw hardware sensors
(accelerometer + significant-motion trigger on Android, raw accelerometer on
iOS) to detect stationary↔moving transitions.

| Feature | Full Mode (default) | Accelerometer-Only Mode |
|---------|-------------------|----------------------|
| Permission needed | Yes (`ACTIVITY_RECOGNITION` / Motion & Fitness) | **None** |
| Activity classification | walking, running, driving, cycling | Not available |
| `onActivityChange` events | Yes | No |
| Stop detection | Via Activity Transition API | Via sustained accelerometer stillness |
| Move detection | Via Activity Transition API | Via shake / significant-motion sensor |
| Battery impact | Best (hardware co-processor) | Good (slightly higher than full mode) |

When `disableMotionActivityUpdates` is `true`, both `getMotionPermissionStatus()`
and `requestMotionPermission()` return `3` (granted) immediately without
triggering any OS dialog.

> **Removing the permission entirely:** On Android, you can also remove
> `ACTIVITY_RECOGNITION` from the merged manifest using `tools:node="remove"`.
> Tracelet catches the `SecurityException` and falls back to accelerometer-only
> mode automatically. See
> [Removing Permissions](PLAY-STORE-DECLARATION.md#removing-other-optional-permissions)
> for all removable permissions.

### Recommended Flow (Full Mode)

```dart
final motionStatus = await tl.Tracelet.getMotionPermissionStatus();
if (motionStatus != 3) {
  // Show rationale dialog, then:
  final result = await tl.Tracelet.requestMotionPermission();
  if (result == 4) {
    // Permanently denied — motion detection won't work automatically
    // Device will still track location, but won't auto-detect movement
    await tl.Tracelet.openAppSettings();
  }
}
```
