import 'package:flutter/material.dart';

import '../api.dart';

/// Compact connectivity label shared visually with the Teacher app.
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
    if (state == AppLifecycleState.resumed) Api.sync.recheck();
  }

  @override
  Widget build(BuildContext context) {
    final sync = Api.sync;
    return ListenableBuilder(
      listenable: Listenable.merge([
        sync.online,
        sync.serverUp,
        sync.connState,
      ]),
      builder: (context, _) {
        final online =
            sync.online.value &&
            sync.serverUp.value &&
            sync.connState.value == 0;
        final color = online
            ? const Color(0xFF2E7D32)
            : const Color(0xFFC62828);
        return Container(
          width: double.infinity,
          margin: widget.compact
              ? const EdgeInsets.fromLTRB(12, 4, 12, 0)
              : const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    online ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                    size: 13,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    online ? 'Online' : 'Offline',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: .3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
