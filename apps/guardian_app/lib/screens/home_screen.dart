import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../fcm_service.dart';
import '../api.dart';
import 'student_tabs_screen.dart';
import 'add_sibling_screen.dart';
import 'login_screen.dart';
import '../widgets/offline_sync_banner.dart';
import '../update_check.dart';

class HomeScreen extends StatefulWidget {
  final List students;
  const HomeScreen({super.key, required this.students});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map? _profile;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _wirePush();
  }

  void _wirePush() {
    handleForegroundMessages(context, _onNotificationTap);
    FirebaseMessaging.instance.getInitialMessage().then((m) {
      if (m != null) _onNotificationTap(m.data);
    });
  }

  Future<void> _onNotificationTap(Map<String, dynamic> data) async {
    final type = data['type'] ?? '';
    int tab = 4;
    if (type == 'result' || type == 'class_test_result') tab = 2;
    if (type == 'attendance') tab = 1;
    if (type == 'homework') tab = 3;
    var studentId = int.tryParse('${data['student_id'] ?? ''}') ?? 0;

    if (studentId == 0) {
      if (data['exam_id'] != null) {
        try {
          final notifs = await Api.get('/guardian/notifications');
          for (final n in (notifs['notifications'] as List? ?? [])) {
            if ('${n['exam_id'] ?? ''}' == '${data['exam_id'] ?? ''}') {
              studentId = int.tryParse('${n['student_id'] ?? ''}') ?? 0;
              break;
            }
          }
        } catch (_) {}
      } else if (data['homework_id'] != null) {
        try {
          final notifs = await Api.get('/guardian/notifications');
          String? classId;
          for (final n in (notifs['notifications'] as List? ?? [])) {
            if (n['type'] == 'homework' && '${n['related_id'] ?? ''}' == '${data['homework_id'] ?? ''}') {
              classId = '${n['class_id'] ?? ''}';
              break;
            }
          }
          if (classId != null && classId.isNotEmpty) {
            final students = _profile?['students'] ?? widget.students;
            for (final st in (students as List)) {
              if ('${st['class_id'] ?? ''}' == classId) {
                studentId = int.tryParse('${st['id']}') ?? 0;
                break;
              }
            }
          }
        } catch (_) {}
      }
    }
    final students = _profile?['students'] ?? widget.students;
    if (studentId == 0) {
      final st = (students as List).isNotEmpty ? students[0] : null;
      if (st == null) return;
      studentId = int.tryParse('${st['id']}') ?? 0;
    }
    if (studentId == 0) return;
    final data2 = '${data['exam_id'] ?? ''}';
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentTabsScreen(
          studentId: studentId,
          studentName: '',
          initialTab: tab,
          initialExamId: (type == 'result' || type == 'class_test_result') ? data2 : null,
        ),
      ),
    );
  }

  Future<void> _load() async {
    try {
      final r = await Api.get('/guardian/profile');
      setState(() => _profile = r);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Colors.redAccent, size: 24),
            SizedBox(width: 8),
            Text('লগআউট নিশ্চিতকরণ', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text('আপনি কি নিশ্চিত যে অভিভাবক পোর্টাল থেকে লগআউট করতে চান?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('না')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('লগআউট'),
          ),
        ],
      ),
    );

    if (ok == true) {
      unregisterDeviceToken();
      await Api.clearToken();
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indigo = theme.colorScheme.primary;
    final students = _profile?['students'] ?? widget.students;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5FB),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.family_restroom_rounded, size: 22),
            SizedBox(width: 8),
            Text('Guardian App', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_rounded),
            tooltip: 'সন্তান যোগ করুন',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddSiblingScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.system_update_alt_rounded),
            tooltip: 'অ্যাপ আপডেট',
            onPressed: () => checkForUpdate(context, 'guardian', manual: true),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'লগআউট',
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : students.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    const OfflineSyncBanner(compact: true),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          children: [
                            // Guardian Welcome Card
                            Container(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF1E1B4B), Color(0xFF2E3A8C), Color(0xFF3730A3)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF2E3A8C).withValues(alpha: 0.3),
                                    blurRadius: 18,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(20),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
                                    ),
                                    child: const CircleAvatar(
                                      radius: 26,
                                      backgroundColor: Colors.white24,
                                      child: Icon(Icons.family_restroom_rounded, color: Colors.white, size: 28),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'স্বাগতম 👋',
                                          style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                                        ),
                                        const SizedBox(height: 2),
                                        const Text(
                                          'অভিভাবক ড্যাশবোর্ড',
                                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${students.length} জন শিক্ষার্থীর প্রোফাইল সংযুক্ত',
                                          style: const TextStyle(color: Colors.white, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),

                            // Section Title
                            const Text(
                              'আমার সন্তান / শিক্ষার্থীরা',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Student Cards List
                            for (final s in students)
                              Container(
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(18),
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
                                    borderRadius: BorderRadius.circular(18),
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => StudentTabsScreen(
                                          studentId: s['id'],
                                          studentName: s['name'],
                                        ),
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
                                        children: [
                                          // Student Avatar / Roll Badge
                                          Container(
                                            width: 48,
                                            height: 48,
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [indigo, const Color(0xFF4338CA)],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                              borderRadius: BorderRadius.circular(14),
                                            ),
                                            child: Center(
                                              child: Text(
                                                (s['name'] ?? 'S')[0].toUpperCase(),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 20,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 14),

                                          // Student Info
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  s['name'] ?? '',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 16,
                                                    color: Color(0xFF0F172A),
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Wrap(
                                                  spacing: 6,
                                                  runSpacing: 4,
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFFEEF2FF),
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(color: const Color(0xFFC7D2FE)),
                                                      ),
                                                      child: Text(
                                                        'Class ${s['class_name']} (${s['section']})',
                                                        style: const TextStyle(
                                                          color: Color(0xFF3730A3),
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.grey.shade100,
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        'Roll: ${s['roll']}',
                                                        style: TextStyle(
                                                          color: Colors.grey.shade700,
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'ID: ${s['student_code']}',
                                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                                ),
                                              ],
                                            ),
                                          ),

                                          // Arrow Icon
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: indigo.withValues(alpha: 0.08),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: indigo),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                            const SizedBox(height: 16),

                            // Add Sibling Card
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: indigo.withValues(alpha: 0.25), style: BorderStyle.solid),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const AddSiblingScreen()),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.add_circle_outline_rounded, color: indigo, size: 20),
                                        const SizedBox(width: 8),
                                        Text(
                                          'আরও সন্তান যোগ করুন (Add Sibling)',
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700,
                                            color: indigo,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // App Update Card
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
                              ),
                              child: ListTile(
                                dense: true,
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.system_update_alt_rounded, color: Colors.blue, size: 18),
                                ),
                                title: const Text('অ্যাপ আপডেট', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                                subtitle: FutureBuilder(
                                  future: Future.wait([installedVersion(), installedBuild()]),
                                  builder: (_, s) {
                                    final v = s.data is List ? (s.data as List)[0].toString() : '…';
                                    final b = s.data is List ? (s.data as List)[1].toString() : '…';
                                    return Text('ফোনে: v$v • build $b — tap করে সার্ভারের সাথে মিলান',
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600));
                                  },
                                ),
                                trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                                onTap: () => checkForUpdate(context, 'guardian', manual: true),
                              ),
                            ),

                            // Version Footer
                            FutureBuilder<String>(
                              future: installedVersion(),
                              builder: (_, s) => Padding(
                                padding: const EdgeInsets.only(top: 14, bottom: 20),
                                child: Text(
                                  'Nazirhat Collegiate High School • Guardian v${s.data ?? ''}',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
