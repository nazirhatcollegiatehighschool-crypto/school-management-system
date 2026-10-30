import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

String slotDisplayName(String? l0) {
  final l = (l0 ?? '').toString().trim();
  final m = RegExp(r'^CLASS_(\d)$', caseSensitive: false).firstMatch(l);
  if (m != null) {
    const bn = <String, String>{
      '1': '১ম',
      '2': '২য়',
      '3': '৩য়',
      '4': '৪র্থ',
      '5': '৫ম',
      '6': '৬ষ্ঠ',
      '7': '৭ম',
    };
    return '${bn[m.group(1)!] ?? m.group(1)} Period';
  }
  final lw = l.toLowerCase();
  if (lw == 'assembly') return 'সমাবেশ';
  if (lw == 'leisure') return 'অবসর';
  return l0?.toString() ?? '';
}

const _days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday'];

const _dayNamesBn = {
  'Sunday': 'রবিবার',
  'Monday': 'সোমবার',
  'Tuesday': 'মঙ্গলবার',
  'Wednesday': 'বুধবার',
  'Thursday': 'বৃহস্পতিবার',
  'Friday': 'শুক্রবার',
  'Saturday': 'শনিবার',
};

int? _timeToMinutes(dynamic v) {
  final s = (v ?? '').toString();
  final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(s);
  if (m == null) return null;
  return (int.parse(m.group(1)!) * 60) + int.parse(m.group(2)!);
}

/// Flattens the /routine/student payload to the routine rows of ONE student.
List _rowsForStudent(dynamic routines, {int? studentId}) {
  final entries = routines is List ? routines : [];
  final rows = <dynamic>[];
  for (final entry in entries) {
    if (entry is! Map || entry['routine'] is! List) continue;
    if (studentId != null) {
      final st = entry['student'];
      if (st is Map && '${st['id']}' != '$studentId') continue;
    }
    rows.addAll(entry['routine'] as List);
  }
  return rows;
}

Map? _studentForRoutines(dynamic routines, {int? studentId}) {
  if (routines is! List) return null;
  for (final entry in routines) {
    if (entry is! Map || entry['student'] is! Map) continue;
    final student = entry['student'] as Map;
    if (studentId == null || '${student['id']}' == '$studentId') {
      return student;
    }
  }
  return null;
}

String? _firstPhone(dynamic phone) {
  final s = (phone ?? '').toString().trim();
  if (s.isEmpty) return null;
  final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.isEmpty ? null : digits;
}

/// "চলমান ক্লাস" banner — like the teacher app dashboard banner.
/// Shows the running (or next) period with subject, class, time and the
/// teacher's name + tap-to-call phone button.
class CurrentClassBanner extends StatelessWidget {
  final dynamic routines;
  final int? studentId;
  const CurrentClassBanner({super.key, required this.routines, this.studentId});

