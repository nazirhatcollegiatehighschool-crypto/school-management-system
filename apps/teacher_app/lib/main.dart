import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'api.dart';
import 'class_alerts.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try { await Firebase.initializeApp(); } catch (_) {}
  FirebaseMessaging.onBackgroundMessage(_bgMessagingHandler);
  await Api.init(); // offline cache + outbox + auto-sync
  await ClassAlertService.instance.init();
  runApp(const TeacherApp());
}

Future<void> _bgMessagingHandler(RemoteMessage message) async {
  try { await Firebase.initializeApp(); } catch (_) {}
}

class TeacherApp extends StatelessWidget {
  const TeacherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Teacher App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

void setToken(String t) => Api.token = t;