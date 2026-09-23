import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';

const String appVersion = '1.2.0';

/// manual=false: silent auto-check on login (only prompts when new version exists).
/// manual=true: triggered from Settings — also reports "up-to-date" or "can't check".
Future<void> checkForUpdate(BuildContext context, String appName, {bool manual = false}) async {
  try {
    final r = await Api.get('/app-version?app=$appName');
    final latest = r['version']?.toString();
    final url = r['apk_url']?.toString();
    if (latest == null || url == null) {
      if (manual && context.mounted) _say(context, 'আপডেট তথ্য পাওয়া যায়নি।');
      return;
    }
    if (latest != appVersion) {
      _showUpdateDialog(context, appVersion, latest, url);
    } else if (manual) {
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('✅ সব আপ-টু-ডেট'),
          content: Text('আপনার App-এ সর্বশেষ version আছে (v$appVersion)।'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('ঠিক আছে'))],
        ),
      );
    }
  } catch (_) {
    if (manual && context.mounted) _say(context, 'ইন্টারনেট চেক করুন — আপডেট পরীক্ষা করা যায়নি।');
  }
}

Future<void> _showUpdateDialog(BuildContext context, String current, String latest, String url) async {
  if (!context.mounted) return;
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: const Text('🔄 Update Available'),
      content: Text(
          'নতুন version এসেছে (v$latest)।\nআপনার বর্তমান version: v$current\n\n"Update Now" চাপলে APK download শুরু হবে — download শেষে সেটি open করে Install করুন।'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('পরে')),
        FilledButton(
          onPressed: () async {
            final uri = Uri.parse(url);
            try {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } catch (_) {}
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Update Now'),
        ),
      ],
    ),
  );
}

void _say(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}