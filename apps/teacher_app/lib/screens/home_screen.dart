import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:share_plus/share_plus.dart';
import '../api.dart';
import '../class_alerts.dart';
import '../config.dart';
import '../fcm_service.dart';
import 'dashboard_screen.dart';
import 'exams_screen.dart';
import 'exam_detail_screen.dart';
import 'attendance_screen.dart';
import 'homework_screen.dart';
import 'class_students_screen.dart';
import 'profile_screen.dart';
import 'promotion_screen.dart';
import 'routine_screen.dart';
import '../widgets/offline_sync_banner.dart';
import '../update_check.dart';

class HomeScreen extends StatefulWidget {
  final dynamic teacher;
  const HomeScreen({super.key, required this.teacher});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  final _examsKey = GlobalKey<ExamsScreenState>();
  static bool _updateCheckedThisSession = false;

  @override
  void initState() {
    super.initState();
    _wirePush();
    ClassAlertService.instance.start();
    _loadRoutines();
    // Silent update check for already-logged-in users (login screen check
    // only runs on fresh login, so without this they never get prompted).
    if (!_updateCheckedThisSession) {
      _updateCheckedThisSession = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) checkForUpdate(context, 'teacher');
      });
    }
  }

  Future<void> _loadRoutines() async {
    try {
      final r = await Api.get('/routine/teacher/mine');
      if (r is List && r.isNotEmpty) {
        await ClassAlertService.instance.updateRoutines(r);
      }
    } catch (_) {
      // routine alert scheduling is best-effort; the dashboard card can retry
    }
    // Warm the permanent on-device routine cache in the background so the
    // Routine screen paints instantly (no spinner) when opened.
    Api.refreshCache('/routine/teacher/mine');
    Api.refreshCache('/routine/teacher/subjects');
    Api.refreshCache('/routine/slots');
  }

  void _wirePush() {
    // NOTE: onMessageOpenedApp is already registered inside handleForegroundMessages
    // (fcm_service.dart). Registering it again here would double-navigate on tap.
    handleForegroundMessages(context, _onNotificationTap);
    FirebaseMessaging.instance.getInitialMessage().then((m) { if (m != null) _onNotificationTap(m.data); });
  }

  void _onNotificationTap(Map<String, dynamic> data) {
    final examId = data['exam_id'];
    if (examId != null && examId.toString().isNotEmpty) {
      final examName = data['exam_name'] ?? 'Exam';
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ExamDetailScreen(examId: int.tryParse(examId.toString()) ?? 0, examName: examName.toString())));
      return;
    }
    setState(() => _tab = 1);
    WidgetsBinding.instance.addPostFrameCallback((_) => _examsKey.currentState?.reload());
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(teacher: widget.teacher),
      ExamsScreen(teacher: widget.teacher, key: _examsKey),
      AttendanceScreen(teacher: widget.teacher),
      HomeworkScreen(teacher: widget.teacher),
      RoutineScreen(teacher: widget.teacher),
      ClassStudentsScreen(teacher: widget.teacher),
      ProfileScreen(teacher: widget.teacher),
      PromotionScreen(),
    ];
    final t = widget.teacher;
    final tName = (t is Map ? t['name']?.toString() : null) ?? 'Teacher';
    return Scaffold(
      // ===== Top menu bar: brand + pending-marks shortcut + global actions =====
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: _TeacherTopBar(
          teacherName: tName,
          activeTab: _tab,
          onBrandTap: () => setState(() => _tab = 0),
          onOpenExams: () => setState(() => _tab = 1),
          onOpenProfile: () => setState(() => _tab = 6),
          onSelectTab: (i) => setState(() => _tab = i),
        ),
      ),
      body: Column(
        children: [
          const OfflineSyncBanner(compact: true),
          Expanded(child: screens[_tab]),
        ],
      ),
    );
  }
}

