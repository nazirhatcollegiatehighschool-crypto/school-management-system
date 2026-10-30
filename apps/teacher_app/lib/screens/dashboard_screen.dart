import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../api.dart';
import '../class_alerts.dart';
import '../routine_roster_targets.dart';
import 'class_students_screen.dart';
import 'attendance_screen.dart';
import 'exams_screen.dart';
import 'exam_detail_screen.dart';
import 'event_list_screen.dart';
import 'student_progress_screen.dart';
import 'homework_screen.dart';
import 'written_complaint_screen.dart';
import 'routine_screen.dart';
import 'who_is_free_screen.dart';

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
    });
    List exams = [];
    List routine = _routineEntries;
    Map<String, dynamic> profile = {};
    void apply() {
      if (!mounted) return;
      setState(() {
        _exams = exams;
        _classes = (profile['classes'] as List? ?? []);
        _routineEntries = routine;
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

  bool _isOpenAdminExam(dynamic item) {
    if (item is! Map || item['status'] == 'published') return false;
    final flag = item['entry_open'];
    if (flag == false || flag == 0 || flag == '0') return false;
    // Older teacher-created exams may not have an event or explicit flag.
    return flag != null || item['event_id'] == null;
  }

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

  Future<RoutineRosterTarget?> _chooseRoutineTarget(
    List<RoutineRosterTarget> targets, {
    required String title,
  }) {
    if (targets.length == 1) return Future.value(targets.first);
    if (targets.isEmpty) return Future.value(null);
    return showDialog<RoutineRosterTarget>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(title),
        children: [
          for (final target in targets)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, target),
              child: Text(target.label),
            ),
        ],
      ),
    );
  }

  Future<void> _openLiveStudents(
    RoutineAlert routine,
    List<RoutineRosterTarget> targets,
  ) async {
    final target = await _chooseRoutineTarget(
      targets,
      title: 'চলমান class-এর section বাছুন',
    );
    if (!mounted || target == null) return;
    _open(
      context,
      StudentProgressScreen(
        classId: target.classId,
        classLabel: target.label,
        subjectName: routine.subject,
        showUniform: false,
      ),
    );
  }

  Future<void> _openLiveAttendance(List<RoutineRosterTarget> targets) async {
    final target = await _chooseRoutineTarget(
      targets,
      title: 'চলমান class-এর attendance নিন',
    );
    if (!mounted || target == null) return;
    _open(
      context,
      AttendanceScreen(teacher: widget.teacher, initialClassId: target.classId),
    );
  }

  Future<void> _openUniformReport() async {
    if (_classes.isEmpty) return;
    final classId = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Uniform report — class বাছুন'),
        children: [
          for (final c in _classes)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, int.tryParse('${c['id']}')),
              child: Text(
                '${c['name'] ?? c['class_name'] ?? 'Class'} '
                '${c['section'] ?? c['group_name'] ?? ''}',
              ),
            ),
        ],
      ),
    );
    if (!mounted || classId == null) return;
    final classRow = _classes.firstWhere(
      (c) => int.tryParse('${c['id']}') == classId,
    );
    var subjectName = 'Class Teacher';
    for (final entry in _routineEntries) {
      final sectionMatch = (entry['sections'] as List? ?? []).any(
        (section) => int.tryParse('${section['class_id']}') == classId,
      );
      final groupMatch = (entry['groups'] as List? ?? []).any(
        (group) => int.tryParse('${group['class_id']}') == classId,
      );
      if (sectionMatch || groupMatch) {
        subjectName =
            '${entry['subject'] ?? entry['subject_name'] ?? subjectName}';
        break;
      }
    }
    final section = classRow['section'] ?? classRow['group_name'] ?? '';
    _open(
      context,
      StudentProgressScreen(
        classId: classId,
        classLabel:
            '${classRow['name'] ?? classRow['class_name'] ?? 'Class'} $section',
        subjectName: subjectName,
        showUniform: false,
        uniformOnly: true,
      ),
    );
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
                          title: 'Marks entry',
                          tint: const Color(0xFF3D4A75),
                          onTap: () => _open(
                            context,
                            ExamsScreen(teacher: widget.teacher),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (isClassTeacher) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _QuickAction(
                            icon: Icons.checkroom_rounded,
                            title: 'Uniform report',
                            tint: const Color(0xFF0F8B72),
                            onTap: _openUniformReport,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _QuickAction(
                            icon: Icons.report_gmailerrorred_rounded,
                            title: 'লিখিত অভিযোগ',
                            tint: const Color(0xFFCA4650),
                            onTap: () =>
                                _open(context, const WrittenComplaintScreen()),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(child: SizedBox()),
                      ],
                    ),
                  ],
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
                  ValueListenableBuilder<ClassAlertSnapshot>(
                    valueListenable: ClassAlertService.instance.snapshot,
                    builder: (context, snap, _) {
                      final routine = snap.routine;
                      final routineEntry = routineEntryForId(
                        _routineEntries,
                        routine?.id,
                      );
                      final targets = routineRosterTargets(routineEntry);
                      final teacherClassIds = _classes
                          .map((classRow) => int.tryParse('${classRow['id']}'))
                          .whereType<int>()
                          .toSet();
                      final attendanceTargets = targets
                          .where(
                            (target) =>
                                teacherClassIds.contains(target.classId),
                          )
                          .toList();
                      final now = DateTime.now();
                      final nowSec =
                          now.hour * 3600 + now.minute * 60 + now.second;
                      return _LiveUpcomingCard(
                        snapshot: snap,
                        nowSec: nowSec,
                        isWeekend: isWeekend,
                        onOpenRoutine: () => _open(
                          context,
                          RoutineScreen(teacher: widget.teacher),
                        ),
                        hasStudentTargets: targets.isNotEmpty,
                        onOpenStudents: routine == null || targets.isEmpty
                            ? null
                            : () => _openLiveStudents(routine, targets),
                        onTakeAttendance:
                            isClassTeacher && attendanceTargets.isNotEmpty
                            ? () => _openLiveAttendance(attendanceTargets)
                            : null,
                      );
                    },
                  ),
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

