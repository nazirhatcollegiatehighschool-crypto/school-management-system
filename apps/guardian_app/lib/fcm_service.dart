import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

const _pushNotificationsKey = 'push_notifications_enabled';
StreamSubscription<String>? _tokenRefreshSubscription;

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
    if (!await isPushNotificationsEnabled()) return null;
    final fm = FirebaseMessaging.instance;
    var settings = await fm.getNotificationSettings();
    if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
      settings = await fm.requestPermission();
    }
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      return null;
    }
    final token = await fm.getToken();
    if (token == null) return null;
    try {
      await fm.unsubscribeFromTopic('all_users');
    } catch (_) {}
    await Api.post('/auth/register-device', {
      'fcm_token': token,
      'platform': 'android',
    });
    _tokenRefreshSubscription ??= fm.onTokenRefresh.listen((
      refreshedToken,
    ) async {
      try {
        if (!await isPushNotificationsEnabled()) return;
        await Api.post('/auth/register-device', {
          'fcm_token': refreshedToken,
          'platform': 'android',
        });
      } catch (error) {
        debugPrint('Device notification token refresh failed: $error');
      }
    });
    return token;
  } catch (error) {
    debugPrint('Device notification registration failed: $error');
    return null;
  }
}

Future<bool> isPushNotificationsEnabled() async {
  final preferences = await SharedPreferences.getInstance();
  return preferences.getBool(_pushNotificationsKey) ?? true;
}

Future<AuthorizationStatus> pushNotificationAuthorization() async {
  final settings = await FirebaseMessaging.instance.getNotificationSettings();
  return settings.authorizationStatus;
}

Future<bool> configurePushNotifications(bool enabled) async {
  final preferences = await SharedPreferences.getInstance();
  final messaging = FirebaseMessaging.instance;
  if (!enabled) {
    final token = await messaging.getToken();
    try {
      await messaging.unsubscribeFromTopic('all_users');
    } catch (_) {}
    var queued = false;
    if (token != null) {
      final result = await Api.post('/auth/unregister-device', {
        'fcm_token': token,
      });
      queued = Api.isQueued(result);
      if (!queued && (result is! Map || result['ok'] != true)) {
        throw StateError('সার্ভার notification বন্ধ করার অনুরোধ গ্রহণ করেনি।');
      }
    }
    await preferences.setBool(_pushNotificationsKey, false);
    return queued;
  }

  var settings = await messaging.getNotificationSettings();
  if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
    settings = await messaging.requestPermission();
  }
  if (settings.authorizationStatus != AuthorizationStatus.authorized &&
      settings.authorizationStatus != AuthorizationStatus.provisional) {
    throw StateError(
      'ফোনের Settings থেকে এই অ্যাপের notification permission চালু করুন।',
    );
  }

  final token = await messaging.getToken();
  if (token == null) {
    throw StateError('এই ফোনের notification token পাওয়া যায়নি।');
  }
  try {
    await messaging.unsubscribeFromTopic('all_users');
  } catch (_) {}
  final result = await Api.post('/auth/register-device', {
    'fcm_token': token,
    'platform': 'android',
  });
  final queued = Api.isQueued(result);
  if (!queued && (result is! Map || result['ok'] != true)) {
    throw StateError('সার্ভার notification registration গ্রহণ করেনি।');
  }
  await preferences.setBool(_pushNotificationsKey, true);
  return queued;
}

Future<void> unregisterDeviceToken() async {
  try {
    final messaging = FirebaseMessaging.instance;
    final token = await messaging.getToken();
    if (token != null) {
      final result = await Api.post('/auth/unregister-device', {
        'fcm_token': token,
      });
      if (Api.isQueued(result)) {
        await messaging.deleteToken();
      }
    }
    try {
      await messaging.unsubscribeFromTopic('all_users');
    } catch (_) {}
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_pushNotificationsKey, false);
  } catch (_) {}
}

/// Returns payload data map when a message is tapped (for deep linking).
void handleForegroundMessages(
  BuildContext context,
  void Function(Map<String, dynamic>) onTap,
) {
  final messenger = ScaffoldMessenger.of(context);
  FirebaseMessaging.onMessage.listen((msg) {
    final snackBar = SnackBar(
      content: Text(msg.notification?.title ?? 'নতুন notification'),
      action: SnackBarAction(label: 'দেখুন', onPressed: () => onTap(msg.data)),
    );
    messenger.showSnackBar(snackBar);
  });
  FirebaseMessaging.onMessageOpenedApp.listen((msg) => onTap(msg.data));
}
