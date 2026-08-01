import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression guard for #286 — per-engine `TraceletSyncSink` accumulation.
///
/// The bug: both native plugins built a **new** `TraceletSyncSink` for every
/// `FlutterEngine` that attached, and neither ever detached one. Hosts that
/// spawn secondary engines (`workmanager` creates one per background task, plus
/// headless engines and engine groups) accumulated sinks for the life of the
/// process. Every sink owns its own concurrency guard — a `CoroutineScope` +
/// `Mutex` on Android, a `SyncCoordinator` actor on iOS — so those guards
/// stopped serializing anything: one persisted location fanned out into N
/// blocking auto-syncs, each pinning threads, which showed up in production as
/// `OutOfMemoryError: pthread_create failed`, heap exhaustion, duplicate points
/// server-side and racing `clearLocationsUpTo` calls.
///
/// The sinks and their scopes are native internals with no Dart-visible API, and
/// reproducing the accumulation needs real secondary engines (the example app's
/// #286 card does that on-device). So this test guards the **source invariants**
/// that make the accumulation impossible, on every platform, in CI:
///
/// 1. the sink is constructed in exactly one place — the process-wide accessor —
///    and never inside the per-engine attach/registration entry point;
/// 2. a static/companion holder keeps that single instance;
/// 3. iOS no longer registers the same sink twice per engine;
/// 4. both SDKs can actually detach a sink (dedupe on register + unregister),
///    so a superseded provider cannot stay subscribed.
void main() {
  final kotlinPlugin = File(
    'android/src/main/kotlin/com/ikolvi/tracelet_sync/TraceletSyncPlugin.kt',
  ).readAsStringSync();
  final swiftPlugin = File(
    'ios/tracelet_sync/Sources/tracelet_sync/TraceletSyncPlugin.swift',
  ).readAsStringSync();
  final swiftLocationEngine = File(
    '../../sdk/ios/Sources/TraceletSDK/location/LocationEngine.swift',
  ).readAsStringSync();
  final swiftSdk = File(
    '../../sdk/ios/Sources/TraceletSDK/TraceletSdk.swift',
  ).readAsStringSync();
  final kotlinLocationEngine = File(
    '../../sdk/android/tracelet-sdk/src/main/kotlin/com/ikolvi/tracelet/sdk/'
    'location/LocationEngine.kt',
  ).readAsStringSync();

  /// Returns the text from [declaration] up to the first [closer], i.e. the body
  /// of a member declared at the indentation that [closer] closes.
  String bodyOf(String source, String declaration, String closer) {
    final start = source.indexOf(declaration);
    expect(start, greaterThanOrEqualTo(0), reason: 'missing: $declaration');
    final end = source.indexOf(closer, start);
    expect(end, greaterThan(start), reason: 'unterminated: $declaration');
    return source.substring(start, end);
  }

  group('#286 Android: the sync sink is process-wide', () {
    test('constructed exactly once, inside the shared accessor', () {
      final constructions = RegExp(
        r'TraceletSyncSink\(sdk\)',
      ).allMatches(kotlinPlugin).length;
      expect(
        constructions,
        1,
        reason:
            'A TraceletSyncSink must be built in exactly one place. More than '
            'one construction site means an engine attach can create its own '
            'sink again (#286).',
      );

      final accessor = bodyOf(
        kotlinPlugin,
        'internal fun obtainSharedSink(',
        '\n        }',
      );
      expect(
        accessor,
        contains('TraceletSyncSink(sdk)'),
        reason: 'the single construction must live in obtainSharedSink()',
      );
      expect(
        accessor,
        contains('synchronized('),
        reason:
            'engines attach on their own platform threads, so creation must be '
            'guarded',
      );
    });

    test('a @Volatile companion holder keeps the single instance', () {
      expect(kotlinPlugin, contains('@Volatile'));
      expect(
        kotlinPlugin,
        contains('private var sharedSink: TraceletSyncSink? = null'),
        reason:
            'the sink must be held statically (companion object), not in a '
            'per-plugin-instance field — one plugin instance exists per engine',
      );
    });

    test('onAttachedToEngine reuses the shared sink', () {
      final attach = bodyOf(
        kotlinPlugin,
        'override fun onAttachedToEngine(',
        '\n    }',
      );
      expect(
        attach,
        isNot(contains('TraceletSyncSink(')),
        reason: 'onAttachedToEngine must not construct a sink (#286)',
      );
      expect(attach, contains('obtainSharedSink('));
      expect(
        attach,
        contains('registerSyncProvider('),
        reason:
            'the shared sink still has to be (idempotently) registered with the '
            'SDK on every attach, so a newly built LocationEngine gets it',
      );
    });
  });

  group('#286 iOS: the sync sink is process-wide', () {
    test('constructed exactly once, inside the shared accessor', () {
      final constructions = RegExp(
        r'TraceletSyncSink\(\)',
      ).allMatches(swiftPlugin).length;
      expect(
        constructions,
        1,
        reason:
            'register(with:) runs once per registrar, i.e. once per engine — a '
            'construction site outside the shared accessor reintroduces #286.',
      );

      final accessor = bodyOf(
        swiftPlugin,
        'static func obtainSharedSink(',
        '\n  }',
      );
      expect(accessor, contains('TraceletSyncSink()'));
      expect(
        accessor,
        contains('lock()'),
        reason: 'creation must be guarded across engines',
      );
    });

    test('a static holder keeps the single instance', () {
      expect(
        swiftPlugin,
        contains('private static var sharedSink: TraceletSyncSink?'),
      );
    });

    test('register(with:) reuses the sink and registers it only once', () {
      final register = bodyOf(
        swiftPlugin,
        'public static func register(with registrar:',
        '\n  }',
      );
      expect(
        register,
        isNot(contains('TraceletSyncSink()')),
        reason: 'register(with:) must not construct a sink (#286)',
      );
      expect(register, contains('obtainSharedSink()'));
      expect(
        register,
        isNot(contains('locationEngine.registerSink(')),
        reason:
            'registering directly AND assigning syncProvider (whose didSet '
            'registers) added the same sink twice per engine (#286)',
      );
    });

    test('the plugin has a detach hook', () {
      expect(
        swiftPlugin,
        contains('public func detachFromEngine(for'),
        reason:
            'iOS had no teardown hook at all, so nothing could ever be undone '
            'when an engine went away (#286)',
      );
    });
  });

  group('#286 SDKs: a sink can always be detached', () {
    test('iOS LocationEngine dedupes on register and can unregister', () {
      final register = bodyOf(
        swiftLocationEngine,
        'public func registerSink(',
        '\n    }',
      );
      expect(
        register,
        contains('contains(where:'),
        reason:
            'registerSink was a bare append, so the same sink could be added '
            'repeatedly and each entry fanned out another insertLocation (#286)',
      );
      expect(
        swiftLocationEngine,
        contains('public func unregisterSink('),
        reason:
            'iOS had no way to detach a sink, so stale sync providers stayed '
            'subscribed forever (#286)',
      );
    });

    test('iOS syncProvider replacement detaches the previous provider', () {
      final didSet = bodyOf(
        swiftSdk,
        'public var syncProvider: SyncProvider? = nil {',
        '\n    }\n',
      );
      expect(
        didSet,
        contains('unregisterSink('),
        reason:
            'replacing the provider must unsubscribe the old one, as Android '
            'registerSyncProvider() does (#204/#286)',
      );
      expect(didSet, contains('cancelPendingSync()'));
    });

    test('Android LocationEngine keeps its dedupe and unregister', () {
      expect(kotlinLocationEngine, contains('if (!sinks.contains(sink))'));
      expect(kotlinLocationEngine, contains('fun unregisterSink('));
    });
  });
}
