import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../api.dart';
import '../class_alerts.dart';
import '../widgets/offline_sync_banner.dart';
import 'class_students_screen.dart';
import 'attendance_screen.dart';
import 'exams_screen.dart';
import 'exam_detail_screen.dart';
import 'event_list_screen.dart';
import 'student_progress_screen.dart';
import 'event_detail_screen.dart';
import 'homework_screen.dart';
import 'routine_screen.dart';
import 'who_is_free_screen.dart';

const _days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday'];

class DashboardScreen extends StatefulWidget {
  final dynamic teacher;
  final VoidCallback? onMenu;
  const DashboardScreen({super.key, required this.teacher, this.onMenu});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List _exams = [];
  List _classes = [];
  List _routineEntries = [];
  List _events = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Exam visibility depends on the admin's current lock flag, so never paint
    // a cached exam list before the server confirms that it is still open.
    setState(() {
      _loading = true;
      _error = null;
      _exams = [];
      _events = [];
    });
    List exams = [];
    List routine = _routineEntries;
    List events = [];
    Map<String, dynamic> profile = {};
    void apply() {
      if (!mounted) return;
      setState(() {
        _exams = exams;
        _classes = (profile['classes'] as List? ?? []);
        _routineEntries = routine;
        _events = events;
        _loading = false;
      });
    }

