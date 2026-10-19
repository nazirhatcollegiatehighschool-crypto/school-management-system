import 'package:flutter/material.dart';
import 'api.dart';
import 'config.dart';

/// Server URL setting — lets the app point at a different backend URL
/// without a rebuild. Saved on-device; test before saving.
Future<void> showServerUrlDialog(BuildContext context) async {
  final ctl = TextEditingController(text: Config.serverUrl);
  String? status;
  bool testing = false;
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
      title: const Text('🔧 Server URL'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('ডিফল্ট server ছাড়া অন্য URL লাগলে এখানে বসান।\nযেমন: https://school-management-system-brown-mu.vercel.app',
            style: TextStyle(fontSize: 12.5)),
        const SizedBox(height: 10),
        TextField(controller: ctl, keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Server URL *', border: OutlineInputBorder(),
                hintText: 'https://school-management-system-brown-mu.vercel.app')),
        if (status != null) ...[
          const SizedBox(height: 8),
          Text(status!, style: TextStyle(fontSize: 12.5,
              color: status!.startsWith('✅') ? Colors.green.shade700 : Colors.red)),
        ],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('বাতিল')),
        TextButton(
          onPressed: testing ? null : () async {
            setD(() { testing = true; status = 'পরীক্ষা চলছে…'; });
            final ok = await _testUrl(ctl.text.trim());
            setD(() {
              testing = false;
              status = ok ? '✅ Server পাওয়া গেছে — Save চাপুন' : '❌ Server-এ পৌঁছানো যাচ্ছে না';
            });
          },
          child: const Text('Test')),
        FilledButton(
          onPressed: () async {
            final u = ctl.text.trim().replaceAll(RegExp(r'/+$'), '');
            if (!u.startsWith('http://') && !u.startsWith('https://')) {
              setD(() => status = '❌ http:// বা https:// দিয়ে শুরু হতে হবে');
              return;
            }
            await Config.setOverride(u);
            if (ctx.mounted) Navigator.pop(ctx);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  backgroundColor: Colors.green,
                  content: Text('✓ Server বদলেছে — অ্যাপ বন্ধ করে আবার খুলুন')));
            }
          },
          child: const Text('Save')),
      ],
    )),
  );
}

Future<bool> _testUrl(String base) async {
  if (base.isEmpty) return false;
  try {
    final res = await Api.testHealth(base);
    return res == true;
  } catch (_) {
    return false;
  }
}
