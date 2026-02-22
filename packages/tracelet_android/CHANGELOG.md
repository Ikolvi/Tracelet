## 0.2.2

* Fix `ConfigManager.setConfig()` — flatten nested section sub-maps (`geo`, `app`, `http`, etc.) sent by Dart before processing. Fixes foreground service notification config (title, text, channel, priority) and all other sub-config values being silently ignored.

## 0.2.1

* Version bump for coordinated release.

## 0.2.0

* Add SPDX `license: Apache-2.0` identifier for pub.dev scoring.

## 0.1.0

* Initial release.
* FusedLocationProvider-based location tracking.
* Foreground service with configurable notification.
* Activity recognition via Google Play Services.
* SQLite persistence with Room.
* HTTP auto-sync with OkHttp.
* Geofencing with platform GeofencingClient.
* Headless Dart isolate execution.
* Boot-completed receiver for start-on-boot.
* WorkManager-based scheduling.
