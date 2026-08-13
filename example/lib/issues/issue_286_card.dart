import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Entrypoint for the secondary engines the iOS probe spawns (see
/// `AppDelegate.probeIssue286`). A FlutterEngine must be **running** before
/// plugins may be registered on it — `register(with:)` installs method-call
/// handlers, and doing that on a non-running engine raises
/// `NSInternalInconsistencyException: Setting a message handler before the
/// FlutterEngine has been run.`
///
/// It deliberately does nothing: running `main()` in the probe engines would
/// boot a second copy of the example app. Plugin registration — the thing #286
/// is about — happens natively right after this returns.
@pragma('vm:entry-point')
void issue286ProbeEntrypoint() {}

/// Issue #286 — per-engine `TraceletSyncSink` instances accumulate.
///
/// VERIFICATION ONLY: this card fixes nothing. It reproduces the reporter's
/// environment on the running build and reports what it measures.
///
/// Reported (Android, `tracelet_sync`):
/// `TraceletSyncPlugin.onAttachedToEngine` creates a **new** `TraceletSyncSink`
/// for every `FlutterEngine` that attaches, and `onDetachedFromEngine` only
/// clears the method-call handler — the sink is never cancelled and its
/// `CoroutineScope` / `Mutex` / `SyncManager` stay alive. Any host app that
/// spawns secondary engines therefore accumulates sinks; `workmanager_android`
/// does exactly that per task (`FlutterEngine(applicationContext)` …
/// `engine.destroy()`). The concurrency guards (`syncJob?.isActive`,
/// `syncMutex`) are per sink, so every stale sink that stays subscribed adds
/// another blocking auto-sync per persisted fix — the reported thread/heap OOMs.
///
/// **iOS is affected too, by the same design and with fewer brakes.**
/// `TraceletSyncPlugin.register(with:)` builds a fresh `TraceletSyncSink` on
/// every registrar (so every engine), calls
/// `TraceletSdk.shared.locationEngine.registerSink(sink)` and then assigns
/// `TraceletSdk.shared.syncProvider = sink`, whose `didSet` registers the same
/// sink a *second* time. Each sink owns its own `SyncCoordinator` actor
/// (`isSyncing` / `syncTask` are per instance), so N sinks debounce and sync
/// independently — the same fan-out as Kotlin. What iOS does not have:
/// `registerSyncProvider()`'s replace-and-unregister logic, any
/// `unregisterSink` on `LocationEngine` (its `registerSink` is a bare
/// `sinks.append`, no dedupe), and any `detachFromEngine(for:)` on the sync
/// plugin. `tracelet_ios` guards secondary registrars with a
/// primary/secondary check; `tracelet_sync` has no equivalent. Secondary
/// engines are rarer on iOS, but not absent — `workmanager` creates one per
/// background task there as well.
///
/// What the probe does on each platform (through the `com.tracelet/debug`
/// channel, since sinks are native internals with no Dart-visible API):
/// registers the plugins on N secondary engines, releases those engines, then
/// reports how many **distinct** sink instances the SDK saw, how many are still
/// live/subscribed afterwards, how many sink entries sit on the live
/// `LocationEngine`, and whether the sink is held per engine or in a shared
/// holder.
///
/// Run a **debug** build: release is minified/optimized and the reflective
/// lookups will not resolve. On iOS the probe needs the local-dev Podfile path
/// (`pod 'TraceletSDK'`), otherwise it reports itself as compiled out. Restart
/// the app afterwards — real engines were attached and released.
class Issue286Card extends StatefulWidget {
  const Issue286Card({super.key});

  @override
  State<Issue286Card> createState() => _Issue286CardState();
}

class _Issue286CardState extends State<Issue286Card>
    with IssueCardRun<Issue286Card> {
  static const _debug = MethodChannel('com.tracelet/debug');

  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _test;

  Future<void> _test() async {
    if (running) return;
    setRunning(running: true);
    try {
      _set('Attaching 2 secondary FlutterEngines, then releasing them...');
      final res = await _debug.invokeMapMethod<String, dynamic>(
        'debugIssue286SyncSinkAccumulation',
        {'engines': 2},
      );
      if (res == null) {
        _set('❌ ERROR: debug channel returned null.');
        return;
      }

      final platform = res['platform'] as String? ?? 'unknown';
      final isIos = platform == 'ios';
      final engines = res['enginesSpawned'] as int? ?? 0;
      final baseline = res['baselineSinks'] as int? ?? 0;
      final distinct = res['distinctSinks'] as int? ?? 0;
      final alive = res['aliveAfterDestroy'] as int? ?? 0;
      final inspected = res['scopesInspected'] as int? ?? 0;
      final registeredBefore = res['registeredBefore'] as int? ?? -1;
      final registeredAfter = res['registeredAfter'] as int? ?? -1;
      final registeredBoot = res['registeredBootAfter'] as int? ?? -1;
      final deadProvider = res['providerReplacedByDeadEngine'] == true;
      final instanceField = res['instanceSinkField'] == true;
      final staticHolder = res['staticSinkHolder'] == true;
      final canUnregister = res['canUnregister'] == true;
      final hasDetachHook = res['hasDetachHook'] == true;
      final scopeStates = (res['scopeStates'] as List?)?.cast<String>() ?? [];

      final newSinks = distinct - baseline;
      final aliveLabel = isIos
          ? 'stale sinks still subscribed:'
          : 'abandoned sinks still active: ';

      final facts = StringBuffer()
        ..writeln('platform:                       $platform')
        ..writeln('engines attached then released: $engines')
        ..writeln(
          'distinct sink instances seen:   $distinct '
          '(baseline $baseline → +$newSinks)',
        )
        ..writeln('$aliveLabel  $alive of $inspected inspected')
        ..writeln(
          'sink entries on LocationEngine: $registeredBefore → '
          '$registeredAfter${registeredAfter > 1 ? "  ← fan-out" : ""}',
        );
      if (!isIos) {
        facts.writeln(
          'sinks on boot LocationEngine:   '
          '${registeredBoot < 0 ? "n/a (not tracking natively)" : registeredBoot}',
        );
      }
      facts
        ..writeln(
          'SDK left pointing at a sink from a released engine: '
          '$deadProvider',
        )
        ..writeln('sink can be unregistered again: $canUnregister')
        ..writeln(
          'plugin sink storage: '
          '${staticHolder
              ? "shared holder"
              : instanceField
              ? "per registration/engine"
              : "unknown"}',
        );
      if (isIos) {
        facts.writeln(
          'sync plugin implements detachFromEngine: $hasDetachHook',
        );
      }
      for (final s in scopeStates) {
        facts.writeln('  • $s');
      }

      if (isIos && registeredAfter > engines) {
        facts.writeln(
          '\nNote: iOS registers each sink TWICE per engine — once directly in '
          'register(with:) and once again from the syncProvider didSet — and '
          'LocationEngine.registerSink appends without dedupe. With no '
          'unregisterSink and no detachFromEngine, every one of these entries '
          'stays subscribed for the life of the LocationEngine, and each '
          'distinct sink schedules its own debounced sync.',
        );
      }
      if (!isIos && registeredAfter == 1 && newSinks >= 1) {
        facts.writeln(
          '\nNote: only 1 sink is on the foreground LocationEngine because '
          'registerSyncProvider() unregisters the previous provider when '
          'locationEngine is already assigned. That trims this list, not the '
          'accumulation — the stale sinks above are still alive. The N-way '
          'fan-out in the report needs a stale sink that stayed subscribed: '
          'a secondary engine attaching before initialize() finishes assigning '
          'locationEngine (its heavy setup runs off the calling thread), or '
          "LocationService's own engine, which registerSyncProvider() does not "
          'unregister from.',
        );
      }

      final String verdict;
      if (newSinks >= engines && alive >= 1) {
        verdict =
            '🔴 REPRODUCED — #286 is present in this build ($platform).\n'
            'Every attaching engine created its own TraceletSyncSink '
            '(+$newSinks for $engines engines) and $alive of them are still '
            '${isIos ? "subscribed to the shared LocationEngine" : "running"} '
            'after their engine went away, so nothing tears them down. Each '
            'survivor keeps its own '
            '${isIos ? "SyncCoordinator actor" : "scope/mutex/SyncManager"}, so '
            'the per-sink guards cannot serialize across them: any stale sink '
            'that stays subscribed adds another blocking auto-sync per '
            'persisted fix.';
      } else if (newSinks >= 1 && alive == 0) {
        verdict =
            '🟠 PARTIAL — sinks are still created per engine (+$newSinks), but '
            'the abandoned ones are no longer '
            '${isIos ? "subscribed" : "active"} afterwards, so they are being '
            'torn down. The accumulation itself is not gone.';
      } else if (newSinks == 0 && staticHolder) {
        verdict =
            '🟢 NOT REPRODUCED — the sink looks process-wide (shared holder, no '
            'new instance per engine), which is the first option the issue '
            'suggests.';
      } else if (newSinks == 0) {
        verdict =
            '🟢 NOT REPRODUCED — no additional sink instance appeared after '
            '$engines engine attaches.';
      } else {
        verdict =
            '⚠️ INCONCLUSIVE — mixed signals (+$newSinks new sinks, $alive '
            'still live, $inspected inspected). If the numbers are 0 or -1 you '
            'are probably on a minified release build, where the reflective '
            'lookups fail; re-run a debug build.';
      }

      _set(
        '$verdict\n\n$facts\n'
        'Not verified by this card: the hardcoded 15s timeouts and the '
        '`runBlocking`-inside-`Dispatchers.IO` thread doubling from the issue, '
        'and the duplicate server-side points (that needs real GPS fixes plus a '
        'backend to observe). Restart the app now — real engines were attached '
        'and released.',
      );
    } on PlatformException catch (e) {
      _set('❌ ERROR: ${e.code} — ${e.message}');
    } on MissingPluginException {
      _set(
        '❌ ERROR: no debug handler for this platform build. The probe lives in '
        'the example app (MainActivity.kt / AppDelegate.swift); rebuild the app '
        'so it is compiled in.',
      );
    } catch (e) {
      _set('❌ ERROR: $e');
    } finally {
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'tracelet_sync sync sink per engine flutterengine accumulate leak '
          'onattachedtoengine ondetachedfromengine detachfromengine '
          'registersyncprovider registersink unregistersink synccoordinator '
          'coroutinescope oom pthread_create outofmemoryerror workmanager '
          'headless concurrent autosync duplicate points ios android 286',
      title: '#286: per-engine TraceletSyncSink accumulation (verify only)',
      description:
          'Reported: a new TraceletSyncSink per attaching FlutterEngine that is '
          'never torn down, so WorkManager-style secondary engines accumulate '
          'sinks and one fix fans out into N blocking auto-syncs (thread + heap '
          'OOM). Runs on Android AND iOS — iOS has the same per-registration '
          'sink with no unregisterSink and no detachFromEngine. This card only '
          'VERIFIES: it attaches and releases 2 secondary engines, then reports '
          'how many distinct sinks were created, how many survive, and how many '
          'are registered on the LocationEngine. Debug build; no fix applied.',
      status: status,
      running: running,
      runLabel: 'Verify',
      onRun: _test,
    );
  }
}
