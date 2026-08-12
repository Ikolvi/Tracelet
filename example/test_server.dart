/// Simple HTTP test server for verifying Tracelet's HTTP sync.
///
/// Usage:
///   dart run test_server.dart [port]
///
/// Then configure your example app with:
///   http://YOUR_MAC_IP:8099/locations
///
/// Find your Mac's IP:
///   ipconfig getifaddr en0
///
/// The server logs every incoming request body to the console so you can
/// verify locations are being synced — especially in the killed-app state.
library;

import 'dart:convert';
import 'dart:io';

import 'package:qr/qr.dart';

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? int.tryParse(args.first) ?? 8099 : 8099;

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  final localIp = await _getLocalIp();

  stdout.writeln('╔══════════════════════════════════════════════════════╗');
  stdout.writeln('║  Tracelet Test Server                               ║');
  stdout.writeln('╠══════════════════════════════════════════════════════╣');
  stdout.writeln('║  Listening on: http://$localIp:$port/locations');
  stdout.writeln('║  Use this URL in your Tracelet HttpConfig.          ║');
  stdout.writeln('║  Press Ctrl+C to stop.                              ║');
  stdout.writeln('╚══════════════════════════════════════════════════════╝');
  stdout.writeln();

  final url = 'http://$localIp:$port/locations';

  // The QR code is rendered here, in process. It used to be fetched by shelling
  // out to `curl qrenco.de/<url>`, which had two problems. The obvious one is
  // that it stopped working the moment that third-party service became
  // unreachable. The worse one is that every failure was swallowed — the call
  // was wrapped in `catch (_) {}` and only printed when stdout was non-empty —
  // so a machine with no route to it simply showed no QR code and no reason.
  //
  // Needing the public internet for this was backwards regardless: the URL
  // encodes a LAN address, so the phone and the Mac are already on the same
  // network, and that is the only network the pairing requires.
  try {
    stdout.writeln(_renderQr(url));
    stdout.writeln('^ Scan the QR code above with the Example app ^');
  } catch (e) {
    // Loud, not silent: the URL above is still usable by hand, and a failure
    // here should say so rather than leaving a blank space where a QR was.
    stdout.writeln('⚠️  Could not render the QR code: $e');
    stdout.writeln('    Enter the URL above manually instead: $url');
  }

  stdout.writeln();
  stdout.writeln('Waiting for location sync requests...');
  stdout.writeln();

  var requestCount = 0;

  await for (final request in server) {
    requestCount++;
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    final body = await utf8.decoder.bind(request).join();

    stdout.writeln(
      '── Request #$requestCount [$timestamp] '
      '${request.method} ${request.uri.path} ──',
    );

    if (request.uri.queryParameters.isNotEmpty) {
      stdout.writeln('  Query Params: ${request.uri.queryParameters}');
    }

    stdout.writeln('  Headers:');
    request.headers.forEach((name, values) {
      stdout.writeln('    $name: ${values.join(', ')}');
    });

    if (body.isNotEmpty) {
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;

        dynamic locationData;
        if (json.containsKey('location')) {
          locationData = json['location'];
        } else if (json.containsKey('location_data')) {
          locationData = json['location_data'];
        } else if (json.isNotEmpty) {
          locationData = json.values.first; // Fallback to first value
        }

        if (json.containsKey('params')) {
          stdout.writeln('  Root Params: ${jsonEncode(json['params'])}');
        }
        if (json.containsKey('extras')) {
          _printExtras(json['extras']);
        }

        // A dedicated telematicsUrl endpoint posts {"telematics": [...]} on its
        // own request (#368). Handled before the location fallback below, which
        // would otherwise take json.values.first and report driving events as
        // "locations" with their magnitudes mislabelled as routeContext.
        if (json['telematics'] case final List<dynamic> events) {
          stdout.writeln('  Batch of ${events.length} telematics event(s):');
          for (final (i, e) in events.indexed) {
            _printTelematicsEvent(e, index: i);
          }
        } else if (locationData is Map) {
          _printLocation(locationData, requestCount);
        } else if (locationData is List) {
          stdout.writeln('  Batch of ${locationData.length} locations:');
          for (final (i, loc) in locationData.indexed) {
            _printLocation(loc as Map, requestCount, index: i);
          }
        } else {
          // Print raw body if format is unexpected
          const encoder = JsonEncoder.withIndent('  ');
          stdout.writeln('  ${encoder.convert(json)}');
        }
      } on FormatException {
        stdout.writeln('  (raw) $body');
      }
    }

    // Always return 200 OK with a JSON response
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'success': true,
          'received': requestCount,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );
    await request.response.close();

    stdout.writeln('  → 200 OK');
    stdout.writeln();
  }
}

