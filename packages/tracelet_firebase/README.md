<p align="center">
  <img src="https://raw.githubusercontent.com/Ikolvi/Tracelet/main/assets/logo_anim.webp" alt="Tracelet" width="400"/>
</p>

# Tracelet Firebase Adapter

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Pub Package](https://img.shields.io/pub/v/tracelet_firebase.svg)](https://pub.dev/packages/tracelet_firebase)
[![CI](https://github.com/Ikolvi/Tracelet/actions/workflows/main.yaml/badge.svg)](https://github.com/Ikolvi/Tracelet/actions)
[![Coverage](https://img.shields.io/codecov/c/github/Ikolvi/Tracelet?flag=tracelet_firebase)](https://codecov.io/gh/Ikolvi/Tracelet)

> **The official Firebase Realtime Database (RTDB) adapter for Tracelet.**

<p align="center">
  <a href="https://tracelet.ikolvi.com/copy-prompt?utm_source=pubdev&utm_medium=readme&utm_campaign=copy_prompt&utm_content=tracelet_firebase">
    <img src="https://img.shields.io/badge/%E2%9C%A8%20Copy%20AI%20Setup%20Prompt-%E2%96%B6%20click%20to%20copy-0F9D58?style=for-the-badge&labelColor=0B7A43" alt="Copy AI Setup Prompt" height="42"/>
  </a>
</p>

<p align="center">
  <sub><b>⚡ Set up Tracelet with AI.</b> Clicking the badge opens Tracelet and copies a ready-made prompt — paste it into your AI coding assistant (Cursor, Claude Code, Kiro, Copilot Chat…) and it interviews you, then installs and configures Tracelet with the Firebase adapter in your Flutter app.</sub>
</p>

This adapter seamlessly connects Tracelet's battery-efficient native HTTP sync engine directly to the Firebase Realtime Database (RTDB) REST API. By pushing locations natively to the RTDB, you achieve 100% serverless, zero-cost background location tracking without the need to deploy Cloud Functions.

## 🚀 Features

- **Zero Cloud Functions** — Syncs natively from the device to RTDB via Firebase's REST API.
- **Auto Token Refresh** — Automatically detects 401 errors in the background and refreshes the Firebase Auth ID token natively, even when the Flutter app is terminated.
- **Batch Syncing** — fully compatible with Tracelet's robust HTTP batch engine, including exponential backoff and offline queues.
- **Enterprise Tested** — 100% test coverage using Mocktail and Dependency Injection.

## 📦 Getting Started

1. Set up Firebase in your Flutter app using `firebase_core` and `firebase_auth`.
2. Initialize Tracelet using `TraceletFirebase`.

```dart
import 'package:tracelet_firebase/tracelet_firebase.dart';
import 'package:firebase_auth/firebase_auth.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // 1. Configure the auto-token refresher
  await TraceletFirebase.configureTokenRefresh();

  // 2. Build the HTTP Config pointing to your RTDB
  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    final httpConfig = await TraceletFirebase.buildHttpConfig(
      databaseUrl: 'https://your-project-default-rtdb.firebaseio.com',
      path: 'locations/${user.uid}', // Secure this path in your RTDB rules
    );

    // 3. Start Tracelet
    await Tracelet.ready(Config(
      http: httpConfig,
    ));
  }
}
```

## 🛠 Customizing the Payload

If you want to inject custom data (like an `order_id` or `trip_id`) into every location point dynamically, use the `Tracelet.setRouteContext()` API in Dart:

```dart
await Tracelet.setRouteContext(RouteContext(
  taskId: 'order_123',
  custom: {'trip_id': 'trip_456'},
));
```

The route context data travels with the location row through the SQLite queue and is included natively in the Firebase RTDB payload.

## 🔒 Security Rules

Secure your RTDB to only allow authenticated users to write to their own location path:

```json
{
  "rules": {
    "locations": {
      "$uid": {
        ".read": "auth != null && auth.uid === $uid",
        ".write": "auth != null && auth.uid === $uid"
      }
    }
  }
}
```

## 🤝 Contributing

See the root [CONTRIBUTING.md](../../CONTRIBUTING.md) for guidelines.

## 📄 License

Apache 2.0 — see [LICENSE](../../LICENSE) for details.
