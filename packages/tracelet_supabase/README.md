<p align="center">
  <img src="https://raw.githubusercontent.com/Ikolvi/Tracelet/main/assets/logo_anim.webp" alt="Tracelet" width="400"/>
</p>

# Tracelet Supabase Adapter

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Pub Package](https://img.shields.io/pub/v/tracelet_supabase.svg)](https://pub.dev/packages/tracelet_supabase)
[![CI](https://github.com/Ikolvi/Tracelet/actions/workflows/main.yaml/badge.svg)](https://github.com/Ikolvi/Tracelet/actions)
[![Coverage](https://img.shields.io/codecov/c/github/Ikolvi/Tracelet?flag=tracelet_supabase)](https://codecov.io/gh/Ikolvi/Tracelet)

> **The official Supabase adapter for Tracelet.**

<p align="center">
  <a href="https://tracelet.ikolvi.com/en?copyPrompt=1&utm_source=pubdev&utm_medium=readme&utm_campaign=copy_prompt&utm_content=tracelet_supabase">
    <img src="https://img.shields.io/badge/%E2%9C%A8%20Copy%20AI%20Setup%20Prompt-%E2%96%B6%20click%20to%20copy-0F9D58?style=for-the-badge&labelColor=0B7A43" alt="Copy AI Setup Prompt" height="42"/>
  </a>
</p>

<p align="center">
  <sub><b>⚡ Set up Tracelet with AI.</b> Clicking the badge opens Tracelet and copies a ready-made prompt — paste it into your AI coding assistant (Cursor, Claude Code, Kiro, Copilot Chat…) and it interviews you, then installs and configures Tracelet with the Supabase adapter in your Flutter app.</sub>
</p>

This adapter seamlessly connects Tracelet's battery-efficient native HTTP sync engine directly to your Supabase project. It automatically configures Tracelet to push locations to a Postgres RPC function or Edge Function, and manages background auth token (JWT) refresh natively.

## 🚀 Features

- **Direct Postgres Sync** — Sync locations straight into your Supabase database via an RPC function, bypassing middleman servers.
- **Edge Function Support** — Alternatively, route locations through a Supabase Edge Function for custom processing before insertion.
- **Auto Token Refresh** — Automatically detects 401 Unauthorized errors in the background and refreshes the Supabase Auth session natively, even when the Flutter app is terminated.
- **Batch Syncing** — Fully compatible with Tracelet's robust HTTP batch engine (exponential backoff, offline queues, Wi-Fi-only sync).
- **Enterprise Tested** — 100% test coverage using Mocktail and Dependency Injection.

## 📦 Getting Started

1. Set up Supabase in your Flutter app using `supabase_flutter`.
2. Initialize Tracelet using `TraceletSupabase`.

```dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracelet_supabase/tracelet_supabase.dart';
import 'package:tracelet/tracelet.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Supabase.initialize(
    url: 'https://xyz.supabase.co',
    anonKey: 'your_anon_key',
  );

  // 1. Configure the auto-token refresher
  await TraceletSupabase.configureTokenRefresh(anonKey: 'your_anon_key');

  // 2. Build the HTTP Config pointing to your Supabase RPC
  final httpConfig = TraceletSupabase.buildHttpConfig(
    supabaseUrl: 'https://xyz.supabase.co',
    anonKey: 'your_anon_key',
    rpcFunction: 'insert_tracelet_locations',
  );

  // 3. Start Tracelet
  await Tracelet.ready(Config(
    http: httpConfig,
  ));
}
```

## 🛠 Customizing the Payload (Route Context)

If you want to inject custom data (like a `driver_id` or `trip_id`) into every location point dynamically, use the `Tracelet.setRouteContext()` API in Dart:

```dart
await Tracelet.setRouteContext(RouteContext(
  taskId: 'order_123',
  custom: {'trip_id': 'trip_456'},
));
```

The route context data travels with the location row through the SQLite queue and is included natively in the Supabase REST payload.

## 🤝 Contributing

See the root [CONTRIBUTING.md](../../CONTRIBUTING.md) for guidelines.

## 📄 License

Apache 2.0 — see [LICENSE](../../LICENSE) for details.
