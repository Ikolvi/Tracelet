# tracelet_platform_interface

A common platform interface for the [Tracelet](https://pub.dev/packages/tracelet) background geolocation plugin.

This package provides the abstract classes and types that the platform-specific implementations (`tracelet_android`, `tracelet_ios`, `tracelet_web`) implement.

## Usage

**You should not depend on this package directly.** Instead, depend on [`tracelet`](https://pub.dev/packages/tracelet) which automatically includes the correct platform implementation.

This package is only relevant if you are writing a custom platform implementation for Tracelet.

## Related Packages

| Package | Description |
|---|---|
| [`tracelet`](https://pub.dev/packages/tracelet) | App-facing Dart API — the only package you depend on |
| [`tracelet_android`](https://pub.dev/packages/tracelet_android) | Android implementation |
| [`tracelet_ios`](https://pub.dev/packages/tracelet_ios) | iOS implementation |
| [`tracelet_web`](https://pub.dev/packages/tracelet_web) | Web implementation |

## More Information

- [GitHub Repository](https://github.com/Ikolvi/Tracelet)
- [Documentation](https://github.com/Ikolvi/Tracelet/tree/main/help)
- [Issue Tracker](https://github.com/Ikolvi/Tracelet/issues)
