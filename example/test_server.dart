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
  stdout.writeln('');
  stdout.writeln('Waiting for location sync requests...');
  stdout.writeln('');

  var requestCount = 0;

  await for (final request in server) {
    requestCount++;
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    final body = await utf8.decoder.bind(request).join();

    stdout.writeln(
      '── Request #$requestCount [$timestamp] '
      '${request.method} ${request.uri.path} ──',
    );

    if (body.isNotEmpty) {
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        final location = json['location'];

        if (location is Map) {
          _printLocation(location, requestCount);
        } else if (location is List) {
          stdout.writeln('  Batch of ${location.length} locations:');
          for (final (i, loc) in location.indexed) {
            _printLocation(loc as Map, requestCount, index: i);
          }
        } else {
          // Print raw body if format is unexpected
          final encoder = const JsonEncoder.withIndent('  ');
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
    stdout.writeln('');
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
  if (uuid != '') stdout.write(', uuid=${uuid.toString().substring(0, 8)}...');
  stdout.writeln('');
  if (ts != '') stdout.writeln('$prefix  ts=$ts');
}

Future<String> _getLocalIp() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
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
