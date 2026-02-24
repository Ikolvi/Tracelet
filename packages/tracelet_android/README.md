# tracelet_android

Android implementation of the [Tracelet](https://pub.dev/packages/tracelet) background geolocation plugin.

This package uses Kotlin and native Android APIs (FusedLocationProvider, Room, WorkManager, Geofencing API) to provide production-grade background location tracking.

## Usage

**You should not depend on this package directly.** Instead, depend on [`tracelet`](https://pub.dev/packages/tracelet) which automatically includes this package on Android builds.

```yaml
dependencies:
  tracelet: ^0.5.0
```

For Android-specific setup (permissions, Gradle configuration), see the [Android Setup Guide](https://github.com/Ikolvi/Tracelet/blob/main/help/INSTALL-ANDROID.md).

## Related Packages

| Package | Description |
|---|---|
| [`tracelet`](https://pub.dev/packages/tracelet) | App-facing Dart API — the only package you depend on |
| [`tracelet_platform_interface`](https://pub.dev/packages/tracelet_platform_interface) | Abstract platform interface |
| [`tracelet_ios`](https://pub.dev/packages/tracelet_ios) | iOS implementation |
| [`tracelet_web`](https://pub.dev/packages/tracelet_web) | Web implementation |

## More Information

- [GitHub Repository](https://github.com/Ikolvi/Tracelet)
- [Documentation](https://github.com/Ikolvi/Tracelet/tree/main/help)
- [Issue Tracker](https://github.com/Ikolvi/Tracelet/issues)