// ===================== Top menu bar =====================
// Brand (tap = dashboard) + quick Exams shortcut + profile avatar.
// Persistent across all 8 tabs so entry/deadline work is one tap away.
class _TeacherTopBar extends StatelessWidget {
  final String teacherName;
  final int activeTab;
  final VoidCallback onBrandTap;
  final VoidCallback onOpenExams;
  final VoidCallback onOpenProfile;
  final void Function(int) onSelectTab;
  const _TeacherTopBar({required this.teacherName, required this.activeTab,
      required this.onBrandTap, required this.onOpenExams, required this.onOpenProfile,
      required this.onSelectTab});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: scheme.primary,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          Builder(builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu_rounded, color: Colors.white),
                tooltip: 'Menu',
                onPressed: () => _openNavMenu(ctx),
              )),
          GestureDetector(
            onTap: onBrandTap,
            child: Row(children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.school_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                const Text('Teacher Panel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                Text(teacherName, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 11),
                    overflow: TextOverflow.ellipsis),
              ]),
            ]),
          ),
          const Spacer(),
          _TopAction(
            icon: Icons.quiz_rounded,
            label: 'Exams',
            active: activeTab == 1,
            onTap: onOpenExams,
          ),
          const SizedBox(width: 4),
          _TopAction(
            icon: Icons.share_rounded,
            label: 'Share App',
            active: false,
            onTap: () async {
              final base = Config.api.replaceAll(RegExp(r'/api/?$'), '');
              await Share.share(
                'Teacher App — Nazirhat Collegiate High School\n\nডাউনলোড লিংক:\n$base/download\n\nv${await installedVersion()}',
                subject: 'School Teacher App',
              );
            },
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onOpenProfile,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutBack,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: activeTab == 6 ? Colors.white : Colors.white.withValues(alpha: 0.35),
                    width: activeTab == 6 ? 2.5 : 1.2),
              ),
              child: CircleAvatar(
                radius: 15,
                backgroundColor: Colors.white,
                child: Text(teacherName.isNotEmpty ? teacherName[0].toUpperCase() : 'T',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: scheme.primary)),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ]),
      ),
    );
  }

  // Bottom-sheet nav menu: single source of truth for the 8 tabs.
  // Replaces the old drawer (Scaffold has no drawer, so openDrawer() crashed).
  void _openNavMenu(BuildContext ctx) {
    const items = [
      (0, Icons.dashboard_rounded, 'হোম', 'Dashboard — আজকের সারসংক্ষেপ'),
      (1, Icons.quiz_rounded, 'Exams', 'Marks entry ও Events'),
      (2, Icons.fact_check_rounded, 'হাজিরা', 'Attendance ও analytics'),
      (3, Icons.edit_note_rounded, 'Homework', 'বাড়ির কাজ'),
      (4, Icons.calendar_month_rounded, 'রুটিন', 'সাপ্তাহিক রুটিন'),
      (5, Icons.group_rounded, 'Students', 'Class-এর শিক্ষার্থী'),
      (6, Icons.person_rounded, 'Profile', 'প্রোফাইল ও সেটিংস'),
      (7, Icons.upgrade_rounded, 'Promotion', 'প্রমোশন রিভিউ'),
    ];
    showModalBottomSheet(
      context: ctx,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(width: 44, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(99))),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(children: [
              CircleAvatar(
                backgroundColor: Theme.of(c).colorScheme.primary,
                child: Text(teacherName.isNotEmpty ? teacherName[0].toUpperCase() : 'T',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(teacherName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const Text('Teacher Panel', style: TextStyle(fontSize: 11, color: Colors.grey)),
              ])),
            ]),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final it in items)
                  ListTile(
                    leading: Icon(it.$2,
                        color: activeTab == it.$1
                            ? Theme.of(c).colorScheme.primary
                            : Colors.grey.shade600),
                    title: Text(it.$3,
                        style: TextStyle(fontWeight: activeTab == it.$1
                            ? FontWeight.w800 : FontWeight.w500)),
                    subtitle: Text(it.$4, style: const TextStyle(fontSize: 11)),
                    selected: activeTab == it.$1,
                    selectedTileColor: Theme.of(c).colorScheme.primaryContainer
                        .withValues(alpha: 0.35),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onTap: () {
                      Navigator.pop(c);
                      onSelectTab(it.$1);
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

class _TopAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TopAction({required this.icon, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: EdgeInsets.symmetric(horizontal: active ? 12 : 9, vertical: 7),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 17, color: active ? Theme.of(context).colorScheme.primary : Colors.white),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: active
                ? Padding(padding: const EdgeInsets.only(left: 5),
                    child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.primary)))
                : const SizedBox.shrink(),
          ),
        ]),
      ),
    );
  }
}

