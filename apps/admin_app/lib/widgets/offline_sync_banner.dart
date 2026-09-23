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
      listenable: Listenable.merge([sync.online, sync.pending, sync]),
      builder: (context, _) {
        final pendingN = sync.pendingCount;
        final online = sync.online.value;
        final errs = sync.syncErrors.length;
        final show = (pendingN > 0) || !online;
        if (!show) {
          return const SizedBox.shrink();
        }
        final canSync = online && pendingN > 0;

        Color bg;
        String msg;
        if (!online) {
          bg = const Color(0xFFB71C1C).withValues(alpha: 0.15);
          msg = 'ইন্টারনেট নেই — অ্যাপটি অফলাইনে চলছে';
        } else if (pendingN > 0) {
          bg = const Color(0xFFF9A825).withValues(alpha: 0.25);
          msg = '$pendingNটি পরিবর্তন sync-এর অপেক্ষায়${errs > 0 ? ' ($errsটি গ্রহণ হয়নি)' : ''}';
        } else {
          bg = Colors.green.withValues(alpha: 0.15);
          msg = 'ইন্টারনেট আছে — সবকিছু sync হয়ে গেছে';
        }

        return Container(
          width: double.infinity,
          margin: compact ? const EdgeInsets.fromLTRB(12, 4, 12, 0) : const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              Icon(canSync ? Icons.sync : (online ? Icons.cloud_done : Icons.cloud_off),
                  size: 18, color: Theme.of(context).colorScheme.onSurface),
              const SizedBox(width: 8),
              Expanded(child: Text(msg, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
              if (canSync)
                TextButton(
                  onPressed: () async {
                    await Api.flushOffline();
                  },
                  child: const Text('Sync Now'),
                ),
            ],
          ),
        );
      },
    );
  }
}