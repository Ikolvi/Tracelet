import 'dart:math' as math;

/// Simple UUID v4 generator (no crypto dependency).
///
/// Shared between web engine files that need unique identifiers.
String generateUuid() {
  final rng = math.Random();
  return '${_hex(rng, 8)}-${_hex(rng, 4)}-4${_hex(rng, 3)}-'
      '${_hexVariant(rng)}${_hex(rng, 3)}-${_hex(rng, 12)}';
}

String _hex(math.Random rng, int count) {
  final sb = StringBuffer();
  for (var i = 0; i < count; i++) {
    sb.write(rng.nextInt(16).toRadixString(16));
  }
  return sb.toString();
}

String _hexVariant(math.Random rng) => (8 + rng.nextInt(4)).toRadixString(16);
