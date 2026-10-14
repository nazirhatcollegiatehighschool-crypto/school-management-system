import 'package:flutter/material.dart';
import '../api.dart';

/// Shows offline/pending state and offers manual "Sync Now".
/// Goes away when everything is synced and connectivity is back.
class OfflineSyncBanner extends StatelessWidget {
  final bool compact;
  const OfflineSyncBanner({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final sync = Api.sync;
    return ListenableBuilder(
      listenable: Listenable.merge([sync.online, sync.pending, sync.serverUp, sync]),
      builder: (context, _) {
        final pendingN = sync.pendingCount;
        final online = sync.online.value;
        final serverDown = !sync.serverUp.value;
        final errs = sync.syncErrors.length;
        final show = (pendingN > 0) || !online || serverDown;
        if (!show) {
          return const SizedBox.shrink();
        }
        final canSync = online && !serverDown && pendingN > 0;

        Color bg;
        String msg;
        IconData icon;
        if (!online) {
          bg = const Color(0xFFB71C1C).withValues(alpha: 0.15);
          msg = 'ইন্টারনেট নেই — অ্যাপটি অফলাইনে চলছে';
          icon = Icons.cloud_off;
        } else if (serverDown) {
          bg = const Color(0xFFE65100).withValues(alpha: 0.18);
          msg = 'ইন্টারনেট আছে, কিন্তু school server-এ পৌঁছানো যাচ্ছে না — laptop server / Server URL দেখুন';
          icon = Icons.dns_outlined;
        } else if (pendingN > 0) {
          bg = const Color(0xFFF9A825).withValues(alpha: 0.25);
          msg = '$pendingNটি পরিবর্তন sync-এর অপেক্ষায়${errs > 0 ? ' ($errsটি গ্রহণ হয়নি)' : ''}';
          icon = Icons.sync;
        } else {
          bg = Colors.green.withValues(alpha: 0.15);
          msg = 'ইন্টারনেট আছে — সবকিছু sync হয়ে গেছে';
          icon = Icons.cloud_done;
        }

        return Container(
          width: double.infinity,
          margin: compact ? const EdgeInsets.fromLTRB(12, 4, 12, 0) : const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurface),
              const SizedBox(width: 8),
              Expanded(child: Text(msg, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
              if (canSync)
                TextButton(
                  onPressed: () async {
                    await Api.flushOffline();
                  },
                  child: const Text('Sync Now'),
                ),
              if (serverDown && online)
                TextButton(
                  onPressed: () async {
                    await sync.probeServer();
                  },
                  child: const Text('আবার চেষ্টা'),
                ),
            ],
          ),
        );
      },
    );
  }
}