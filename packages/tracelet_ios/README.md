# tracelet_ios

iOS implementation of the [Tracelet](https://pub.dev/packages/tracelet) background geolocation plugin.

This package uses Swift and native Apple frameworks (CoreLocation, CoreMotion, BackgroundTasks, SQLite3) to provide production-grade background location tracking.

## Usage

**You should not depend on this package directly.** Instead, depend on [`tracelet`](https://pub.dev/packages/tracelet) which automatically includes this package on iOS builds.

```yaml
dependencies:
  tracelet: ^0.5.0
```

For iOS-specific setup (Info.plist, capabilities, entitlements), see the [iOS Setup Guide](https://github.com/Ikolvi/Tracelet/blob/main/help/INSTALL-IOS.md).

## Related Packages

| Package | Description |
|---|---|
| [`tracelet`](https://pub.dev/packages/tracelet) | App-facing Dart API — the only package you depend on |
| [`tracelet_platform_interface`](https://pub.dev/packages/tracelet_platform_interface) | Abstract platform interface |
| [`tracelet_android`](https://pub.dev/packages/tracelet_android) | Android implementation |
| [`tracelet_web`](https://pub.dev/packages/tracelet_web) | Web implementation |

## More Information

- [GitHub Repository](https://github.com/Ikolvi/Tracelet)
- [Documentation](https://github.com/Ikolvi/Tracelet/tree/main/help)
- [Issue Tracker](https://github.com/Ikolvi/Tracelet/issues)

