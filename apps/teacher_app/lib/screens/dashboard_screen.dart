import 'dart:math';
import 'package:flutter/material.dart';
import '../api.dart';
import '../class_alerts.dart';
import '../widgets/offline_sync_banner.dart';
import 'class_students_screen.dart';
import 'attendance_screen.dart';
import 'exams_screen.dart';
import 'homework_screen.dart';
import 'routine_screen.dart';
import 'who_is_free_screen.dart';

const _days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday'];

class DashboardScreen extends StatefulWidget {
  final dynamic teacher;
  const DashboardScreen({super.key, required this.teacher});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List _exams = [];
  List _classes = [];
  List _routineEntries = [];
  Map<String, int> _attCounts = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        Api.get('/teacher/exams'),
        Api.get('/teacher/attendance?date=${DateTime.now().toIso8601String().substring(0, 10)}'),
        Api.get('/teacher/profile').catchError((_) => const <String, dynamic>{}),
        Api.get('/routine/teacher/mine').catchError((_) => const <dynamic>[]),
      ]);
      final exams = results[0] is List ? results[0] : [];
      final att = results[1] is List ? results[1] : [];
      final profile = results[2] is Map ? results[2] as Map : <String, dynamic>{};
      final routine = results[3] is List ? results[3] as List : <dynamic>[];
      final counts = {'present': 0, 'absent': 0, 'late': 0};
      for (final a in att) {
        final s = a['status']?.toString() ?? '';
        if (counts.containsKey(s)) counts[s] = counts[s]! + 1;
      }
      await ClassAlertService.instance.updateRoutines(routine);
      if (!mounted) return;
      setState(() {
        _exams = exams;
        _attCounts = counts;
        _classes = (profile['classes'] as List? ?? []);
        _routineEntries = routine;
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  int _schoolDayOf(DateTime d) {
    if (d.weekday == 7) return 0;
    return d.weekday;
  }

  int _hms(String t) {
    final p = t.split(':');
    if (p.length < 2) return 0;
    return int.parse(p[0]) * 3600 + int.parse(p[1]) * 60 + (p.length > 2 ? int.parse(p[2]) : 0);
  }

  String _classSummary(dynamic entry) {
    final parts = <String>{};
    for (final s in (entry?['sections'] as List?) ?? []) {
      parts.add('${s['class_name']} ${s['section']}');
    }
    for (final g in (entry?['groups'] as List?) ?? []) {
      parts.add('${g['class_name']} ${g['group_name']}');
    }
    return parts.join(', ');
  }

  String _monthName(int m) => const ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][m];

  String _greeting(DateTime now) {
    final h = now.hour;
    if (h < 5) return 'শুভ রাত্রি';
    if (h < 11) return 'শুভ সকাল';
    if (h < 16) return 'শুভ দুপুর';
    if (h < 20) return 'শুভ সন্ধ্যা';
    return 'শুভ রাত্রি';
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final sd = _schoolDayOf(today);
    final isWeekend = sd >= 5;
    final nowSec = today.hour * 3600 + today.minute * 60 + today.second;
    final isClassTeacher = _classes.isNotEmpty;
    final myCount = _exams.where((e) => e['is_mine'] == 1).length;
    final pubCount = _exams.where((e) => e['status'] == 'published').length;
    final draftCount = _exams.where((e) => e['status'] == 'draft').length;
    final submittedCount = _exams.length - pubCount - draftCount;

    // Today's timeline (sorted picks only real instructional periods)
    final todayEntries = _routineEntries
        .where((e) => (e['day'] is int ? e['day'] : 0) == sd)
        .where((e) => (e['start_time']?.toString().length ?? 0) >= 5)
        .toList()
      ..sort((a, b) {
        final sa = _hms(a['start_time'].toString());
        final sb = _hms(b['start_time'].toString());
        return sa.compareTo(sb);
      });

    return Scaffold(
      appBar: AppBar(title: Text(isWeekend ? 'Weekend' : _days[sd]), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(14), children: [
                    // ===== Greeting hero =====
                    _GreetingHero(
                      teacher: widget.teacher,
                      greeting: _greeting(today),
                      dateText: '${today.day} ${_monthName(today.month)}, ${today.year}',
                      isClassTeacher: isClassTeacher,
                    ),
                    const SizedBox(height: 12),

                    // ===== Live & Upcoming Period widget =====
                    Builder(builder: (context) {
                      final routine = ClassAlertService.instance.snapshot.value.routine;
                      int? attClassId;
                      if (routine != null) {
                        for (final e in _routineEntries) {
                          if (e['id'] != routine.id) continue;
                          final classIds = <int>{};
                          for (final s in (e['sections'] as List?) ?? []) {
                            classIds.add(s['class_id'] as int);
                          }
                          for (final g in (e['groups'] as List?) ?? []) {
                            classIds.add(g['class_id'] as int);
                          }
                          for (final c in _classes) {
                            if (classIds.contains(c['id'])) { attClassId = c['id'] as int; break; }
                          }
                          break;
                        }
                      }
                      return ValueListenableBuilder<ClassAlertSnapshot>(
                        valueListenable: ClassAlertService.instance.snapshot,
                        builder: (_, snap, _) => _LiveUpcomingCard(
                          snapshot: snap,
                          nowSec: nowSec,
                          isWeekend: isWeekend,
                          onOpenRoutine: () => _open(context, RoutineScreen(teacher: widget.teacher)),
                          attendanceClassId: attClassId,
                          onTakeAttendance: attClassId != null && isClassTeacher
                              ? () => _open(context, AttendanceScreen(teacher: widget.teacher, initialClassId: attClassId))
                              : null,
                        ),
                      );
                    }),
                    const SizedBox(height: 12),

                    const OfflineSyncBanner(),
                    const SizedBox(height: 12),

                    // ===== Action shortcuts =====
                    _ShortcutsGrid(
                      isClassTeacher: isClassTeacher,
                      onAttendance: isClassTeacher ? () => _open(context, AttendanceScreen(teacher: widget.teacher)) : null,
                      onExams: () => _open(context, ExamsScreen(teacher: widget.teacher)),
                      onHomework: () => _open(context, HomeworkScreen(teacher: widget.teacher)),
                      onRoutine: () => _open(context, RoutineScreen(teacher: widget.teacher)),
                      onStudents: isClassTeacher ? () => _open(context, ClassStudentsScreen(teacher: widget.teacher)) : null,
                      onWhoIsFree: () => _open(context, WhoIsFreeScreen(teacher: widget.teacher)),
                    ),
                    const SizedBox(height: 14),

                    // ===== Today's stats =====
                    Text('আজকের ক্লাস', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 6),
                    Row(children: [
                      _stat(Colors.indigo, 'মোট Period', todayEntries.length),
                      _stat(Colors.green, 'Present', _attCounts['present'] ?? 0),
                      _stat(Colors.red, 'Absent', _attCounts['absent'] ?? 0),
                      _stat(Colors.orange, 'Late', _attCounts['late'] ?? 0),
                    ]),
                    const SizedBox(height: 14),

                    // ===== Daily timeline =====
                    if (!isWeekend) ...[
                      Text('আজকের Time Table', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 6),
                      if (todayEntries.isEmpty)
                        const Card(child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('আজ কোনো scheduled period নেই।', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                        ))
                      else
                        ...todayEntries.map((e) => _TimelineTile(
                              entry: e,
                              nowSec: nowSec,
                              classSummary: _classSummary(e),
                            )),
                    ] else
                      const Card(child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('আজ ছুটির দিন — সময়সূচি নেই।', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                      )),
                    const SizedBox(height: 14),

                    // ===== Exam summary =====
                    Text('Exams', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 6),
                    Row(children: [
                      _stat(Colors.blue, 'মোট Exam', _exams.length),
                      _stat(Colors.teal, 'আমার Test', myCount),
                    ]),
                    const SizedBox(height: 6),
                    Row(children: [
                      _stat(Colors.green, 'Published', pubCount),
                      _stat(Colors.orange, 'Draft', draftCount),
                      _stat(Colors.grey, 'Submitted', submittedCount),
                    ]),
                    const SizedBox(height: 8),
                    for (final e in _exams.take(5))
                      ListTile(
                        dense: true,
                        leading: Icon(e['status'] == 'published' ? Icons.check_circle : Icons.schedule,
                            color: e['status'] == 'published' ? Colors.green : Colors.orange),
                        title: Text(e['name']?.toString() ?? ''),
                        subtitle: Text('${e['subject_name'] ?? ''} • ${e['class_name'] ?? ''} (${e['section'] ?? ''})'),
                        trailing: Text(e['status']?.toString() ?? '', style: TextStyle(
                            fontSize: 12, color: e['status'] == 'published' ? Colors.green : Colors.grey)),
                      ),
                    if (_exams.isEmpty)
                      const Padding(padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('কোনো exam নেই', textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey))),
                  ]),
                ),
    );
  }

  Widget _stat(Color color, String label, int value) {
    return Expanded(child: Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(children: [
        Text(value.toString(), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ]))));
  }
}

