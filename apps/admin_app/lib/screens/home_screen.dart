import 'package:flutter/material.dart';

import '../fcm_service.dart';
import '../api.dart';
import 'students_screen.dart';
import 'teachers_screen.dart';
import 'classes_screen.dart';
import 'notices_screen.dart';
import 'sibling_request_screen.dart';
import 'settings_screen.dart';
import 'routines_screen.dart';
import 'attendance_screen.dart';
import 'login_screen.dart';
import 'exam_center_screen.dart';
import 'delete_logs_screen.dart';
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
            Text(
              'Sign Out',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to log out of the admin panel?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
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
    final now = DateTime.now();
    const months = [
      '',
      'জানুয়ারি',
      'ফেব্রুয়ারি',
      'মার্চ',
      'এপ্রিল',
      'মে',
      'জুন',
      'জুলাই',
      'আগস্ট',
      'সেপ্টেম্বর',
      'অক্টোবর',
      'নভেম্বর',
      'ডিসেম্বর',
    ];
    final dateLabel = '${now.day} ${months[now.month]} ${now.year}';
    final items = [
      (
        title: 'Students',
        subtitle: 'Admissions & records',
        icon: Icons.people_alt_rounded,
        color: const Color(0xFF5C50E8),
        screen: const StudentsScreen(),
      ),
      (
        title: 'Teachers',
        subtitle: 'Faculty & subjects',
        icon: Icons.school_rounded,
        color: const Color(0xFF8676F4),
        screen: const TeachersScreen(),
      ),
      (
        title: 'Classes',
        subtitle: 'Sections & groups',
        icon: Icons.meeting_room_rounded,
        color: const Color(0xFF3D4A75),
        screen: const ClassesScreen(),
      ),
      (
        title: 'স্কুল পরীক্ষা · Class 6–10',
        subtitle: 'নিজস্ব পরীক্ষা, ফলাফল ও শ্রেণি উত্তরণ / SSC Batch',
        icon: Icons.school_rounded,
        color: const Color(0xFF675DEB),
        screen: const ExamCenterScreen(),
      ),
      (
        title: 'Routines',
        subtitle: 'Class & bell schedule',
        icon: Icons.calendar_today_rounded,
        color: const Color(0xFF8BC34A),
        screen: const RoutinesScreen(),
      ),
      (
        title: 'Attendance',
        subtitle: 'Board, requests & report',
        icon: Icons.fact_check_rounded,
        color: const Color(0xFF5C50E8),
        screen: const AttendanceScreen(),
      ),
      (
        title: 'Notices',
        subtitle: 'Broadcast alerts',
        icon: Icons.campaign_rounded,
        color: const Color(0xFF8676F4),
        screen: const NoticesScreen(),
      ),
      (
        title: 'Sibling Req.',
        subtitle: 'Guardian pairings',
        icon: Icons.family_restroom_rounded,
        color: const Color(0xFF3D4A75),
        screen: const SiblingRequestScreen(),
      ),
      (
        title: 'স্থায়ী delete log',
        subtitle: 'কারণ ও সম্পূর্ণ audit record',
        icon: Icons.history_rounded,
        color: const Color(0xFFB45309),
        screen: const DeleteLogsScreen(),
      ),
      (
        title: 'Settings',
        subtitle: 'System preferences',
        icon: Icons.tune_rounded,
        color: const Color(0xFF5C50E8),
        screen: const SettingsScreen(),
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFEEF0F8),
      appBar: AppBar(
        title: const Row(
          children: [
            Image(
              image: AssetImage('assets/school_logo.png'),
              width: 26,
              height: 26,
              fit: BoxFit.contain,
            ),
            SizedBox(width: 8),
            Text(
              'Admin Dashboard',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: _loading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                children: [
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF5148E5),
                          Color(0xFF675DEB),
                          Color(0xFF8676F4),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6659E8).withValues(alpha: .25),
                          blurRadius: 22,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .16),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .3),
                            ),
                          ),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(5),
                            child: Image.asset(
                              'assets/school_logo.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'স্কুল পরিচালনা এক নজরে',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$dateLabel • শিক্ষার্থী, শিক্ষক ও পরীক্ষার তথ্য',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: .82),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.auto_awesome_rounded,
                          color: Color(0xFFD7F7A0),
                          size: 24,
                        ),
                      ],
                    ),
                  ),
                  // Overview Stats Header Row
                  Row(
                    children: [
                      _statCard(
                        label: 'Students',
                        value: _stats?['students'],
                        icon: Icons.people_outline_rounded,
                        color: const Color(0xFF5C50E8),
                      ),
                      const SizedBox(width: 10),
                      _statCard(
                        label: 'Teachers',
                        value: _stats?['teachers'],
                        icon: Icons.school_outlined,
                        color: const Color(0xFF3D4A75),
                      ),
                      const SizedBox(width: 10),
                      _statCard(
                        label: 'Exams',
                        value: _stats?['exams'],
                        icon: Icons.assignment_outlined,
                        color: const Color(0xFF8676F4),
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
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Modules Grid
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
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
                          border: Border.all(
                            color: Colors.grey.withValues(alpha: 0.12),
                          ),
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
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(9),
                                        decoration: BoxDecoration(
                                          color: item.color.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Icon(
                                          item.icon,
                                          size: 22,
                                          color: item.color,
                                        ),
                                      ),
                                      Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        size: 13,
                                        color: Colors.grey.shade400,
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
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
