# tracelet_web

Web implementation of the [Tracelet](https://pub.dev/packages/tracelet) background geolocation plugin.

This package uses browser APIs (Geolocation, Permissions, `fetch`, `navigator.onLine`) to provide foreground-only location tracking on the web.

> **Important:** The web platform does **not** support background location tracking.
> The Web Geolocation API only works while the page/tab is in the foreground.

## Usage

**You should not depend on this package directly.** Instead, depend on [`tracelet`](https://pub.dev/packages/tracelet) which automatically includes this package on web builds.

```yaml
dependencies:
  tracelet: ^1.1.0
```

For a full compatibility matrix of what works and what doesn't on web, see the [Web Support Guide](https://github.com/Ikolvi/Tracelet/blob/main/help/WEB-SUPPORT.md).

## Features

| Feature | Status | Notes |
|---|---|---|
| `getCurrentPosition` | Full | Via `navigator.geolocation.getCurrentPosition()` with auto-fallback |
| `start` / `watchPosition` | Partial | Foreground only. No background tab tracking. |
| `stop` / `stopWatchPosition` | Full | Via `navigator.geolocation.clearWatch()` |
| Geofencing | Emulated | Distance-based enter/exit/dwell computed in Dart |
| Persistence | In-memory | Lost on page refresh. Use HTTP sync for durability. |
| HTTP Sync | Full | Via browser `fetch()` API with delta compression support |
| Permissions | Partial | Via `navigator.permissions.query()` |
| Connectivity | Full | Via `navigator.onLine` events |
| Mock Detection | Passthrough | `Location.isMock` always `false` — browser API has no spoof detection |
| OEM Compatibility | Stub | `isAggressiveOem: false` — no OEM power management on web |
| Headless / Background | No | Not possible on web |
| System Settings | No | Cannot open OS settings from browser |

## Related Packages

| Package | Description |
|---|---|
| [`tracelet`](https://pub.dev/packages/tracelet) | App-facing Dart API — the only package you depend on |
| [`tracelet_platform_interface`](https://pub.dev/packages/tracelet_platform_interface) | Abstract platform interface |
| [`tracelet_android`](https://pub.dev/packages/tracelet_android) | Android implementation |
| [`tracelet_ios`](https://pub.dev/packages/tracelet_ios) | iOS implementation |

## More Information

- [GitHub Repository](https://github.com/Ikolvi/Tracelet)
- [Web Support Guide](https://github.com/Ikolvi/Tracelet/blob/main/help/WEB-SUPPORT.md)
- [Documentation](https://github.com/Ikolvi/Tracelet/tree/main/help)
- [Issue Tracker](https://github.com/Ikolvi/Tracelet/issues)