  @override
  Widget build(BuildContext context) {
    final rows = _rowsForStudent(routines, studentId: studentId);
    final now = DateTime.now().toUtc().add(const Duration(hours: 6));
    // DateTime.weekday uses Monday=1..Sunday=7, while this list starts Sunday.
    final today = weekdayName[now.weekday % 7];
    final todayRows =
        rows.where((r) {
          final d = (r is Map ? r['day_name'] : '')?.toString();
          return d != null && d.toLowerCase() == today.toLowerCase();
        }).toList()..sort((a, b) {
          final av =
              _timeToMinutes(a is Map ? a['start_time'] : null) ?? 999999;
          final bv =
              _timeToMinutes(b is Map ? b['start_time'] : null) ?? 999999;
          return av.compareTo(bv);
        });

    final nowMin = now.hour * 60 + now.minute;
    Map? current;
    Map? next;
    for (final raw in todayRows) {
      if (raw is! Map) continue;
      final start = _timeToMinutes(raw['start_time']);
      final end = _timeToMinutes(raw['end_time']);
      if (start == null || end == null) continue;
      if (nowMin >= start && nowMin < end) {
        current = raw;
        break;
      }
      if (nowMin < start && next == null) next = raw;
    }

    if (current == null && next == null) {
      return CurrentClassBanner._shell(
        icon: Icons.nights_stay_rounded,
        iconColor: Colors.blueGrey,
        title: todayRows.isEmpty ? 'আজ ছুটির দিন 🎉' : 'আজকের ক্লাস শেষ 🎉',
        subtitle: todayRows.isEmpty
            ? 'আজকের কোনো routine নেই'
            : 'আজ আর কোনো ক্লাস নেই',
      );
    }

    final live = current != null;
    final r = (live ? current : next)!;
    final subject = (r['subject'] is Map ? (r['subject']['name'] ?? '') : '')
        .toString();
    final start = _timeToMinutes(r['start_time']);
    final end = _timeToMinutes(r['end_time']);
    String two(int v) => v.toString().padLeft(2, '0');
    final timeLabel = (start != null && end != null)
        ? '${two(start ~/ 60)}:${two(start % 60)} – ${two(end ~/ 60)}:${two(end % 60)}'
        : '';
    final slot = slotDisplayName(r['slot_label']?.toString());
    final student = _studentForRoutines(routines, studentId: studentId);
    final classLabel =
        '${(student is Map ? student['class_name'] : '') ?? ''} ${student is Map ? (student['section'] ?? '') : ''}'
            .trim();
    final teacherName = (r['teacher_name'] ?? '').toString().trim();
    final phone = _firstPhone(r['teacher_phone']);

    final accent = live ? const Color(0xFFB9F36B) : const Color(0xFFFFD76A);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF202A49),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  live ? Icons.sensors_rounded : Icons.hourglass_top_rounded,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  live ? 'চলমান ক্লাস • $subject' : 'পরবর্তী ক্লাস • $subject',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  live ? 'LIVE' : (timeLabel.isEmpty ? 'শীঘ্রই' : timeLabel),
                  style: const TextStyle(
                    color: Color(0xFF202A49),
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            [
              if (classLabel.isNotEmpty) classLabel,
              if (slot.isNotEmpty) slot,
              timeLabel,
            ].join('  •  '),
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          if (teacherName.isNotEmpty || phone != null)
            Row(
              children: [
                Icon(
                  Icons.person_rounded,
                  size: 15,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    teacherName.isNotEmpty ? 'শিক্ষক: $teacherName' : '—',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (phone != null)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => _call(context, phone),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16A34A),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.call_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 5),
                            const Text(
                              'কল করুন',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _call(BuildContext context, String phone) async {
    try {
      final uri = Uri(scheme: 'tel', path: phone);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ডায়ালার খোলা যায়নি')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ডায়ালার খোলা যায়নি')));
      }
    }
  }

  static Widget _shell({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
    ),
    padding: const EdgeInsets.all(14),
    child: Row(
      children: [
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

const weekdayName = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];

class RoutineView extends StatelessWidget {
  final dynamic routines;
  final int? studentId;
  final bool showBanner;
  const RoutineView({
    super.key,
    required this.routines,
    this.studentId,
    this.showBanner = true,
  });
  @override
  Widget build(BuildContext context) {
    // routines from /routine/student returns array of {student, routine:[...]}
    final studentRows = _rowsForStudent(routines, studentId: studentId);
    if (studentRows.isEmpty) {
      return const Center(child: Text('কোনো routine নেই'));
    }

    // Group by day
    final byDay = <String, List>{};
    for (final r in studentRows) {
      final d = '${r['day_name'] ?? ''}';
      (byDay[d] = byDay[d] ?? []).add(r);
    }

    final student = _studentForRoutines(routines, studentId: studentId);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (showBanner)
          CurrentClassBanner(routines: routines, studentId: studentId),
        if (student != null && '${student['name']}'.trim().isNotEmpty)
          Card(
            color: Colors.indigo.shade50,
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.indigo.shade100,
                    child: Text(
                      '${student['name']}'.characters.first,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${student['name']} • ${student['class_name'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ..._days.map((day) {
          final list = byDay[day] ?? [];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
                child: Text(
                  '$day (${_dayNamesBn[day] ?? day})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
              ),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text('—', style: TextStyle(color: Colors.grey)),
                )
              else
                ...list.map((e) {
                  final sub = e['subject'];
                  final subjectName = sub['name'] ?? '';
                  final teacher = (e['teacher_name'] ?? '').toString().trim();
                  final phone = _firstPhone(e['teacher_phone']);
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    child: ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 15,
                        backgroundColor: Colors.indigo.shade100,
                        child: Text(
                          '${e['slot_order'] ?? ''}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              subjectName,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          if (e['is_escape'] == true ||
                              e['is_escape'] == 1 ||
                              e['is_escape'] == '1')
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Text(
                                'বাঙ্ক',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        '${slotDisplayName(e['slot_label']?.toString())}  ${e['start_time']?.toString().substring(0, 5) ?? ''}–${e['end_time']?.toString().substring(0, 5) ?? ''}${teacher.isNotEmpty ? ' · $teacher' : ''}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      onTap: phone == null
                          ? null
                          : () async {
                              try {
                                await launchUrl(
                                  Uri(scheme: 'tel', path: phone),
                                  mode: LaunchMode.externalApplication,
                                );
                              } catch (_) {}
                            },
                      trailing: phone == null
                          ? null
                          : const Icon(
                              Icons.call_rounded,
                              size: 16,
                              color: Color(0xFF16A34A),
                            ),
                    ),
                  );
                }),
            ],
          );
        }),
      ],
    );
  }
}