class _WorldHero extends StatelessWidget {
  final dynamic teacher;
  final String greeting;
  final String dateText;
  final bool isClassTeacher;
  final int truantCount;
  const _WorldHero({
    required this.teacher,
    required this.greeting,
    required this.dateText,
    required this.isClassTeacher,
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
          if (truantCount > 0) ...[
            const SizedBox(height: 12),
            _GlassChip(
              icon: Icons.warning_amber_rounded,
              label: '$truantCount জন পলাতক!',
              strong: true,
              alert: true,
            ),
          ],
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
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFE8EDF3)),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF102A43).withValues(alpha: .045),
          blurRadius: 18,
          offset: const Offset(0, 7),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(3, 1, 3, 11),
          child: Text(
            'দ্রুত সেবা',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: Color(0xFF18213A),
            ),
          ),
        ),
        _SecondaryFeatureCard(
          icon: Icons.menu_book_rounded,
          title: 'আজকের পড়া',
          subtitle: 'আজকের পাঠ লিখুন ও অভিভাবককে জানান',
          color: const Color(0xFF7654D8),
          softColor: const Color(0xFFF1EDFF),
          onTap: onHomework,
        ),
        if (onStudents != null) ...[
          const SizedBox(height: 9),
          _SecondaryFeatureCard(
            icon: Icons.groups_rounded,
            title: 'শিক্ষার্থী তালিকা',
            subtitle: 'আমার class-এর শিক্ষার্থী দেখুন',
            color: const Color(0xFF3155A6),
            softColor: const Color(0xFFEDF2FF),
            onTap: onStudents!,
          ),
        ],
        const SizedBox(height: 9),
        _SecondaryFeatureCard(
          icon: Icons.access_time_filled_rounded,
          title: 'Resting Teacher',
          subtitle: 'দিন ও period অনুযায়ী বিশ্রামে থাকা শিক্ষক দেখুন',
          color: const Color(0xFF0B8A78),
          softColor: const Color(0xFFE8F7F3),
          onTap: onFree,
        ),
      ],
    ),
  );
}

class _SecondaryFeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Color softColor;
  final VoidCallback onTap;

  const _SecondaryFeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.softColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        constraints: const BoxConstraints(minHeight: 82),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: .19)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: softColor,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: color, size: 25),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11.5,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: softColor,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.arrow_forward_rounded, color: color, size: 17),
            ),
          ],
        ),
      ),
    ),
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

class _LiveUpcomingCard extends StatelessWidget {
  final ClassAlertSnapshot snapshot;
  final int nowSec;
  final bool isWeekend;
  final VoidCallback onOpenRoutine;
  final VoidCallback? onTakeAttendance;
  final bool hasStudentTargets;
  final VoidCallback? onOpenStudents;
  const _LiveUpcomingCard({
    required this.snapshot,
    required this.nowSec,
    required this.isWeekend,
    required this.onOpenRoutine,
    this.onTakeAttendance,
    this.hasStudentTargets = false,
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
          if (hasStudentTargets && onOpenStudents != null) ...[
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
