import 'package:flutter/material.dart';
String _slotDisplayName(String? l0) {
  final l = (l0 ?? '').toString().trim();
  final m = RegExp(r'^CLASS_(\d)$', caseSensitive: false).firstMatch(l);
  if (m != null) {
    const bn = <String, String>{'1': '১ম', '2': '২য়', '3': '৩য়', '4': '৪ৰ্থ', '5': '৫ম', '6': '৬ষ্ঠ', '7': '৭ম'};
    return '${bn[m.group(1)!] ?? m.group(1)} Period';
  }
  final lw = l.toLowerCase();
  if (lw == 'assembly') return 'সমাবেশ';
  if (lw == 'leisure') return 'অবসর';
  return l0?.toString() ?? '';
}

const _days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday'];

class RoutineView extends StatelessWidget {
  final dynamic routines;
  const RoutineView({super.key, required this.routines});
  @override
  Widget build(BuildContext context) {
    // routines from /routine/student returns array of {student, routine:[...]}
    final items = routines is List ? routines : [];
    if (items.isEmpty) return const Center(child: Text('কোনো routine নেই'));

    // Build flat list for this student (guardian = single student usually)
    final all = <dynamic>[];
    for (final entry in items) {
      if (entry['routine'] is List) all.addAll(entry['routine'] as List);
    }
    if (all.isEmpty) return const Center(child: Text('কোনো routine নেই'));

    // Group by day
    final byDay = <String, List>{};
    for (final r in all) {
      final d = '${r['day_name'] ?? ''}';
      (byDay[d] = byDay[d] ?? []).add(r);
    }

    final student = items.isNotEmpty ? items[0]['student'] : null;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (student != null && '${student['name']}'.trim().isNotEmpty)
          Card(
            color: Colors.indigo.shade50,
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.indigo.shade100,
                  child: Text('${student['name']}'.characters.first, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text('${student['name']} • ${student['class_name'] ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.w600))),
              ]),
            ),
          ),
        ..._days.map((day) {
          final list = byDay[day] ?? [];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
                child: Text(day, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
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
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    child: ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 15,
                        backgroundColor: Colors.indigo.shade100,
                        child: Text('${e['slot_order'] ?? ''}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      title: Row(children: [
                        Flexible(child: Text(subjectName, style: const TextStyle(fontSize: 13))),
                        if (e['is_escape'] == true || e['is_escape'] == 1 || e['is_escape'] == '1')
                          const Padding(padding: EdgeInsets.only(left: 6),
                              child: Text('বাঙ্ক', style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold))),
                      ]),
                      subtitle: Text(
                        '${e['slot_label'] ?? ''}  ${e['start_time']?.toString().substring(0, 5) ?? ''}–${e['end_time']?.toString().substring(0, 5) ?? ''}',
                        style: const TextStyle(fontSize: 11),
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
