# Changelog

All notable changes to `@ikolvi/tracelet` will be documented in this file.

## 0.1.0-alpha.0

**Initial alpha release** — full API surface with shared native engines.

- **FEAT**: TurboModule-based React Native package using shared TraceletCore engines
- **FEAT**: Full lifecycle API — `ready()`, `start()`, `stop()`, `startGeofences()`, `startPeriodic()`
- **FEAT**: All 15 event streams via `NativeEventEmitter` — location, motion, geofence, HTTP, etc.
- **FEAT**: TypeScript-first API — all types, enums, and interfaces fully typed
- **FEAT**: React hooks — `useLocation()`, `useTraceletState()`, `useGeofences()`
- **FEAT**: Geofencing — add/remove/get circular geofences with enter/exit/dwell events
- **FEAT**: SQLite persistence — `getLocations()`, `getCount()`, `destroyLocations()`, `insertLocation()`
- **FEAT**: HTTP sync — manual `sync()` + auto-sync via config
- **FEAT**: Permission management — location, notification, motion, temporary full accuracy
- **FEAT**: Android headless execution via `HeadlessJsTaskService`
- **FEAT**: Android periodic tracking — WorkManager, exact alarms, foreground service strategies
- **FEAT**: iOS periodic tracking — BGAppRefreshTask + CLServiceSession (iOS 18+)
- **FEAT**: Enterprise features — audit trail, privacy zones (shared from TraceletCore)
- **FEAT**: 45 Jest unit tests covering all API methods and event subscriptions
- **FEAT**: CI/CD — GitHub Actions workflows for lint, typecheck, test, build, publish
- **FEAT**: Example app with location display and event log
