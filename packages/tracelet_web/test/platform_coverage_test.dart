import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Verifies that every abstract method in [TraceletPlatform] has a
/// corresponding `@override` implementation in [TraceletWebPlugin].
///
/// This test parses source files directly to detect missing method stubs
/// that would throw [UnimplementedError] at runtime.
void main() {
  group('Platform interface coverage', () {
    test('TraceletWebPlugin overrides all TraceletPlatform methods', () {
      // Read source files.
      final interfaceSource = File(
        '../tracelet_platform_interface/lib/src/tracelet_platform.dart',
      ).readAsStringSync();
      final webPluginSource = File(
        'lib/src/tracelet_web_plugin.dart',
      ).readAsStringSync();

      // Extract method names from the platform interface.
      // Matches: Future<...> methodName(  or  Future<...> methodName([
      final methodPattern = RegExp(
        r'^\s+Future<[^>]+>\s+(\w+)\s*[\(\[]',
        multiLine: true,
      );

      final interfaceMethods = methodPattern
          .allMatches(interfaceSource)
          .map((m) => m.group(1)!)
          .toSet();

      expect(
        interfaceMethods,
        isNotEmpty,
        reason: 'Should find methods in TraceletPlatform',
      );

      // Extract overridden method names from the web plugin.
      // Matches: Future<...> methodName( preceded by @override on a prior line.
      final overridePattern = RegExp(
        r'@override\s+Future<[^>]+>\s+(\w+)\s*[\(\[]',
        multiLine: true,
      );

      final webMethods = overridePattern
          .allMatches(webPluginSource)
          .map((m) => m.group(1)!)
          .toSet();

      final missing = interfaceMethods.difference(webMethods);

      expect(
        missing,
        isEmpty,
        reason:
            'TraceletWebPlugin is missing overrides for: ${missing.join(', ')}. '
            'These will throw UnimplementedError at runtime.',
      );
    });
  });
}
