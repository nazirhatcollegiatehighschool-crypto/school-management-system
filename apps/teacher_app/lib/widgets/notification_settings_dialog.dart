import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../fcm_service.dart';

Future<void> showNotificationSettings(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _NotificationSettingsDialog(),
);

class _NotificationSettingsDialog extends StatefulWidget {
  const _NotificationSettingsDialog();

  @override
  State<_NotificationSettingsDialog> createState() =>
      _NotificationSettingsDialogState();
}

class _NotificationSettingsDialogState
    extends State<_NotificationSettingsDialog>
    with WidgetsBindingObserver {
  bool _enabled = true;
  bool _loading = true;
  bool _busy = false;
  AuthorizationStatus? _authorization;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final enabled = await isPushNotificationsEnabled();
      final authorization = await pushNotificationAuthorization();
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _authorization = authorization;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Notification service পাওয়া যায়নি: $error';
      });
    }
  }

  Future<void> _setEnabled(bool enabled) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final queued = await configurePushNotifications(enabled);
      final authorization = await pushNotificationAuthorization();
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _authorization = authorization;
        _busy = false;
        _error = queued
            ? 'ইন্টারনেট না থাকায় পরিবর্তনটি queue-তে রাখা হয়েছে।'
            : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  String get _permissionLabel => switch (_authorization) {
    AuthorizationStatus.authorized => 'ফোনে অনুমতি চালু',
    AuthorizationStatus.provisional => 'সীমিত অনুমতি চালু',
    AuthorizationStatus.denied => 'ফোনে অনুমতি বন্ধ',
    AuthorizationStatus.notDetermined => 'এখনো অনুমতি চাওয়া হয়নি',
    null => 'অনুমতির অবস্থা যাচাই করা যায়নি',
  };

  @override
  Widget build(BuildContext context) {
    final permissionDenied = _authorization == AuthorizationStatus.denied;
    return AlertDialog(
      title: const Text('Notification সেটিংস'),
      content: _loading
          ? const SizedBox(
              height: 72,
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Push notification'),
                  subtitle: Text(_permissionLabel),
                  value: _enabled,
                  onChanged: _busy ? null : _setEnabled,
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: _error!.startsWith('ইন্টারনেট')
                            ? Colors.orange.shade800
                            : Colors.red.shade700,
                      ),
                    ),
                  ),
                if (permissionDenied)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: openAppSettings,
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('ফোনের Settings খুলুন'),
                    ),
                  ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('বন্ধ করুন'),
        ),
      ],
    );
  }
}
