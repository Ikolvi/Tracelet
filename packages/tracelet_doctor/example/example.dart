// Not package:material_ui yet: it needs Flutter >= 3.47 and this package
// still supports older versions.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' as tl;
import 'package:tracelet_doctor/tracelet_doctor.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize core Tracelet configuration
  final baseConfig = tl.Config.highAccuracy();
  await tl.Tracelet.ready(
    baseConfig.copyWith(
      app: baseConfig.app.copyWith(stopOnTerminate: false, startOnBoot: true),
      logger: baseConfig.logger.copyWith(
        debug: true,
        logLevel: tl.LogLevel.verbose,
      ),
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tracelet Doctor Example',
      theme: ThemeData.dark(),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tracelet Companion Dashboard')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Tracelet Background Geolocation is Active',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                // 2. Trigger the drop-in diagnostic overlay dashboard
                TraceletDoctor.show(context);
              },
              icon: const Icon(Icons.medical_services_outlined),
              label: const Text('Launch Tracelet Doctor'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
