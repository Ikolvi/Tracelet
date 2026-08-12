/// Helpers for cards that need a *reachable* endpoint rather than a refused one.
///
/// Most issue cards can assert everything they need locally. A few cannot: you
/// cannot prove a request was routed to a particular host, or that a *success*
/// path settled its records correctly, without something on the other end
/// answering 200. Those cards run against the example test server
/// (`dart run example/test_server.dart`), paired by scanning its QR code.
library;

import 'package:tracelet/tracelet.dart';

/// The sync URL the app was paired with, or `null` if no QR has been scanned.
///
/// Cards treat `null` as "run the offline half instead", never as a failure —
/// an unpaired app is an unconfigured card, not a broken build.
String? scannedSyncUrl() {
  final url = Tracelet.activeConfig.http.url;
  if (url == null || url.isEmpty) return null;
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