/// Prints root `extras`, decoding `__telematics` rather than dumping it raw.
///
/// When `telematicsUrl` is not set, telematics ride the location request as a
/// JSON *string* under `extras.__telematics` — printing that verbatim gives a
/// wall of escaped quotes, which is unreadable exactly when you are trying to
/// confirm what the backend received.
void _printExtras(dynamic extras) {
  if (extras is! Map) {
    stdout.writeln('  Root Extras: ${jsonEncode(extras)}');
    return;
  }

  final rest = Map<dynamic, dynamic>.from(extras)..remove('__telematics');
  if (rest.isNotEmpty) {
    stdout.writeln('  Root Extras: ${jsonEncode(rest)}');
  }

  final raw = extras['__telematics'];
  if (raw == null) return;

  // Tolerate both shapes: a JSON string (what the SDK sends, since extras are
  // string-valued) and an already-decoded list.
  dynamic events = raw;
  if (raw is String) {
    try {
      events = jsonDecode(raw);
    } on FormatException {
      stdout.writeln('  Extras __telematics (unparseable): $raw');
      return;
    }
  }

  if (events is List) {
    stdout.writeln(
      '  Extras __telematics: ${events.length} event(s) '
      '(attached to the location payload)',
    );
    for (final (i, e) in events.indexed) {
      _printTelematicsEvent(e, index: i);
    }
  } else {
    stdout.writeln('  Extras __telematics: ${jsonEncode(events)}');
  }
}

/// Prints one driving/impact event.
///
/// `severity` is the normalized 0–1 flag and `value` the measurement behind it
/// (g, or km/h over the limit) — they are shown side by side because a payload
/// carrying only the first was the bug in #367.
void _printTelematicsEvent(dynamic event, {int? index}) {
  final prefix = index != null ? '    [$index]' : '    ';
  if (event is! Map) {
    stdout.writeln('$prefix ${jsonEncode(event)}');
    return;
  }

  final type = event['event_type'] ?? event['kind'] ?? '?';
  stdout.write('$prefix $type');
  if (event['severity'] != null) stdout.write(', severity=${event['severity']}');
  if (event['value'] != null) stdout.write(', value=${event['value']}');
  if (event['speed'] != null) stdout.write(', speed=${event['speed']}');
  stdout.write(', lat=${event['latitude']}, lng=${event['longitude']}');
  if (event['id'] != null) stdout.write(', id=${event['id']}');
  stdout.writeln();

  if (event['timestamp'] != null) {
    stdout.writeln('$prefix  ts=${event['timestamp']}');
  }

  // Missing magnitudes are the #367 signature, and worth calling out here
  // rather than leaving someone to notice two absent keys by eye.
  if (!event.containsKey('speed') || !event.containsKey('value')) {
    stdout.writeln(
      '$prefix  ⚠️  no speed/value on the wire — pre-#367 native build?',
    );
  }
}

