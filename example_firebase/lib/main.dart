// ignore_for_file: uri_does_not_exist, undefined_identifier
import 'package:example_firebase/firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tracelet/tracelet.dart';
import 'package:tracelet_firebase/tracelet_firebase.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final databaseUrl = Firebase.app().options.databaseURL;
  if (databaseUrl == null) {
    throw Exception(
      'Database URL not found in FirebaseOptions. Please ensure you have created a Realtime Database and run "flutterfire configure" again.',
    );
  }

  // 2. Configure Token Refresh (Crucial for background tracking)
  await TraceletFirebase.configureTokenRefresh();

  // 3. Authenticate user to get an ID for the RTDB path
  // In a real app, the user might already be logged in
  UserCredential? userCredential;
  try {
    userCredential = await FirebaseAuth.instance.signInAnonymously();
  } catch (e) {
    debugPrint('Firebase Auth Error: $e');
  }

  final uid = userCredential?.user?.uid ?? 'anonymous_device';

  // 4. Build the Native HTTP Config
  final httpConfig = await TraceletFirebase.buildHttpConfig(
    databaseUrl: databaseUrl,
    path: 'locations/$uid',
  );

  // 5. Initialize Tracelet
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

  // 6. Smart Functionality: Handle action buttons from the notification
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
        appBar: AppBar(title: const Text('Tracelet Firebase Adapter')),
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
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
