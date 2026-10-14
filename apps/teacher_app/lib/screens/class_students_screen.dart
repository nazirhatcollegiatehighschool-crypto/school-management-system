import 'package:flutter/material.dart';
import '../api.dart';
import 'student_registration_screen.dart';

class ClassStudentsScreen extends StatefulWidget {
  final dynamic teacher;
  const ClassStudentsScreen({super.key, required this.teacher});
  @override
  State<ClassStudentsScreen> createState() => _ClassStudentsScreenState();
}

class _ClassStudentsScreenState extends State<ClassStudentsScreen> {
  List _classes = [];
  int? _selectedClass;
  List _students = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await Api.get('/teacher/profile');
      final classes = (r['classes'] as List? ?? []);
      setState(() {
        _classes = classes;
        if (_selectedClass == null && classes.isNotEmpty) _selectedClass = classes.first['id'];
        _loading = false;
      });
      if (_selectedClass != null) _loadStudents();
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _loadStudents() async {
    if (_students.isEmpty) setState(() { _loading = true; _error = null; });
    try {
      await Api.loadCachedFirst('/teacher/classes/$_selectedClass/guardians', (r) {
        if (!mounted) return;
        setState(() { _students = r is List ? r : []; _loading = false; });
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('রোল ও অভিভাবক'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _loadClasses),
      ]),
      floatingActionButton: _selectedClass != null
          ? FloatingActionButton.extended(
              onPressed: () async {
                final cls = _classes.firstWhere((c) => c['id'] == _selectedClass, orElse: () => null);
                if (cls == null) return;
                final ok = await Navigator.push<bool>(context,
                    MaterialPageRoute(builder: (_) => StudentRegistrationScreen(
                      teacher: widget.teacher,
                      classId: _selectedClass!,
                      classLabel: '${cls['name']} (${cls['section']})',
                    )));
                if (ok == true) _loadStudents();
              },
              icon: const Icon(Icons.person_add),
              label: const Text('নতুন ভর্তি'),
            )
          : null,
      body: _loading && _classes.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _classes.isEmpty
              ? Center(child: Text(_error!))
              : _classes.isEmpty
                  ? const Center(child: Text('আপনি কোনো class-এর class teacher নন।\nAdmin panel-এ class teacher assign করুন।',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 15)))
                  : Column(children: [
                      Padding(padding: const EdgeInsets.all(12),
                        child: DropdownButtonFormField<int>(
                          initialValue: _selectedClass,
                          decoration: const InputDecoration(labelText: 'আমার class (class teacher)', border: OutlineInputBorder()),
                          items: _classes.map<DropdownMenuItem<int>>((c) =>
                              DropdownMenuItem(value: c['id'], child: Text('${c['name']} (${c['section']}) — ${c['student_count']} students'))).toList(),
                          onChanged: (v) {
                            setState(() => _selectedClass = v);
                            if (v != null) _loadStudents();
                          },
                        )),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 14),
                        child: Divider(height: 1)),
                      Expanded(
                        child: _loading
                            ? const Center(child: CircularProgressIndicator())
                            : _error != null
                                ? Center(child: Text(_error!))
                                : _students.isEmpty
                                    ? const Center(child: Text('কোনো ছাত্র/অভিভাবক নেই', style: TextStyle(color: Colors.grey)))
                                    : ListView.builder(
                                        padding: const EdgeInsets.all(8),
                                        itemCount: _students.length,
                                        itemBuilder: (_, i) {
                                          final s = _students[i];
                                          return Card(child: ListTile(
                                            leading: CircleAvatar(child: Text('${s['roll'] ?? '-'}')),
                                            title: Text('${s['student_name'] ?? ''}'),
                                            subtitle: Text('অভিভাবক: ${s['guardian_name'] ?? '-'}\n${s['guardian_phone'] ?? '-'}${s['guardian_login'] != null ? ' • Login: ${s['guardian_login']}' : ''}'.trim()),
                                            isThreeLine: true,
                                          ));
                                        },
                                      ),
                      ),
                    ]),
    );
  }
}