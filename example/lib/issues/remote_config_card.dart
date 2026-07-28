import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;

/// Remote Config — verifies the native background fetch of `remoteConfigUrl`.
///
/// Before 3.6.2 the iOS and Android SDKs recognized `remoteConfigUrl` in the
/// config but never actually fetched it — the native side just fell back to the
/// local config (an explicit `// TODO: Port remote config fetch` on both sides).
/// This card exercises the real implementation (both sides carried an explicit
/// port-the-fetch stub before). On `ready()` each platform now
///
///   1. applies the last-good **cached** remote config synchronously, so a
///      restart resumes on the freshest known settings instantly and offline;
///   2. fetches a fresh copy from the HTTPS endpoint in the background and
///      applies it at runtime via `setConfig()` (restarting the tracking
///      pipeline if a tracking-relevant key changed);
///   3. re-fetches on the `remoteConfigRefreshInterval` (minutes) cadence.
///
/// The endpoint returns a JSON config map — flat, or the nested
/// `{geo:{}, app:{}, http:{}, ...}` shape `Config.toMap()` produces. Only HTTPS
/// URLs are honored (non-HTTPS is rejected and logged).
///
/// Verification: the card fetches the same URL from Dart to show exactly what
/// the server returns, then calls `ready()` with it. Watch the device logs for
/// a `remote config: fetched N key(s) from …` line — that confirms the native
/// side pulled and applied the override. Relaunch with the network off to see
/// the cached copy applied instantly.
class RemoteConfigCard extends StatefulWidget {
  const RemoteConfigCard({super.key});

  @override
  State<RemoteConfigCard> createState() => _RemoteConfigCardState();
}

class _RemoteConfigCardState extends State<RemoteConfigCard> {
  /// A public, config-shaped JSON fixture served over HTTPS (a GitHub gist,
  /// mirroring `example/assets/remote_config_sample.json`). Editable below.
  static const String _defaultUrl =
      'https://gist.githubusercontent.com/GalacticTitan/'
      '8500881a62f429d00f4b10d4cf7fe55a/raw/remote_config_sample.json';

  final TextEditingController _urlController = TextEditingController(
    text: _defaultUrl,
  );

  String _status = 'Idle';
  bool _running = false;

  void _set(String s) {
    if (mounted) setState(() => _status = s);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  /// GET the URL from Dart so the tester can see the exact payload the native
  /// side will fetch + apply. Returns a short human-readable summary.
  Future<String> _previewRemote(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        return 'HTTP ${response.statusCode}';
      }
      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return const JsonEncoder.withIndent('  ').convert(decoded);
      }
      return 'Not a JSON object: $body';
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _test() async {
    if (_running) return;
    setState(() => _running = true);

    final url = _urlController.text.trim();
    try {
      if (!url.startsWith('https://')) {
        _set('❌ URL must be HTTPS — the native SDK rejects any other scheme.');
        return;
      }

      _set('Previewing remote config from:\n$url');
      String preview;
      try {
        preview = await _previewRemote(url);
      } catch (e) {
        preview = '(Dart preview failed: $e)';
      }
      _set('Server returned:\n$preview\n\nStopping any existing tracking...');
      await Tracelet.stop();

      _set(
        'Server returned:\n$preview\n\n'
        'Calling ready() with remoteConfigUrl set (refresh every 15 min)...',
      );
      await Tracelet.ready(
        Config.balanced().copyWith(
          app: AppConfig(
            remoteConfigUrl: url,
            remoteConfigTimeout: 15000,
            // Minutes. The native floor is 15 min; 15 keeps the periodic
            // refresh timer armed so you can watch repeated fetches in the log.
            remoteConfigRefreshInterval: 15,
          ),
        ),
      );
      await Tracelet.start();

      _set(
        'Server returned:\n$preview\n\n'
        'ready()/start() done. The native SDK is now fetching this config in '
        'the background and applying it via setConfig().\n\n'
        'Waiting ~5s for the background fetch...',
      );
      await Future<void>.delayed(const Duration(seconds: 5));

      _set(
        '✅ Flow exercised.\n\n'
        'Server payload applied:\n$preview\n\n'
        'Confirm in the device logs (adb logcat on Android, Xcode console on '
        'iOS) a line like:\n'
        '  "remote config: fetched N key(s) from $url"\n\n'
        'That line proves the native side pulled the override and applied it '
        'at runtime — the pre-3.6.2 stub only ever used the local config. '
        'The response is cached, so a relaunch with the network OFF applies '
        'these values instantly before any fetch.',
      );
    } catch (e) {
      _set('❌ ERROR: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Remote Config: native background fetch of remoteConfigUrl',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Fetches a JSON config map from an HTTPS endpoint and applies it '
              'over the local config on ready(), refreshing periodically in the '
              'background. Cached to disk so a restart applies it instantly and '
              'offline. (Pre-3.6.2 this was a stub that always used the local '
              'config.)',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Remote config URL (HTTPS)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              maxLines: 2,
              minLines: 1,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Text(
                _status,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _running ? null : _test,
              icon: const Icon(Icons.cloud_download),
              label: const Text('Fetch & Apply'),
            ),
          ],
        ),
      ),
    );
  }
}
