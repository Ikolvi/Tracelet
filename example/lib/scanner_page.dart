import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:tracelet/tracelet.dart' as tl;

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  bool _isProcessing = false;

  Future<void> _handleScan(String url) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      // 1. Update Tracelet Configuration dynamically
      final currentConfig = tl.Tracelet.activeConfig;
      final newConfig = currentConfig.copyWith(
        http: currentConfig.http.copyWith(url: url),
      );
      // setConfig() requires the engine to already be initialized via ready().
      // If the user scans the QR before starting tracking, iOS throws
      // PlatformException(NOT_READY) (Android silently no-ops). In that case,
      // fall back to ready() so the scanned URL is actually applied.
      try {
        await tl.Tracelet.setConfig(newConfig);
      } on PlatformException catch (e) {
        if (e.code == 'NOT_READY') {
          await tl.Tracelet.ready(newConfig);
        } else {
          rethrow;
        }
      }

      // 2. Send a dummy HTTP POST ping to the server to verify connection
      final httpClient = HttpClient();
      final request = await httpClient.postUrl(Uri.parse(url));
      request.headers.contentType = ContentType(
        'application',
        'json',
        charset: 'utf-8',
      );
      request.write(
        jsonEncode({
          'params': {'message': 'Tracelet App QR Connected successfully!'},
        }),
      );
      await request.close();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connected to Test Server successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to connect: $e'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Server QR Code')),
      body: MobileScanner(
        onDetect: (capture) {
          final barcodes = capture.barcodes;
          if (barcodes.isNotEmpty) {
            final code = barcodes.first.rawValue;
            if (code != null && code.startsWith('http')) {
              _handleScan(code);
            }
          }
        },
      ),
    );
  }
}
