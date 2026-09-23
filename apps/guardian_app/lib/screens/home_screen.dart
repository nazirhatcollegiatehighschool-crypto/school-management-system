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
  void initState() { super.initState(); _load(); _wirePush(); }

  void _wirePush() {
    handleForegroundMessages(context, _onNotificationTap);
    FirebaseMessaging.instance.getInitialMessage().then((m) { if (m != null) _onNotificationTap(m.data); });
  }

  Future<void> _onNotificationTap(Map<String, dynamic> data) async {
    final type = data['type'] ?? '';
    int tab = 4;
    if (type == 'result' || type == 'class_test_result') tab = 2;
    if (type == 'attendance') tab = 1;
    if (type == 'homework') tab = 3;
    var studentId = int.tryParse('${data['student_id'] ?? ''}') ?? 0;

    // Resolve the correct child from our own notification history when the
    // push payload didn't carry a student_id (multicast sends one payload to
    // every guardian, so we must match the exam/homework in OUR list).
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
      // Fall back to the first child only when the payload truly has no scope.
      final st = (students as List).isNotEmpty ? students[0] : null;
      if (st == null) return;
      studentId = int.tryParse('${st['id']}') ?? 0;
    }
    if (studentId == 0) return;
    final data2 = '${data['exam_id'] ?? ''}';
    Navigator.push(context, MaterialPageRoute(builder: (_) => StudentTabsScreen(
        studentId: studentId,
        studentName: '',
        initialTab: tab,
        initialExamId: (type == 'result' || type == 'class_test_result') ? data2 : null)));
  }

  Future<void> _load() async {
    try {
      final r = await Api.get('/guardian/profile');
      setState(() => _profile = r);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final students = _profile?['students'] ?? widget.students;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guardian App'),
actions: [
          IconButton(icon: const Icon(Icons.system_update_alt), tooltip: 'অ্যাপ আপডেট',
              onPressed: () => checkForUpdate(context, 'guardian', manual: true)),
          IconButton(icon: const Icon(Icons.person_add_alt_1), tooltip: 'সন্তান যোগ করুন',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddSiblingScreen()))),
          IconButton(icon: const Icon(Icons.logout), onPressed: () async {
            unregisterDeviceToken();
            await Api.clearToken();
            if (!mounted) return;
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
          }),
        ],
      ),
body: _error != null
          ? Center(child: Text(_error!))
          : students.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  const OfflineSyncBanner(compact: true),
                  Expanded(child: ListView(padding: const EdgeInsets.all(14), children: [
                  for (final s in students)
                    Card(child: ListTile(
                      leading: CircleAvatar(backgroundColor: Colors.indigo.shade100,
                          child: Text(s['name'][0])),
                      title: Text(s['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${s['class_name']} (${s['section']}) • Roll ${s['roll']}\nID: ${s['student_code']}'),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => StudentTabsScreen(studentId: s['id'], studentName: s['name']))),
                    )),
                ])),
              ]),
    );
  }
}

