import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'api.dart';

Future<void> initFirebase() async {
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_bgHandler);
  } catch (_) {}
}

Future<void> _bgHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

/// Ask permission + register device token with backend (uses JWT identity).
Future<String?> registerDeviceToken() async {
  try {
    final fm = FirebaseMessaging.instance;
    await fm.requestPermission();
    final token = await fm.getToken();
    if (token == null) return null;
    try {
      await fm.subscribeToTopic('all_users');
    } catch (_) {}
    await Api.post('/auth/register-device', {'fcm_token': token, 'platform': 'android'});
    // Re-register automatically whenever FCM rotates the token
    fm.onTokenRefresh.listen((t) {
      Api.post('/auth/register-device', {'fcm_token': t, 'platform': 'android'});
    });
    return token;
  } catch (_) {
    return null;
  }
}

Future<void> unregisterDeviceToken() async {
  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await Api.post('/auth/unregister-device', {'fcm_token': token});
    }
  } catch (_) {}
}

/// Returns payload data map when a message is tapped (for deep linking).
void handleForegroundMessages(BuildContext context, void Function(Map<String, dynamic>) onTap) {
  FirebaseMessaging.onMessage.listen((msg) {
    final snackBar = SnackBar(
      content: Text(msg.notification?.title ?? 'নতুন notification'),
      action: SnackBarAction(
        label: 'দেখুন',
        onPressed: () => onTap(msg.data),
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  });
  FirebaseMessaging.onMessageOpenedApp.listen((msg) => onTap(msg.data));
}