import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../api.dart';
import '../class_alerts.dart';
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

class HomeScreen extends StatefulWidget {
  final dynamic teacher;
  const HomeScreen({super.key, required this.teacher});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  final _examsKey = GlobalKey<ExamsScreenState>();

  @override
  void initState() {
    super.initState();
    _wirePush();
    ClassAlertService.instance.start();
    _loadRoutines();
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
    return Scaffold(
      body: Column(
        children: [
          const OfflineSyncBanner(compact: true),
          Expanded(child: screens[_tab]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.quiz_outlined), label: 'Exams'),
          NavigationDestination(icon: Icon(Icons.fact_check_outlined), label: 'Attendance'),
          NavigationDestination(icon: Icon(Icons.edit_note_outlined), label: 'Homework'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), label: 'Routine'),
          NavigationDestination(icon: Icon(Icons.group_outlined), label: 'Students'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
          NavigationDestination(icon: Icon(Icons.upgrade_outlined), label: 'Promotion'),
        ],
      ),
    );
  }
}