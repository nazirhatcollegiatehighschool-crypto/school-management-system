import 'package:flutter/material.dart';
import '../api.dart';

/// Shows offline/pending state and offers manual "Sync Now".
/// Goes away when everything is synced and connectivity is back.
/// Re-checks connectivity + server reachability on app resume so a stale
/// flag can never wedge the banner forever.
class OfflineSyncBanner extends StatefulWidget {
  final bool compact;
  const OfflineSyncBanner({super.key, this.compact = false});

  @override
  State<OfflineSyncBanner> createState() => _OfflineSyncBannerState();
}

class _OfflineSyncBannerState extends State<OfflineSyncBanner>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Api.sync.recheck();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sync = Api.sync;
    return ListenableBuilder(
      listenable: Listenable.merge([sync.online, sync.pending, sync.serverUp, sync.connState, sync]),
      builder: (context, _) {
        final pendingN = sync.pendingCount;
        final online = sync.online.value;
        final state = sync.connState.value;
        final reconnecting = state == 1;
        final serverDown = !sync.serverUp.value;
        final syncing = sync.isSyncing;
        final errs = sync.syncErrors.length;
        // The banner is ALWAYS visible: a clear Online/Offline status line sits
        // at the top of every screen, and the app keeps working either way.
        final healthy = online && state == 0;
        final canSync = healthy && pendingN > 0;
        final statusColor = healthy
            ? const Color(0xFF2E7D32)
            : (reconnecting ? const Color(0xFFF9A825)
                : (online ? const Color(0xFFE65100) : const Color(0xFFC62828)));
        final statusLabel = healthy ? 'Online' : (reconnecting ? 'Reconnecting…' : 'Offline');
        final statusIcon = healthy
            ? Icons.cloud_done_rounded
            : (reconnecting ? Icons.sync_rounded : Icons.cloud_off_rounded);

        Color bg;
        String msg;
        IconData icon;
        if (reconnecting) {
          bg = const Color(0xFFF9A825).withValues(alpha: 0.18);
          msg = 'সংযোগ পুনঃস্থাপনের চেষ্টা চলছে…';
          icon = Icons.sync;
        } else if (!online) {
          bg = const Color(0xFFB71C1C).withValues(alpha: 0.12);
          msg = 'ইন্টারনেট নেই — অ্যাপ অফলাইনে চলছে, কাজ জমা হচ্ছে';
          icon = Icons.wifi_off;
        } else if (serverDown) {
          bg = const Color(0xFFE65100).withValues(alpha: 0.14);
          msg = 'School server-এ পৌঁছানো যাচ্ছে না — অ্যাপ অফলাইনে চলছে';
          icon = Icons.dns_outlined;
        } else if (pendingN > 0) {
          bg = const Color(0xFFF9A825).withValues(alpha: 0.20);
          msg = syncing
              ? '$pendingNটি পরিবর্তন server-এ sync হচ্ছে…'
              : '$pendingNটি পরিবর্তন sync-এর অপেক্ষায়${errs > 0 ? ' ($errsটি গ্রহণ হয়নি)' : ''}';
          icon = syncing ? Icons.sync : Icons.cloud_upload_outlined;
        } else {
          bg = const Color(0xFF2E7D32).withValues(alpha: 0.10);
          msg = 'সবকিছু sync আছে — নিরিবিঘ্নে কাজ করুন';
          icon = Icons.cloud_done;
        }

        return Container(
          width: double.infinity,
          margin: widget.compact ? const EdgeInsets.fromLTRB(12, 4, 12, 0) : const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(statusIcon, size: 13, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(statusLabel,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.3)),
                ]),
              ),
              const SizedBox(width: 10),
              Icon(icon, size: 15, color: Colors.black54),
              const SizedBox(width: 6),
              Expanded(child: Text(msg, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
              if (canSync)
                TextButton(
                  onPressed: () async {
                    await Api.flushOffline();
                  },
                  child: const Text('Sync Now'),
                ),
              if (reconnecting || (state == 2 && online))
                TextButton(
                  onPressed: () async {
                    await sync.probeServerWithRetry();
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
