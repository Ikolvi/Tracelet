import 'package:material_ui/material_ui.dart';
import 'package:tracelet_example/local_test_server.dart';
import 'package:tracelet_example/server_logs_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LocalTestServer.instance.start();
  runApp(const TestServerApp());
}

class TestServerApp extends StatelessWidget {
  const TestServerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tracelet Test Server',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const ServerLogsPage(),
    );
  }
}
