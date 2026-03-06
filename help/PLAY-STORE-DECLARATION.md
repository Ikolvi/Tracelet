# Google Play Store — Background Location Declaration

Starting **2021**, Google Play requires apps that use `ACCESS_BACKGROUND_LOCATION`
to submit a **location declaration** with a short video demonstrating the feature.
If your app uses Tracelet for background tracking, you **must** complete this
declaration or your app update will be rejected.

---

## Why Is This Required?

Tracelet's Android plugin declares `ACCESS_BACKGROUND_LOCATION` in its
`AndroidManifest.xml`. This permission is required on **Android 10+** (API 29)
for the OS to deliver location updates to a foreground service when the app is
not visible.

Without this permission, `ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION`
only work while the app is in the foreground. Since background geolocation is
Tracelet's core purpose, this permission cannot be removed.

When the Play Console detects this permission in your merged manifest, it
requires a declaration before you can publish.

---

## Step-by-Step: Submitting the Declaration

### 1. Open the Play Console

Go to **[Google Play Console](https://play.google.com/console)** → select your
app → **App content** (left sidebar) → **Sensitive app permissions** →
**Location permissions**.

> On newer Play Console versions, this may be under **Policy and programs** →
> **App content** → **Permissions declaration**.

### 2. Select Your Use Case

Google will ask you to pick from predefined categories. For a location-tracking
app using Tracelet, typical approved use cases include:

| Use Case | Example |
|---|---|
| **Navigation / route tracking** | Fleet management, delivery tracking, fitness routes |
| **User-initiated location sharing** | Family safety, live location with friends |
| **Asset tracking / logistics** | Vehicle GPS, field worker management |
| **Fitness / health** | Run/bike/hike recording with GPS traces |

Select the category that best matches **your app's purpose**. If none match
exactly, choose the closest one and explain in the text field.

### 3. Explain Why Background Access Is Needed

Write a clear, concise explanation. Google reviewers must understand:

- **What** the feature is (e.g., "continuous route recording")
- **Why** it must run in the background (e.g., "users lock the screen during runs")
- **How** the user benefits (e.g., "accurate route displayed on a map afterward")

#### Template (customize for your app):

> **Feature:** [Your App] records the user's GPS route during [activity].
>
> **Why background access is needed:** Users start a tracking session, then lock
> their phone or switch to other apps while [driving/running/cycling/working].
> The app must continue receiving location updates in the background to record an
> accurate route. A persistent foreground notification informs the user that
> tracking is active.
>
> **User benefit:** After the session, users can view their complete route on a
> map, review distance and duration, and [sync/share/export] their data.

### 4. Record the Video

Google requires a **short video** (30–120 seconds recommended) that demonstrates:

1. **The permission flow** — show the app requesting location permission,
   including the "Allow all the time" dialog (Android 11+ shows a separate
   background permission screen).
2. **The feature in action** — show the user starting background tracking, then
   switching away from the app (or locking the screen), and the foreground
   notification being visible.
3. **The user-visible result** — show the tracked route, trip history, or
   whatever the user sees after tracking completes.

#### Video Recording Tips

- Use **Android Studio's built-in screen recorder** or `adb shell screenrecord`
  on a physical device.
- Record on a **real device** — emulator recordings are often rejected.
- Target **Android 11+** (API 30+) to show the separate background permission
  dialog.
- Keep the video **under 2 minutes** — shorter is better. Google reviewers watch
  many of these.
- **No narration required** — clear on-screen actions are sufficient, but you
  may add text annotations.
- Upload to **YouTube** (unlisted is fine) or provide a direct video link.

#### Recording with adb

```bash
# Connect device via USB, then:
adb shell screenrecord /sdcard/bg_location_demo.mp4

# Press Ctrl+C to stop recording, then pull the file:
adb pull /sdcard/bg_location_demo.mp4
```

#### Recommended Video Script

| Timestamp | Action |
|---|---|
| 0:00–0:05 | Open the app. Show the main screen. |
| 0:05–0:15 | Tap "Start Tracking" (or equivalent). Show the location permission dialog → grant "While using the app". |
| 0:15–0:25 | Show the background permission dialog → grant "Allow all the time". |
| 0:25–0:35 | Show the foreground notification appearing in the notification shade. |
| 0:35–0:50 | Press Home / switch to another app. Show the notification still present. |
| 0:50–1:10 | Return to the app. Show the recorded route / tracked data. |
| 1:10–1:20 | Stop tracking. Show the final result (map, summary, etc.). |

### 5. Submit and Wait for Review

After filling in the declaration and attaching the video link:

1. Click **Save** / **Submit**.
2. Google typically reviews within **1–3 business days**.
3. If approved, you can proceed with publishing your app update.
4. If rejected, Google will provide feedback — adjust your declaration
   accordingly and resubmit.

---

## Common Rejection Reasons and Fixes

| Rejection Reason | Fix |
|---|---|
| "Video does not show background location usage" | Make sure the video shows the app working **after** leaving the foreground (lock screen or press Home). |
| "The declared feature does not require background location" | Emphasize that users cannot keep the app open during the activity (driving, running, etc.). |
| "Permission dialog not shown in video" | Record the full flow from fresh install — clear app data first with `adb shell pm clear com.your.package`. |
| "Video shows emulator, not a real device" | Re-record on a physical device. |
| "Foreground notification not visible" | Ensure `ForegroundServiceConfig.enabled` is `true` and notification permission is granted (Android 13+). |

---

## If Your App Does NOT Need Background Tracking

If your app only uses Tracelet for **foreground-only** features (e.g., a
one-shot location fetch, check-in button, or map centering), you can **remove**
the background location permission from your final APK.

Add this to your **app-level** `AndroidManifest.xml`
(`android/app/src/main/AndroidManifest.xml`):

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <!-- Remove background location — not needed for foreground-only use -->
    <uses-permission
        android:name="android.permission.ACCESS_BACKGROUND_LOCATION"
        tools:node="remove" />
</manifest>
```

This uses Android's **manifest merger** `tools:node="remove"` directive to strip
the permission from the final merged manifest. The Play Store will no longer
require a background location declaration.

> **Warning:** With this permission removed, `Tracelet.requestPermission()` will
> never escalate beyond `whenInUse` (status code `2`). Background tracking via
> foreground service will **not receive location updates** on Android 10+.
> Only use this if you are certain you do not need background tracking.

---

## Verifying Your Merged Manifest

After building your app, verify which permissions are in the final APK:

```bash
# Check the merged manifest
cat android/app/build/intermediates/merged_manifests/release/AndroidManifest.xml \
  | grep "BACKGROUND_LOCATION"

# Or inspect the APK directly
aapt dump permissions build/app/outputs/flutter-apk/app-release.apk
```

If `ACCESS_BACKGROUND_LOCATION` appears, the declaration is required.

---

## Related Guides

- [Permissions Guide](PERMISSIONS.md) — Runtime permission flow and API
- [Background Tracking](BACKGROUND-TRACKING.md) — Foreground service configuration
- [Android Setup](INSTALL-ANDROID.md) — Full Android installation guide
- [OEM Compatibility](OEM-COMPATIBILITY.md) — Battery optimization on OEM skins
