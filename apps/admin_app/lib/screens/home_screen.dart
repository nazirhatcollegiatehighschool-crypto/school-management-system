import 'package:flutter/material.dart';
import '../fcm_service.dart';
import '../api.dart';
import 'students_screen.dart';
import 'teachers_screen.dart';
import 'classes_screen.dart';
import 'exams_screen.dart';
import 'notices_screen.dart';
import 'sibling_request_screen.dart';
import 'settings_screen.dart';
import 'routines_screen.dart';
import 'login_screen.dart';
import '../widgets/offline_sync_banner.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map? _stats;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final r = await Api.get('/admin/stats');
      setState(() => _stats = r);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final items = [
['Students', Icons.people, Colors.blue, const StudentsScreen()],
      ['Teachers', Icons.school, Colors.teal, const TeachersScreen()],
      ['Classes', Icons.class_, Colors.purple, const ClassesScreen()],
      ['Exams & Marks', Icons.quiz, Colors.orange, const ExamsScreen()],
      ['Routines', Icons.calendar_month, Colors.green, const RoutinesScreen()],
      ['Notices', Icons.campaign, Colors.red, const NoticesScreen()],
      ['Sibling Req.', Icons.family_restroom, Colors.indigo, const SiblingRequestScreen()],
      ['Settings', Icons.settings, Colors.brown, const SettingsScreen()],
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('School Admin'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
IconButton(icon: const Icon(Icons.logout), onPressed: () async {
            unregisterDeviceToken();
            await Api.clearToken();
            if (!mounted) return;
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
          }),
        ],
      ),
body: Column(children: [
        const OfflineSyncBanner(compact: true),
        Padding(padding: const EdgeInsets.all(12),
          child: Row(children: [
            _statCard('Students', _stats?['students']),
            _statCard('Teachers', _stats?['teachers']),
            _statCard('Exams', _stats?['exams']),
          ])),
        Expanded(child: GridView.count(
          crossAxisCount: 2,
          padding: const EdgeInsets.all(12),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: [
            for (final it in items)
              Card(child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => it[3] as Widget));
                  _load();
                },
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(it[1] as IconData, size: 44, color: it[2] as Color),
                  const SizedBox(height: 10),
                  Text(it[0] as String, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ]),
              )),
          ])),
      ]),
    );
  }

  Widget _statCard(String label, dynamic value) {
    return Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(14),
      child: Column(children: [
        Text(value?.toString() ?? '-', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blue)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ]))));
  }
}


