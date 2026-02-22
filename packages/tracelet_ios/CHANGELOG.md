## 0.2.4

* Fix LICENSE file format for proper SPDX detection on pub.dev.

## 0.2.3

* Fix `ConfigManager.setConfig()` — flatten nested section sub-maps (`geo`, `app`, `http`, etc.) sent by Dart before processing. Fixes all user config values being silently ignored in favor of defaults.

## 0.2.2

* Fix duplicate keys in `ConfigManager.defaultConfig()` dictionary literal causing runtime crash.

## 0.2.1

* Version bump for coordinated release.

## 0.2.0

* Add Swift Package Manager support.
* Fix podspec homepage URL.
* Fix podspec source_files and resource_bundles paths for SPM layout.
* Add SPDX `license: Apache-2.0` identifier for pub.dev scoring.

## 0.1.0

* Initial release.
* CLLocationManager-based location tracking.
* CoreMotion activity recognition.
* SQLite3 persistence.
* HTTP auto-sync with URLSession.
* CLCircularRegion geofencing.
* Headless FlutterEngine execution.
* BGTaskScheduler integration.
* Significant-change monitoring support.