void _printLocation(Map<dynamic, dynamic> loc, int reqNum, {int? index}) {
  final prefix = index != null ? '  [$index]' : '  ';
  final coords = loc['coords'];
  final lat =
      coords?['latitude'] ??
      coords?['lat'] ??
      loc['latitude'] ??
      loc['lat'] ??
      '?';
  final lng =
      coords?['longitude'] ??
      coords?['lng'] ??
      coords?['lon'] ??
      loc['longitude'] ??
      loc['lng'] ??
      loc['lon'] ??
      '?';
  final speed = coords?['speed'] ?? loc['speed'];
  final ts = loc['timestamp'] ?? '';
  final uuid = loc['uuid'] ?? '';
  final accuracy = coords?['accuracy'] ?? loc['accuracy'];
  final isMoving = loc['is_moving'] ?? loc['isMoving'];

  stdout.write('$prefix lat=$lat, lng=$lng');
  if (speed != null) stdout.write(', speed=$speed');
  if (accuracy != null) stdout.write(', acc=$accuracy');
  if (isMoving != null) stdout.write(', moving=$isMoving');
  if (uuid != '') {
    final uuidStr = uuid.toString();
    final shortUuid = uuidStr.length > 8
        ? '${uuidStr.substring(0, 8)}...'
        : uuidStr;
    stdout.write(', uuid=$shortUuid');
  }

  // Find custom keys injected by routeContext
  final standardKeys = {
    'latitude',
    'lat',
    'longitude',
    'lng',
    'lon',
    'speed',
    'timestamp',
    'uuid',
    'accuracy',
    'is_moving',
    'isMoving',
    'coords',
    'activity',
    'id',
    'is_mock',
  };
  final customKeys = loc.keys.where((k) => !standardKeys.contains(k)).toList();
  if (customKeys.isNotEmpty) {
    stdout.write(' | routeContext: {');
    for (var i = 0; i < customKeys.length; i++) {
      final k = customKeys[i];
      stdout.write('"$k": "${loc[k]}"${i < customKeys.length - 1 ? ', ' : ''}');
    }
    stdout.write('}');
  }

  stdout.writeln();
  if (ts != '') stdout.writeln('$prefix  ts=$ts');
}

/// Renders [data] as a QR code made of Unicode half-block characters.
///
/// Two modules are packed into each character cell — `▀` is a dark upper half
/// over a light lower half, and so on — so the code comes out roughly square in
/// a terminal, whose cells are about twice as tall as they are wide. Rendering
/// one module per line would make it twice as tall as the window.
///
/// Colours are set explicitly (black on white) rather than relying on the
/// terminal's own palette. Scanners need dark modules on a light field, and a
/// developer with a dark theme would otherwise get black-on-black.
String _renderQr(String data) {
  final image = QrImage(
    QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M),
  );
  final size = image.moduleCount;

  // The quiet zone is part of the spec, not padding for looks: without ~4
  // modules of clear margin many scanners will not lock on at all.
  const quiet = 4;
  const black = '\x1b[30;47m';
  const reset = '\x1b[0m';

  bool dark(int x, int y) =>
      x >= 0 && y >= 0 && x < size && y < size && image.isDark(y, x);

  final buffer = StringBuffer();
  for (var y = -quiet; y < size + quiet; y += 2) {
    buffer.write(black);
    for (var x = -quiet; x < size + quiet; x++) {
      final top = dark(x, y);
      // The last row of an odd-height code has no lower half to pair with.
      final bottom = dark(x, y + 1);
      if (top && bottom) {
        buffer.write('█');
      } else if (top) {
        buffer.write('▀');
      } else if (bottom) {
        buffer.write('▄');
      } else {
        buffer.write(' ');
      }
    }
    buffer.writeln(reset);
  }
  return buffer.toString();
}

Future<String> _getLocalIp() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    for (final iface in interfaces) {
      if (iface.name == 'en0' || iface.name == 'wlan0') {
        return iface.addresses.first.address;
      }
    }
    if (interfaces.isNotEmpty) {
      return interfaces.first.addresses.first.address;
    }
  } catch (_) {}
  return '0.0.0.0';
}