    try {
      await Future.wait([
        Api.getFresh('/teacher/exams').then((r) {
          exams = r is List ? r.where(_isOpenAdminExam).toList() : [];
          apply();
        }),
        Api.loadCachedFirst('/teacher/profile', (r) {
          if (r is Map) {
            profile = r as Map<String, dynamic>;
            apply();
          }
        }),
        Api.getFresh('/teacher/events').then((r) {
          events = r is List ? r.where(_isOpenEvent).toList() : [];
          apply();
        }),
        Api.loadCachedFirst('/routine/teacher/mine', (r) {
          routine = r is List ? r : [];
          unawaited(ClassAlertService.instance.updateRoutines(routine));
          apply();
        }),
      ]);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_exams.isEmpty && _routineEntries.isEmpty) {
          _error = e.toString().replaceFirst('Exception: ', '');
        }
        _loading = false;
      });
    }
  }

  bool _isEnabled(dynamic value) => value == true || value == 1 || value == '1';

  bool _isOpenAdminExam(dynamic item) {
    if (item is! Map || item['status'] == 'published') return false;
    final flag = item['entry_open'];
    if (flag == false || flag == 0 || flag == '0') return false;
    // Older teacher-created exams may not have an event or explicit flag.
    return flag != null || item['event_id'] == null;
  }

  bool _isOpenEvent(dynamic item) =>
      item is Map &&
      _isEnabled(item['entry_open']) &&
      !_isEnabled(item['is_published']);

  int _schoolDayOf(DateTime d) {
    if (d.weekday == 7) return 0;
    return d.weekday;
  }

  String _monthName(int m) => const [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][m];

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
    final isClassTeacher = _classes.isNotEmpty;
    final dayNames = const [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
    ];
    final todayName = sd < dayNames.length ? dayNames[sd] : '';
    final todayClasses = _routineEntries.where((e) {
      final value = e['day'] ?? e['day_name'] ?? e['weekday'] ?? '';
      return value is num
          ? value.toInt() == sd
          : value.toString().toLowerCase() == todayName.toLowerCase();
    }).length;

    // ===== Admin-created exams (open for marking, grouped & actionable) =====
    final adminExams = _exams.where((e) => e['source'] == 'admin').toList();
    // My pending: my assigned subjects (or own tests), not published.
    final myPending = adminExams
        .where(
          (e) =>
              (e['status'] ?? 'draft') != 'published' &&
              (e['subject_mine'] == 1 || e['subject_mine'] == true),
        )
        .toList();
    final entryClosed = myPending
        .where((e) => ((e['entry_open'] as num?)?.toInt() ?? 1) == 0)
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFFEEF0F8),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  _WorldHero(
                    teacher: widget.teacher,
                    greeting: _greeting(today),
                    dateText:
                        '${today.day} ${_monthName(today.month)}, ${today.year}',
                    isClassTeacher: isClassTeacher,
                    pendingCount: myPending.length,
                    truantCount: 0,
                  ),
                  const SizedBox(height: 12),
                  _TodayClassesCard(
                    count: todayClasses,
                    isWeekend: isWeekend,
                    onRoutine: () =>
                        _open(context, RoutineScreen(teacher: widget.teacher)),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'দ্রুত শুরু করুন',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: Color(0xFF18213A),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _QuickAction(
                          icon: Icons.fact_check_rounded,
                          title: 'হাজিরা',
                          tint: const Color(0xFF574CE8),
                          onTap: isClassTeacher
                              ? () => _open(
                                  context,
                                  AttendanceScreen(teacher: widget.teacher),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _QuickAction(
                          icon: Icons.calendar_month_rounded,
                          title: 'রুটিন',
                          tint: const Color(0xFF7868EE),
                          onTap: () => _open(
                            context,
                            RoutineScreen(teacher: widget.teacher),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _QuickAction(
                          icon: Icons.edit_note_rounded,
                          title: 'নম্বর দিন',
                          tint: const Color(0xFF3D4A75),
                          onTap: () => _open(
                            context,
                            ExamsScreen(teacher: widget.teacher),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.workspace_premium_outlined),
                      label: const Text('প্রকাশিত পরীক্ষার ফল দেখুন'),
                      onPressed: () => _open(
                        context,
                        EventListScreen(
                          teacher: widget.teacher,
                          publishedOnly: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // ===== Live & Upcoming Period widget =====
                  Builder(
                    builder: (context) {
                      final routine =
                          ClassAlertService.instance.snapshot.value.routine;
                      int? attClassId;
                      int? progressClassId;
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
                          if (classIds.isNotEmpty)
                            progressClassId = classIds.first;
                          for (final c in _classes) {
                            if (classIds.contains(c['id'])) {
                              attClassId = c['id'] as int;
                              break;
                            }
                          }
                          break;
                        }
                      }
                      final nowSec =
                          DateTime.now().hour * 3600 +
                          DateTime.now().minute * 60 +
                          DateTime.now().second;
                      return ValueListenableBuilder<ClassAlertSnapshot>(
                        valueListenable: ClassAlertService.instance.snapshot,
                        builder: (_, snap, _) => _LiveUpcomingCard(
                          snapshot: snap,
                          nowSec: nowSec,
                          isWeekend: isWeekend,
                          onOpenRoutine: () => _open(
                            context,
                            RoutineScreen(teacher: widget.teacher),
                          ),
                          attendanceClassId: attClassId,
                          progressClassId: progressClassId,
                          onOpenStudents: progressClassId == null
                              ? null
                              : () => _open(
                                  context,
                                  StudentProgressScreen(
                                    classId: progressClassId!,
                                    classLabel: routine!.classLabel,
                                    subjectName: routine.subject,
                                  ),
                                ),
                          onTakeAttendance: attClassId != null && isClassTeacher
                              ? () => _open(
                                  context,
                                  AttendanceScreen(
                                    teacher: widget.teacher,
                                    initialClassId: attClassId,
                                  ),
                                )
                              : null,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),

                  const OfflineSyncBanner(),
                  const SizedBox(height: 12),

                  // ===== মার্কস এন্ট্রি — আমার করণীয় (Admin Created Exams) =====
                  _MarkingTasksCard(
                    myPending: myPending,
                    entryClosed: entryClosed,
                    onOpenExam: (e) => _open(
                      context,
                      ExamDetailScreen(
                        examId: e['id'] as int,
                        examName: '${e['name']}',
                      ),
                    ),
                    onOpenAll: () =>
                        _open(context, ExamsScreen(teacher: widget.teacher)),
                  ),
                  const SizedBox(height: 14),

                  _SecondaryToolsCard(
                    onHomework: () =>
                        _open(context, HomeworkScreen(teacher: widget.teacher)),
                    onStudents: isClassTeacher
                        ? () => _open(
                            context,
                            ClassStudentsScreen(teacher: widget.teacher),
                          )
                        : null,
                    onFree: () => _open(
                      context,
                      WhoIsFreeScreen(teacher: widget.teacher),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ===== Class truancy watch (today) =====
                  _TruancyWatchCard(
                    dateText:
                        '${today.day} ${_monthName(today.month)}, ${today.year}',
                  ),
                  const SizedBox(height: 14),
                ],
              ),
            ),
    );
  }
}

// ===================== Class truancy watch (today) =====================
// Menu-first home shows SAFETY status, not raw exam lists: today's truancy
// count pulled from the FSM window summary. Zero truants = calm green;
// any truant = red alert card (tap → attendance screen).
class _TruancyWatchCard extends StatelessWidget {
  final String dateText;
  const _TruancyWatchCard({required this.dateText});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Api.get('/teacher/attendance/window'),
      builder: (_, snap) {
        int truants = 0;
        if (snap.hasData && snap.data is Map) {
          for (final f in ((snap.data as Map)['finals'] as List?) ?? const []) {
            if (f['state'] == 'TRUANT_UNAUTHORIZED') {
              truants += (f['count'] as num?)?.toInt() ?? 0;
            }
          }
        }
        final calm = truants == 0;
        return Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: calm
                  ? [const Color(0xFFECFDF5), const Color(0xFFD1FAE5)]
                  : [const Color(0xFFFEF2F2), const Color(0xFFFECACA)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: calm ? Colors.green.shade200 : Colors.red.shade300,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: calm ? Colors.green : Colors.red,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  calm
                      ? Icons.verified_user_outlined
                      : Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      calm ? 'সবাই নিরাপদে আছে ✅' : '$truants জন পলাতক! 🚨',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: calm
                            ? Colors.green.shade900
                            : Colors.red.shade800,
                      ),
                    ),
                    Text(
                      '$dateText • ৫ম পিরিয়ড যাচাই',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: calm
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ===================== Marking tasks (admin-created, awaiting MY entry) =====================
// Design: teacher-এর দৈনন্দিন করণীয় এক নজরে —
//  1. কোন admin exam-এ আমার entry বাকি (deadline + entry open/close সহ),
//  2. প্রতিটিতে tap করলে সরাসরি marks entry,
//  3. entry বন্ধ হলে কেন বন্ধ (admin revoke / deadline) স্পষ্ট।
class _MarkingTasksCard extends StatelessWidget {
  final List myPending;
  final int entryClosed;
  final void Function(dynamic e) onOpenExam;
  final VoidCallback onOpenAll;
  const _MarkingTasksCard({
    required this.myPending,
    required this.entryClosed,
    required this.onOpenExam,
    required this.onOpenAll,
  });

  String _fmtDeadline(dynamic dl) {
    if (dl == null) return '';
    final s = dl.toString().replaceAll('T', ' ');
    return s.length >= 16 ? s.substring(0, 16) : s;
  }

  bool _overdue(dynamic dl) {
    if (dl == null) return false;
    try {
      return DateTime.now().isAfter(
        DateTime.parse(dl.toString().replaceAll(' ', 'T')),
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF6A5FE8).withValues(alpha: 0.22),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF574CE8).withValues(alpha: 0.09),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF5148E5), Color(0xFF8276F2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF574CE8).withValues(alpha: .22),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.edit_document,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'মার্কস এন্ট্রি — আমার করণীয়',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              if (myPending.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF5148E5), Color(0xFF7468EE)],
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${myPending.length} বাকি',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            myPending.isEmpty
                ? 'সব entry সম্পূর্ণ — কোনো pending marking নেই। 🎉'
                : 'Admin unlock করা আপনার subject-এর পরীক্ষায় সরাসরি নম্বর দিন।',
            style: TextStyle(fontSize: 12.5, color: Colors.blueGrey.shade600),
          ),
          if (entryClosed > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '$entryClosed টি exam-এ admin entry বন্ধ রেখেছে।',
                style: const TextStyle(fontSize: 12, color: Colors.red),
              ),
            ),
          const SizedBox(height: 8),
          for (final e in myPending.take(5))
            Builder(
              builder: (_) {
                final open = ((e['entry_open'] as num?)?.toInt() ?? 1) == 1;
                final closed = !open || _overdue(e['entry_deadline']);
                final dl = e['entry_deadline']?.toString();
                return InkWell(
                  onTap: closed ? null : () => onOpenExam(e),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: closed
                          ? Colors.grey.shade100
                          : const Color(0xFFF3F1FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: closed
                            ? Colors.grey.shade300
                            : const Color(0xFFDED9FF),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          closed
                              ? Icons.lock_outline
                              : Icons.pending_actions_outlined,
                          color: closed ? Colors.grey : const Color(0xFF5C50E8),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${e['name']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${e['subject_name'] ?? ''} • ${e['class_name'] ?? ''}'
                                '${dl != null && dl.isNotEmpty ? ' • ⏰ ${_fmtDeadline(dl)} পর্যন্ত' : ''}'
                                '${closed ? (open ? ' • ⏰ Deadline পার' : ' • 🔒 Admin বন্ধ') : ''}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: closed
                                      ? Colors.red.shade700
                                      : Colors.blueGrey.shade600,
                                ),
                                maxLines: 2,
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 14,
                          color: closed ? Colors.grey : const Color(0xFF5C50E8),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: onOpenAll,
              icon: const Icon(Icons.quiz_outlined, size: 17),
              label: const Text(
                'সব Exam দেখুন',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===================== Running event coverage tile =====================
// Test-Exam year rule: event rows show "Test Exam 2025" (year included);
// tap opens the subject-wise breakdown (entry per subject).
class _EventCoverageTile extends StatelessWidget {
  final dynamic event;
  final VoidCallback onTap;
  const _EventCoverageTile({required this.event, required this.onTap});

  String get _titleYear {
    final name = '${event['name'] ?? ''}';
    final year = event['year']?.toString() ?? '';
    if (year.isNotEmpty && !name.contains(year)) return '$name $year';
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final classes = (event['my_classes'] as List?) ?? const [];
    int stuDone = 0, stuTotal = 0, subDone = 0, subTotal = 0;
    for (final c in classes) {
      stuDone += (c['students_with_marks'] as num?)?.toInt() ?? 0;
      stuTotal += (c['student_count'] as num?)?.toInt() ?? 0;
      subDone += (c['subjects_with_marks'] as num?)?.toInt() ?? 0;
      subTotal += (c['subject_count'] as num?)?.toInt() ?? 0;
    }
    final pct = subTotal > 0 ? (subDone / subTotal).clamp(0.0, 1.0) : 0.0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.blue.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _titleYear,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (event['is_published'] == 1 || event['is_published'] == true)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Published',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade800,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
              'tap করলে subject-wise entry দেখা যাবে',
              style: TextStyle(fontSize: 11, color: Colors.black45),
            ),
            const SizedBox(height: 6),
            Text(
              '📚 $subDone/$subTotal subject  •  👥 $stuDone/$stuTotal student',
              style: TextStyle(
                fontSize: 12,
                color: Colors.blueGrey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 6,
                backgroundColor: Colors.blue.withValues(alpha: 0.12),
                color: Colors.blue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===================== World-class hero + workspace menu =====================
// Menu-first rationale (Fitts + Hick + Miller 7±2):
//  - ONE navigation surface (no drawer/bottom-nav/top-tab triple mapping).
//  - 6 workspace cards (≤7 chunks) ordered by daily workflow:
//    হাজিরা → মার্কস → Homework → রুটিন → Students → ফ্রি শিক্ষক।
//  - Each card carries LIVE status (pending count / today's count), so the
//    teacher never opens a module just to discover "nothing to do".
//  - Premium depth: layered gradient hero, glass stat chips, per-card accent
//    gradient icon wells + soft colored shadows.
class _WorldHero extends StatelessWidget {
  final dynamic teacher;
  final String greeting;
  final String dateText;
  final bool isClassTeacher;
  final int pendingCount;
  final int truantCount;
  const _WorldHero({
    required this.teacher,
    required this.greeting,
    required this.dateText,
    required this.isClassTeacher,
    required this.pendingCount,
    required this.truantCount,
  });

  @override
  Widget build(BuildContext context) {
    final name = teacher?['name']?.toString() ?? '';
    final designation = teacher?['designation']?.toString() ?? '';
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5148E5), Color(0xFF675DEB), Color(0xFF8676F4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6659E8).withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.45),
                    width: 2,
                  ),
                ),
                child: CircleAvatar(
                  radius: 27,
                  backgroundColor: Colors.white.withValues(alpha: 0.16),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'T',
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '$greeting 👋',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (isClassTeacher) ...[
                          const SizedBox(width: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                              ),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: const Text(
                              'Class Teacher',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      [
                        if (designation.isNotEmpty) designation,
                        dateText,
                      ].join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _GlassChip(
                icon: Icons.edit_document,
                label: pendingCount == 0
                    ? 'Entry সম্পূর্ণ 🎉'
                    : '$pendingCount টি entry বাকি',
                strong: pendingCount > 0,
              ),
              const SizedBox(width: 8),
              if (truantCount > 0)
                _GlassChip(
                  icon: Icons.warning_amber_rounded,
                  label: '$truantCount জন পলাতক!',
                  strong: true,
                  alert: true,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TodayClassesCard extends StatelessWidget {
  final int count;
  final bool isWeekend;
  final VoidCallback onRoutine;
  const _TodayClassesCard({
    required this.count,
    required this.isWeekend,
    required this.onRoutine,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onRoutine,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFF0EEFF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.calendar_month_rounded,
                color: Color(0xFF5C50E8),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isWeekend ? 'আজ ছুটির দিন' : 'আজ আপনার $count টি ক্লাস',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF18213A),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    count == 0
                        ? 'রুটিন দেখতে ট্যাপ করুন'
                        : 'আজকের সময়সূচি দেখুন',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blueGrey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 15,
              color: Color(0xFF8B8FA3),
            ),
          ],
        ),
      ),
    ),
  );
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color tint;
  final VoidCallback? onTap;
  const _QuickAction({
    required this.icon,
    required this.title,
    required this.tint,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onTap == null ? .48 : 1,
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 5),
          child: Column(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: tint),
              ),
              const SizedBox(height: 7),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF26304A),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SecondaryToolsCard extends StatelessWidget {
  final VoidCallback onHomework;
  final VoidCallback? onStudents;
  final VoidCallback onFree;
  const _SecondaryToolsCard({
    required this.onHomework,
    required this.onStudents,
    required this.onFree,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'অন্যান্য কাজ',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Color(0xFF18213A),
          ),
        ),
        const SizedBox(height: 5),
        _ToolRow(
          icon: Icons.menu_book_rounded,
          label: 'আজকের পড়া',
          onTap: onHomework,
        ),
        if (onStudents != null)
          _ToolRow(
            icon: Icons.groups_rounded,
            label: 'শিক্ষার্থী তালিকা',
            onTap: onStudents!,
          ),
        _ToolRow(
          icon: Icons.access_time_rounded,
          label: 'কে ফ্রি?',
          onTap: onFree,
        ),
      ],
    ),
  );
}

class _ToolRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ToolRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    leading: Icon(icon, color: const Color(0xFF6559E9)),
    title: Text(
      label,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
    ),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}

class _GlassChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool strong;
  final bool alert;
  const _GlassChip({
    required this.icon,
    required this.label,
    this.strong = false,
    this.alert = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: alert
            ? const Color(0xFFDC2626).withValues(alpha: 0.9)
            : Colors.white.withValues(alpha: strong ? 0.22 : 0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceMenu extends StatelessWidget {
  final bool isClassTeacher;
  final int pendingMarks;
  final VoidCallback onExams;
  final VoidCallback? onAttendance;
  final VoidCallback onHomework;
  final VoidCallback onRoutine;
  final VoidCallback? onStudents;
  final VoidCallback onWhoIsFree;
  const _WorkspaceMenu({
    required this.isClassTeacher,
    required this.pendingMarks,
    required this.onExams,
    required this.onAttendance,
    required this.onHomework,
    required this.onRoutine,
    required this.onStudents,
    required this.onWhoIsFree,
  });

  @override
  Widget build(BuildContext context) {
    final cards = [
      _WsCard(
        icon: Icons.fact_check_rounded,
        title: 'হাজিরা',
        sub: 'সকাল 10:15–11:10 • P5 2:00–2:45',
        gradient: const [Color(0xFF0D9488), Color(0xFF0F766E)],
        status: isClassTeacher ? null : 'শুধু class teacher',
        enabled: isClassTeacher,
        onTap: onAttendance,
      ),
      _WsCard(
        icon: Icons.quiz_rounded,
        title: 'Exams ও মার্কস',
        sub: pendingMarks > 0
            ? '$pendingMarks টি entry বাকি'
            : 'সব entry সম্পূর্ণ',
        gradient: const [Color(0xFFF59E0B), Color(0xFFD97706)],
        badge: pendingMarks > 0 ? '$pendingMarks' : null,
        onTap: onExams,
      ),
      _WsCard(
        icon: Icons.edit_note_rounded,
        title: 'আজকের পড়া',
        sub: 'আজ কী পড়িয়েছেন লিখুন ও অভিভাবককে জানান',
        gradient: const [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
        onTap: onHomework,
      ),
      _WsCard(
        icon: Icons.calendar_month_rounded,
        title: 'রুটিন',
        sub: 'সাপ্তাহিক ক্লাস সূচি',
        gradient: const [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
        onTap: onRoutine,
      ),
      _WsCard(
        icon: Icons.group_rounded,
        title: 'Students',
        sub: isClassTeacher ? 'আমার class-এর শিক্ষার্থী' : 'শুধু class teacher',
        gradient: const [Color(0xFF10B981), Color(0xFF047857)],
        enabled: isClassTeacher,
        onTap: onStudents,
      ),
      _WsCard(
        icon: Icons.access_time_rounded,
        title: 'কে ফ্রি?',
        sub: 'এই মুহূর্তে ফাঁকা শিক্ষক',
        gradient: const [Color(0xFFEC4899), Color(0xFFBE1858)],
        onTap: onWhoIsFree,
      ),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.55,
      ),
      itemCount: cards.length,
      itemBuilder: (_, i) => cards[i],
    );
  }
}

class _WsCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  final List<Color> gradient;
  final String? badge;
  final String? status;
  final bool enabled;
  final VoidCallback? onTap;
  const _WsCard({
    required this.icon,
    required this.title,
    required this.sub,
    required this.gradient,
    this.badge,
    this.status,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: gradient[0].withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: gradient[0].withValues(alpha: enabled ? 0.14 : 0.04),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: enabled
                        ? gradient
                        : [Colors.grey.shade300, Colors.grey.shade400],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: [
                    BoxShadow(
                      color: gradient[0].withValues(
                        alpha: enabled ? 0.35 : 0.0,
                      ),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 21),
              ),
              const Spacer(),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const Spacer(),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: enabled ? Colors.grey.shade900 : Colors.grey,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            status ?? sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: enabled ? Colors.blueGrey.shade500 : Colors.grey,
            ),
          ),
        ],
      ),
    );
    if (!enabled || onTap == null) {
      return Opacity(opacity: 0.75, child: card);
    }
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: card,
      ),
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
  final int? progressClassId;
  final VoidCallback? onOpenStudents;
  const _LiveUpcomingCard({
    required this.snapshot,
    required this.nowSec,
    required this.isWeekend,
    required this.onOpenRoutine,
    this.attendanceClassId,
    this.onTakeAttendance,
    this.progressClassId,
    this.onOpenStudents,
  });

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
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              color: Colors.grey.shade400,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isWeekend
                    ? 'আজ ছুটির দিন 🎉'
                    : 'Routine সেট করুন — পরবর্তী ক্লাস এখানে দেখা যাবে।',
                style: const TextStyle(color: Colors.blueGrey, fontSize: 13),
              ),
            ),
            TextButton(onPressed: onOpenRoutine, child: const Text('Routine')),
          ],
        ),
      );
    }

    final live = phase == 'live';
    final isCountdown = phase == 'countdown';
    final idle = phase == 'idle';
    const liveColor = Color(0xFF16A34A);
    const warnColor = Color(0xFFD97706);

    double progress = 0;
    if (live) {
      final total = max(1, r.endSec - r.startSec);
      progress = ((nowSec - r.startSec) / total).clamp(0.0, 1.0);
    }

    const Color cardColor = Color(0xFF202A49);
    final Color accent = live
        ? const Color(0xFFB9F36B)
        : const Color(0xFFFFD76A);
    final String title;
    final String sub;
    if (live) {
      title = 'চলমান ক্লাস • ${r.subject}';
      sub =
          '${r.classLabel} • ${r.slotLabel}${r.room.isNotEmpty ? ' • Room ${r.room}' : ''}';
    } else if (isCountdown) {
      title = 'প্রস্তুত হোন! • ${r.subject}';
      sub =
          '${r.classLabel} • ${r.slotLabel}${r.room.isNotEmpty ? ' • Room ${r.room}' : ''}';
    } else if (idle && snapshot.anyToday) {
      title = 'পরবর্তী ক্লাস • ${r.subject}';
      sub =
          '${r.classLabel} • ${r.slotLabel}${r.room.isNotEmpty ? ' • Room ${r.room}' : ''}';
    } else {
      title = 'পরবর্তী কর্মদিবস • ${r.subject}';
      sub = '${r.classLabel} • ${r.slotLabel}';
    }

    final cnt = snapshot.secondsLeft > 0 ? snapshot.secondsLeft : 0;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  live
                      ? Icons.sensors_rounded
                      : isCountdown
                      ? Icons.hourglass_top_rounded
                      : Icons.schedule_rounded,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
                ),
              ),
              if (live)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'LIVE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else if (isCountdown)
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
                    '${_fmtSeconds(cnt)} বাকি',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else
                Text(
                  _fmtSeconds(cnt),
                  style: TextStyle(color: accent, fontWeight: FontWeight.bold),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            sub,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          if (progressClassId != null && onOpenStudents != null) ...[
            const SizedBox(height: 5),
            InkWell(
              onTap: live ? onOpenStudents : null,
              child: Text(
                live
                    ? 'শিক্ষার্থীর তথ্য দেখতে ট্যাপ করুন  ›'
                    : 'শিক্ষার্থীর তথ্য চলমান class-এ খুলবে',
                style: TextStyle(
                  color: accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (live) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                backgroundColor: liveColor.withValues(alpha: 0.12),
                color: liveColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${_fmtClock(r.startSec)} – ${_fmtClock(r.endSec)}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (onTakeAttendance != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0B6B4F),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: onTakeAttendance,
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: const Text(
                  'This Period-এ Attendance নিন',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _fmtClock(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}
