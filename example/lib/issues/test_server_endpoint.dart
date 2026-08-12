/// Helpers for cards that need a *reachable* endpoint rather than a refused one.
///
/// Most issue cards can assert everything they need locally. A few cannot: you
/// cannot prove a request was routed to a particular host, or that a *success*
/// path settled its records correctly, without something on the other end
/// answering 200. Those cards run against the example test server
/// (`dart run example/test_server.dart`), paired by scanning its QR code.
library;

import 'package:tracelet/tracelet.dart';

/// Host:port used by cards that need a request to *fail*.
///
/// Port 9 (discard) on loopback refuses immediately rather than hanging until a
/// timeout, which keeps a card fast and its failure unambiguous.
const cardDeadHost = '127.0.0.1:9';

/// A URL on [cardDeadHost] with the given [path], for cards asserting failure.
String deadUrl(String path) => 'http://$cardDeadHost/$path';

/// The sync URL the app was paired with, or `null` if there isn't a usable one.
///
/// Cards treat `null` as "run the offline half instead", never as a failure —
/// an unpaired app is an unconfigured card, not a broken build.
///
/// **Read this before the card calls `ready()`.** It reports the *active*
/// config, and a card that reconfigures the SDK first will read back its own
/// URL rather than the paired one.
///
/// Sentinel URLs are filtered out. Config persists across runs, so a card that
/// points the SDK at [cardDeadHost] leaves that behind as the active URL — and
/// the next run, or the next card, would otherwise treat a deliberately dead
/// endpoint as a live server and quietly assert nothing.
String? scannedSyncUrl() {
  final url = Tracelet.activeConfig.http.url;
  if (url == null || url.isEmpty) return null;
  if (url.contains(cardDeadHost)) return null;
  return url;
}

/// Rewrites the last path segment of [url] to [segment].
///
/// The QR pairs the app with `.../locations`; a card that needs a second
/// endpoint on the same server derives it from that rather than asking the user
/// to type a host twice — the point is to compare where two requests land, and
/// two hand-entered URLs are one typo away from proving nothing.
///
/// Returns `null` if [url] cannot be parsed.
String? siblingEndpoint(String url, String segment) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final segments = List<String>.from(uri.pathSegments);
  if (segments.isEmpty) {
    segments.add(segment);
  } else {
    segments[segments.length - 1] = segment;
  }
  return uri.replace(pathSegments: segments).toString();
}