// ===================== Greeting hero =====================
class _GreetingHero extends StatelessWidget {
  final dynamic teacher;
  final String greeting;
  final String dateText;
  final bool isClassTeacher;
  const _GreetingHero({required this.teacher, required this.greeting, required this.dateText, required this.isClassTeacher});

  @override
  Widget build(BuildContext context) {
    final name = teacher?['name']?.toString() ?? '';
    final designation = teacher?['designation']?.toString() ?? '';
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1E3A8A), Color(0xFF312E81), Color(0xFF5B21B6)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(18),
      child: Row(children: [
        CircleAvatar(radius: 30, backgroundColor: Colors.white24,
            child: Text(name.isNotEmpty ? name[0] : 'T', style: const TextStyle(fontSize: 26, color: Colors.white))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$greeting 👋', style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 2),
          Text(name, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(
            [if (designation.isNotEmpty) designation, if (isClassTeacher) 'Class Teacher'].join(' • '),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(dateText, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ])),
      ]),
    );
  }
}

// ===================== Live & Upcoming period =====================
class _LiveUpcomingCard extends StatelessWidget {
  final ClassAlertSnapshot snapshot;
  final int nowSec;
  final bool isWeekend;
  final VoidCallback onOpenRoutine;
  final int? attendanceClassId;
  final VoidCallback? onTakeAttendance;
  const _LiveUpcomingCard({required this.snapshot, required this.nowSec,
      required this.isWeekend, required this.onOpenRoutine,
      this.attendanceClassId, this.onTakeAttendance});

