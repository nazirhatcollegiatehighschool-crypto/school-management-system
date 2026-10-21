import 'package:flutter/material.dart';
import '../fcm_service.dart';
import '../api.dart';
import 'students_screen.dart';
import 'teachers_screen.dart';
import 'classes_screen.dart';
import 'approvals_screen.dart';
import 'exam_catalog_screen.dart';
import 'exams_screen.dart';
import 'results_screen.dart';
import 'notices_screen.dart';
import 'sibling_request_screen.dart';
import 'settings_screen.dart';
import 'routines_screen.dart';
import 'promotion_screen.dart';
import 'attendance_screen.dart';
import 'login_screen.dart';
import 'exam_dashboard_screen.dart';
import '../widgets/offline_sync_banner.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map? _stats;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Api.get('/admin/stats');
      if (mounted) setState(() => _stats = r);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Colors.redAccent, size: 24),
            SizedBox(width: 10),
            Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: const Text('Are you sure you want to log out of the admin panel?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (ok == true) {
      unregisterDeviceToken();
      await Api.clearToken();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        title: 'Students',
        subtitle: 'Admissions & records',
        icon: Icons.people_alt_rounded,
        color: const Color(0xFF2563EB),
        screen: const StudentsScreen(),
      ),
      (
        title: 'Teachers',
        subtitle: 'Faculty & subjects',
        icon: Icons.school_rounded,
        color: const Color(0xFF0D9488),
        screen: const TeachersScreen(),
      ),
      (
        title: 'Classes',
        subtitle: 'Sections & groups',
        icon: Icons.meeting_room_rounded,
        color: const Color(0xFF7C3AED),
        screen: const ClassesScreen(),
      ),
      (
        title: 'Exam Session Dashboard',
        subtitle: 'Sessions, progress, publish, entry',
        icon: Icons.dashboard_rounded,
        color: const Color(0xFF6366F1),
        screen: const ExamDashboardScreen(),
      ),
      (
        title: 'Exams & Marks',
        subtitle: 'Assessments & entries',
        icon: Icons.assignment_turned_in_rounded,
        color: const Color(0xFFEA580C),
        screen: const ExamsScreen(),
      ),
      (
        title: 'Results',
        subtitle: 'Running / Published + PDF',
        icon: Icons.emoji_events_rounded,
        color: const Color(0xFFB45309),
        screen: const ResultsScreen(),
      ),
      (
        title: 'Exam Approvals',
        subtitle: 'Pending marks entry',
        icon: Icons.rule_folder_rounded,
        color: const Color(0xFF0D9488),
        screen: const ApprovalsScreen(),
      ),
      (
        title: 'Exam Weightage',
        subtitle: 'NCTB catalog & pass rules',
        icon: Icons.tune_rounded,
        color: const Color(0xFF7C3AED),
        screen: const ExamCatalogScreen(),
      ),
      (
        title: 'Promotion → SSC',
        subtitle: 'Yearly graduation',
        icon: Icons.how_to_reg_rounded,
        color: const Color(0xFF4F46E5),
        screen: const PromotionScreen(),
      ),
      (
        title: 'Routines',
        subtitle: 'Class & bell schedule',
        icon: Icons.calendar_today_rounded,
        color: const Color(0xFF16A34A),
        screen: const RoutinesScreen(),
      ),
      (
        title: 'Attendance',
        subtitle: 'Board, requests & report',
        icon: Icons.fact_check_rounded,
        color: const Color(0xFF0EA5E9),
        screen: const AttendanceScreen(),
      ),
      (
        title: 'Notices',
        subtitle: 'Broadcast alerts',
        icon: Icons.campaign_rounded,
        color: const Color(0xFFE11D48),
        screen: const NoticesScreen(),
      ),
      (
        title: 'Sibling Req.',
        subtitle: 'Guardian pairings',
        icon: Icons.family_restroom_rounded,
        color: const Color(0xFF0284C7),
        screen: const SiblingRequestScreen(),
      ),
      (
        title: 'Settings',
        subtitle: 'System preferences',
        icon: Icons.tune_rounded,
        color: const Color(0xFF475569),
        screen: const SettingsScreen(),
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, size: 22),
            SizedBox(width: 8),
            Text('Admin Dashboard', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout_rounded),
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: Column(
        children: [
          const OfflineSyncBanner(compact: true),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                children: [
                  // Overview Stats Header Row
                  Row(
                    children: [
                      _statCard(
                        label: 'Students',
                        value: _stats?['students'],
                        icon: Icons.people_outline_rounded,
                        color: const Color(0xFF2563EB),
                      ),
                      const SizedBox(width: 10),
                      _statCard(
                        label: 'Teachers',
                        value: _stats?['teachers'],
                        icon: Icons.school_outlined,
                        color: const Color(0xFF0D9488),
                      ),
                      const SizedBox(width: 10),
                      _statCard(
                        label: 'Exams',
                        value: _stats?['exams'],
                        icon: Icons.assignment_outlined,
                        color: const Color(0xFFEA580C),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Section Title
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Administrative Modules',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                          letterSpacing: -0.2,
                        ),
                      ),
                      Text(
                        '${items.length} Modules',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Modules Grid
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.25,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => item.screen),
                              );
                              _load();
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(9),
                                        decoration: BoxDecoration(
                                          color: item.color.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Icon(item.icon, size: 22, color: item.color),
                                      ),
                                      Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        size: 13,
                                        color: Colors.grey.shade400,
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        item.subtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w400,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required String label,
    required dynamic value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value?.toString() ?? '-',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
