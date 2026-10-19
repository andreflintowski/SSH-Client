import 'package:flutter/material.dart';

import 'data/host_repository.dart';
import 'screens/hosts_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = HostRepository();
  await repo.load();
  runApp(SshApp(repo: repo));
}

class SshApp extends StatelessWidget {
  final HostRepository repo;

  const SshApp({super.key, required this.repo});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SSH',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: HostsScreen(repo: repo),
    );
  }
}