  String _fmtSeconds(int s) {
    if (s < 0) s = 0;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
  }

  @override
  Widget build(BuildContext context) {
    final r = snapshot.routine;
    final phase = snapshot.phase;

    if (r == null) {
      return Card(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(Icons.no_sim, color: Colors.grey.shade400),
          const SizedBox(width: 12),
          Expanded(child: Text(isWeekend ? 'আজ ছুটির দিন 🎉' : 'Routine সেট করুন — পরবর্তী ক্লাস এখানে দেখা যাবে।',
              style: const TextStyle(color: Colors.blueGrey))),
          TextButton(onPressed: onOpenRoutine, child: const Text('Routine')),
        ]),
      ));
    }

    final live = phase == 'live';
    final isCountdown = phase == 'countdown';
    final idle = phase == 'idle';
    const liveColor = Color(0xFF16A34A);
    const warnColor = Color(0xFFD97706);

    // progress (0..1) for live period
    double progress = 0;
    if (live) {
      final total = max(1, r.endSec - r.startSec);
      progress = ((nowSec - r.startSec) / total).clamp(0.0, 1.0);
    }

    final Color accent = live ? liveColor : warnColor;
    final String title;
    final String sub;
    if (live) {
      title = 'শেখানো হচ্ছে • ${r.subject}';
      sub = '${r.classLabel} • ${r.slotLabel}${r.room.isNotEmpty ? ' • Room ${r.room}' : ''}';
    } else if (isCountdown) {
      title = 'চলুন প্রস্তুত! • ${r.subject}';
      sub = '${r.classLabel} • ${r.slotLabel}${r.room.isNotEmpty ? ' • Room ${r.room}' : ''}';
    } else if (idle && snapshot.anyToday) {
      title = 'পরবর্তী ক্লাস • ${r.subject}';
      sub = '${r.classLabel} • ${r.slotLabel}${r.room.isNotEmpty ? ' • Room ${r.room}' : ''}';
    } else {
      title = 'পরবর্তী কর্মদিবস • ${r.subject}';
      sub = '${r.classLabel} • ${r.slotLabel}';
    }

    final cnt = snapshot.secondsLeft > 0 ? snapshot.secondsLeft : 0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: accent.withValues(alpha: 0.35), width: 1),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(live ? Icons.sensors : isCountdown ? Icons.hourglass_top : Icons.schedule,
              color: accent, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: accent))),
          if (live)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(999)),
              child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
            )
          else if (isCountdown)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(999)),
              child: Text('${_fmtSeconds(cnt)} বাকি', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
            )
          else
            Text(_fmtSeconds(cnt), style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 8),
        Text(sub, style: const TextStyle(fontSize: 13, color: Colors.black87)),
        const SizedBox(height: 10),
        if (live) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: progress, minHeight: 8, backgroundColor: liveColor.withValues(alpha: 0.15), color: liveColor),
          ),
          const SizedBox(height: 6),
          Text('${_fmtClock(r.startSec)} – ${_fmtClock(r.endSec)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
        if (onTakeAttendance != null) ...[
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: onTakeAttendance,
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: const Text('This Period-এ Attendance নিন'),
          )),
        ],
      ])),
    );
  }

  String _fmtClock(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}

