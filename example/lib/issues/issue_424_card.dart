import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #424 — archiving an iOS app ended with "Upload Symbols Failed: The
/// archive did not include a dSYM for the TraceletCore.framework", and crashes
/// inside the Rust core were unsymbolicated.
///
/// The release build discarded its debug info and the packaging never produced
/// a symbol file. `build-ios.sh` now keeps line tables, extracts a dSYM per
/// slice, strips the shipped binary, and attaches the dSYMs to both
/// xcframeworks; it fails the build unless every slice carries a dSYM whose
/// UUIDs match its binary.
///
/// **What this card can prove:** nothing at runtime. A running app cannot see
/// the dSYMs, which live in the archive and never in the installed bundle. The
/// proof is the build's own UUID check and an archive: Product → Archive in
/// Xcode, then confirm Organizer shows no "Upload Symbols Failed" warning for
/// TraceletCore or TraceletSyncFFI. The card prints those steps and claims no
/// pass.
class Issue424Card extends StatefulWidget {
  const Issue424Card({super.key});

  @override
  State<Issue424Card> createState() => _Issue424CardState();
}

class _Issue424CardState extends State<Issue424Card>
    with IssueCardRun<Issue424Card> {
  bool get _isIOS => !kIsWeb && Platform.isIOS;

  @override
  IssueRunner? get cardRunner => _run;

  Future<void> _run() async {
    setRunning(running: true);
    try {
      setStatus(
        'ℹ️ Not verifiable at runtime — dSYMs live in the archive, never in '
        'the installed app.${_isIOS ? '' : ' (And this is an iOS-only issue.)'}'
        '\n\nHow it is verified:\n'
        '1. `sdk/rust-core/build-ios.sh` fails unless every xcframework slice '
        'carries a dSYM whose UUIDs match its binary '
        '("✅ dSYMs present with matching UUIDs.").\n'
        '2. In Xcode: Product → Archive. Organizer must show no "Upload '
        'Symbols Failed" warning for TraceletCore.framework or '
        'TraceletSyncFFI.framework.\n'
        '3. Optional: `dwarfdump --uuid` on the archived '
        'dSYMs/TraceletCore.framework.dSYM matches the framework inside '
        'Products/Applications/<App>.app/Frameworks.\n\n'
        'If your Podfile sets DEBUG_INFORMATION_FORMAT = dwarf for the '
        'Tracelet targets to silence the old warning, remove it.',
      );
    } finally {
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'ios dsym upload symbols failed archive testflight crashlytics '
          'symbolicate xcframework TraceletCore TraceletSyncFFI 424',
      title: '#424: the Rust frameworks ship dSYMs',
      description:
          'Archives warned "Upload Symbols Failed" for TraceletCore and Rust '
          'crashes were unsymbolicated. Verified at build time and by '
          'archiving, not from the running app: Run prints the steps.',
      status: status,
      running: running,
      onRun: _run,
      prepare: false,
    );
  }
}
