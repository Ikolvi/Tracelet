import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracelet/tracelet.dart';
import 'package:tracelet_supabase/tracelet_supabase.dart';

// Replace these with your actual Supabase project credentials
const supabaseUrl = 'YOUR_SUPABASE_URL';
const supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Supabase
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

  // 2. Configure Token Refresh (Crucial for background tracking)
  await TraceletSupabase.configureTokenRefresh(anonKey: supabaseAnonKey);

  // 3. Build the Native HTTP Config
  final httpConfig = TraceletSupabase.buildHttpConfig(
    supabaseUrl: supabaseUrl,
    anonKey: supabaseAnonKey,
    edgeFunction: 'tracelet-ingest',
  );

  // 4. Initialize Tracelet
  await Tracelet.ready(
    Config(
      geo: const GeoConfig(distanceFilter: 50),
      http: httpConfig,
      android: const AndroidConfig(
        foregroundService: ForegroundServiceConfig(
          showNotificationOnPauseOnly:
              true, // Hides notification while app is in foreground
          notificationTitle: 'Tracelet Tracker',
          notificationText: 'Actively tracking your route',
          actions: ['Stop Tracking'],
        ),
      ),
    ),
  );

  // 5. Smart Functionality: Handle action buttons from the notification
  Tracelet.onNotificationAction((action) async {
    if (action == 'Stop Tracking') {
      await Tracelet.stop();
    }
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Tracelet Supabase Adapter')),
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              // Sign in anonymously for testing
              await Supabase.instance.client.auth.signInAnonymously();

              // Request location permissions before starting
              await Tracelet.requestLocationAuthorization();

              // Request notification permissions (Required for Android 13+ foreground service)
              await Tracelet.requestNotificationAuthorization();

              // Start tracking!
              await Tracelet.start();
            },
            child: const Text('Start Tracking'),
          ),
        ),
      ),
    );
  }
}