// ===================== Shortcuts grid =====================
class _ShortcutsGrid extends StatelessWidget {
  final bool isClassTeacher;
  final VoidCallback? onAttendance;
  final VoidCallback onExams;
  final VoidCallback onHomework;
  final VoidCallback onRoutine;
  final VoidCallback? onStudents;
  final VoidCallback onWhoIsFree;
  const _ShortcutsGrid({required this.isClassTeacher, this.onAttendance, required this.onExams,
      required this.onHomework, required this.onRoutine, this.onStudents, required this.onWhoIsFree});

  @override
  Widget build(BuildContext context) {
    final items = <({IconData icon, String label, VoidCallback? onTap, Color color})>[
      (icon: Icons.fact_check_outlined, label: 'Attendance', onTap: onAttendance, color: const Color(0xFF16A34A)),
      (icon: Icons.quiz_outlined, label: 'Marks Entry', onTap: onExams, color: const Color(0xFF2563EB)),
      (icon: Icons.calendar_month_outlined, label: 'My Routine', onTap: onRoutine, color: const Color(0xFF7C3AED)),
      (icon: Icons.group_outlined, label: 'My Students', onTap: onStudents, color: const Color(0xFFDB2777)),
      (icon: Icons.edit_note_outlined, label: 'Homework', onTap: onHomework, color: const Color(0xFFD97706)),
      (icon: Icons.waving_hand_outlined, label: 'কে ফ্রি?', onTap: onWhoIsFree, color: const Color(0xFF0891B2)),
    ];
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.92,
      children: items.map((it) {
        return InkWell(
          onTap: it.onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              color: it.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: it.color.withValues(alpha: 0.25)),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(it.icon, color: it.color, size: 28),
              const SizedBox(height: 6),
              Text(it.label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        );
      }).toList(),
    );
  }
}

// ===================== Timeline tile =====================
class _TimelineTile extends StatelessWidget {
  final dynamic entry;
  final int nowSec;
  final String classSummary;
  const _TimelineTile({required this.entry, required this.nowSec, required this.classSummary});

  int _hms(String t) {
    final p = t.split(':');
    if (p.length < 2) return 0;
    return int.parse(p[0]) * 3600 + int.parse(p[1]) * 60 + (p.length > 2 ? int.parse(p[2]) : 0);
  }

  String _fmt(String raw) {
    final s = raw.toString();
    return s.length >= 5 ? s.substring(0, 5) : s;
  }

  @override
  Widget build(BuildContext context) {
    final startSec = _hms(entry['start_time'].toString());
    final endSec = _hms(entry['end_time'].toString());
    final status = nowSec >= endSec
        ? 'Completed'
        : nowSec >= startSec
            ? 'Ongoing'
            : 'Upcoming';
    final Color color = status == 'Completed' ? Colors.green : status == 'Ongoing' ? Colors.red : Colors.blue;
    final IconData icon = status == 'Completed' ? Icons.check_circle : status == 'Ongoing' ? Icons.play_circle : Icons.schedule;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(radius: 20, backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color, size: 22)),
        title: Row(children: [
          Expanded(child: Text('${entry['subject']?['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w500))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
            child: Text(status, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ]),
        subtitle: Text('${_fmt(entry['start_time'].toString())} – ${_fmt(entry['end_time'].toString())}'
            '${classSummary.isNotEmpty ? ' • $classSummary' : ''}${(entry['room']?.toString() ?? '').isNotEmpty ? ' • Room ${entry['room']}' : ''}'),
      ),
    );
  }
}