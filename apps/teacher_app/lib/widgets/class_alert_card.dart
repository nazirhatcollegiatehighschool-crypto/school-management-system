import 'package:flutter/material.dart';
import '../class_alerts.dart';

/// The dynamic "Next Class" alert card on the teacher dashboard.
/// idle      -> shows the next class details (simple, calm)
/// countdown -> 5-minute countdown card ("Class Starts In: MM:SS") + beep plays
/// live      -> "Class in Progress" live badge
class ClassAlertCard extends StatelessWidget {
  const ClassAlertCard({super.key});

  static String _fmtSec(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  static String _timeOf(int sec) {
    final h = (sec ~/ 3600).toString().padLeft(2, '0');
    final m = ((sec % 3600) ~/ 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ClassAlertService.instance.snapshot,
      builder: (context, _) {
        final s = ClassAlertService.instance.snapshot.value;
        if (!s.hasCard) {
          return const SizedBox.shrink();
        }
        final r = s.routine!;
        final isLive = s.phase == 'live';
        final isCount = s.phase == 'countdown';

        final (b1, b2) = isLive
            ? (const Color(0xFF43A047), const Color(0xFF1B5E20))
            : isCount
                ? (const Color(0xFFFFB300), const Color(0xFFE65100))
                : (const Color(0xFF4DB6AC), const Color(0xFF00695C));
        final icon = isLive
            ? Icons.radio_button_checked
            : isCount
                ? Icons.timer
                : Icons.school;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(colors: [b1.withValues(alpha: 0.20), b2.withValues(alpha: 0.08)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            border: Border.all(color: b2.withValues(alpha: 0.55), width: 1.6),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, color: b2, size: 22),
                const SizedBox(width: 8),
                Expanded(child: Text(_header(s, isLive), style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: b2))),
                if (isCount)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: b2, borderRadius: BorderRadius.circular(20)),
                    child: Text('Starts In ${_fmtSec(s.secondsLeft)}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, fontFeatures: [FontFeature.tabularFigures()])),
                  ),
                if (isLive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: b2, borderRadius: BorderRadius.circular(20)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.fiber_manual_record, color: Colors.white, size: 12),
                      SizedBox(width: 4),
                      Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ]),
                  ),
              ]),
              const SizedBox(height: 10),
              Text(r.subject, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              if (r.classLabel.isNotEmpty)
                Row(children: [
                  const Icon(Icons.group, size: 16, color: Colors.black54),
                  const SizedBox(width: 5),
                  Expanded(child: Text(r.classLabel, style: const TextStyle(fontSize: 14, color: Colors.black87))),
                ]),
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.schedule, size: 15, color: Colors.black54),
                const SizedBox(width: 5),
                Text(
                  '${r.slotLabel} · ${_timeOf(r.startSec)}–${_timeOf(r.endSec)}${r.room.isNotEmpty ? ' • Room ${r.room}' : ''}',
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ]),
            ]),
          ),
        );
      },
    );
  }

  static String _header(ClassAlertSnapshot s, bool isLive) {
    if (isLive) return 'Class in Progress';
    if (s.phase == 'countdown') return 'Class Starts In ${_fmtSec(s.secondsLeft)}';
    return 'Next Class';
  }
}