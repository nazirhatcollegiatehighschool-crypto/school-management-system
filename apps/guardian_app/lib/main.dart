import 'package:flutter/material.dart';
import 'api.dart';
import 'app_theme.dart';
import 'config.dart';
import 'fcm_service.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Config.loadOverride(); // server URL saved from Server settings
  await Api.init(); // offline cache + outbox + auto-sync
  await initFirebase();
  runApp(const GuardianApp());
}

class GuardianApp extends StatelessWidget {
  const GuardianApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Guardian App',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const SplashScreen(),
    );
  }
}