import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #446 — iOS `EXC_BAD_ACCESS` in `ConfigManager` getters.
///
/// The motion sampler reads the config on a background queue while
/// `setConfig()` mutates and serialises the same dictionary on main. The
/// reporter hit it refreshing a Live Activity through `setConfig()` during a
/// moving session.
///
/// **What this card can show**: it reproduces that load — a moving session
/// with the sampler running and 200 back-to-back `setConfig()` calls — and
/// reports whether the app survived. A race is probabilistic, so surviving one
/// run is evidence, not proof; the deterministic check is the
/// `ConfigManagerConcurrencyTests` unit test under ThreadSanitizer.
class Issue446Card extends StatefulWidget {
  const Issue446Card({super.key});

  @override
  State<Issue446Card> createState() => _Issue446CardState();
}

class _Issue446CardState extends State<Issue446Card>
    with IssueCardRun<Issue446Card> {
  @override
  IssueRunner? get cardRunner => _run;

  Future<void> _run() async {
    if (!Platform.isIOS) {
      setStatus('ℹ️ iOS only — Android ConfigManager is unaffected.');
      return;
    }
    setRunning(running: true);
    try {
      await Tracelet.requestLocationAuthorization();
      await Tracelet.ready(const Config(http: HttpConfig(autoSync: false)));
      await Tracelet.start();
      await Tracelet.changePace(true);
      setStatus('⏳ 200 setConfig() calls while moving…');
      for (var i = 0; i < 200; i++) {
        await Tracelet.setConfig(
          Config(app: AppConfig(heartbeatInterval: 60 + (i % 5))),
        );
      }
      setStatus(
        '✅ Survived 200 setConfig() calls during a moving session.\n\n'
        'Before the fix this load could crash with EXC_BAD_ACCESS in a '
        'ConfigManager getter. One clean run is evidence, not proof.',
      );
    } catch (e) {
      setStatus('❌ FAILED: $e');
    } finally {
      await Tracelet.stop();
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'crash EXC_BAD_ACCESS ConfigManager setConfig race live activity '
          'motion sampler thread 446',
      title: '#446: iOS ConfigManager race',
      description:
          'setConfig() during a moving session could crash in a ConfigManager '
          'getter. Runs 200 setConfig() calls with the motion sampler active.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
