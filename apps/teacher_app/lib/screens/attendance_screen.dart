import 'package:flutter/material.dart';
import '../api.dart';
import 'attendance_analytics_screen.dart';

class AttendanceScreen extends StatefulWidget {
  final dynamic teacher;
  final int? initialClassId;
  const AttendanceScreen({super.key, required this.teacher, this.initialClassId});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  List _classes = [];
  int? _selectedClass;
  DateTime _date = DateTime.now();
  List _students = [];
  Map<int, String> _status = {};
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Api.get('/teacher/profile').then((r) {
      setState(() {
        _classes = r['classes'];
        final wanted = widget.initialClassId;
        if (wanted != null && _classes.any((c) => c['id'] == wanted)) {
          _selectedClass = wanted;
          _loadStudents();
        }
      });
    }).catchError((e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    });
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _date,
        firstDate: DateTime(2020), lastDate: DateTime(2035));
    if (d != null) { setState(() => _date = d); if (_selectedClass != null) _loadStudents(); }
  }

  Future<void> _loadStudents() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await Api.get('/teacher/classes/$_selectedClass/students');
      setState(() {
        _students = r;
        _status = {for (final s in r) s['id'] as int: 'present'};
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _save() async {
    try {
      await Api.post('/teacher/attendance', {
        'date': _date.toIso8601String().substring(0, 10),
        'records': _status.entries.map((e) => {'student_id': e.key, 'status': e.value}).toList(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attendance saved!')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _notifyAbsent() async {
    final absentIds = _status.entries.where((e) => e.value != 'present').map((e) => e.key).toList();
    if (absentIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('সবাই present — notification দরকার নেই')));
      return;
    }
    try {
      await Api.post('/teacher/notify', {
        'student_ids': absentIds,
        'title': 'Attendance alert',
        'body': 'আপনার সন্তান আজ (${_date.toString().substring(0, 10)}) school-এ absent/late ছিল।',
        'type': 'attendance',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${absentIds.length} জনের guardian-কে alert পাঠানো হয়েছে')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance'), actions: [
        if (_students.isNotEmpty)
          IconButton(icon: const Icon(Icons.campaign), tooltip: 'absent-দের guardian-কে alert',
              onPressed: _students.isEmpty ? null : _notifyAbsent,
              color: _status.values.any((v) => v != 'present') ? Colors.red : Colors.grey),
        IconButton(icon: const Icon(Icons.insights), tooltip: 'Analytics',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AttendanceAnalyticsScreen()))),
      ]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(child: DropdownButtonFormField<int>(
              initialValue: _selectedClass,
              decoration: const InputDecoration(labelText: 'আমার class (class teacher)', border: OutlineInputBorder()),
              items: _classes.map<DropdownMenuItem<int>>((c) =>
                  DropdownMenuItem(value: c['id'], child: Text('${c['name']} (${c['section']})'))).toList(),
              onChanged: (v) { setState(() => _selectedClass = v); if (v != null) _loadStudents(); },
            )),
            const SizedBox(width: 8),
            TextButton(onPressed: _pickDate, child: Text(_date.toString().substring(0, 10))),
          ])),
        if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
        Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _students.isEmpty
                ? _classes.isEmpty
                    ? const Center(child: _RestrictedCard())
                    : Center(child: Text('উপরে class নির্বাচন করুন', textAlign: TextAlign.center))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 90),
                    itemCount: _students.length,
                    itemBuilder: (_, i) {
                      final s = _students[i];
                      return ListTile(
                        leading: CircleAvatar(child: Text('${s['roll']}')),
                        title: Text(s['name']),
                        trailing: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'present', label: Text('P')),
                            ButtonSegment(value: 'absent', label: Text('A')),
                            ButtonSegment(value: 'late', label: Text('L')),
                          ],
                          selected: {_status[s['id']] ?? 'present'},
                          onSelectionChanged: (sel) => setState(() => _status[s['id']] = sel.first),
                        ),
                      );
                    },
                  )),
      ]),
      floatingActionButton: _students.isEmpty ? null : FloatingActionButton.extended(
        icon: const Icon(Icons.save),
        label: const Text('Save'),
        onPressed: _save,
      ),
    );
  }
}

class _RestrictedCard extends StatelessWidget {
  const _RestrictedCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Card(
        color: Colors.amber.shade50,
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.lock_outline, size: 44, color: Colors.amber),
            const SizedBox(height: 10),
            const Text('Attendance Restricted', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'শুধুমাত্র designated Class Teacher-ই attendance নিতে পারবেন।\n'
              'আপনি আপাতত কোনো class-এর class teacher নন।\n'
              'Admin panel → Class & Class Teacher Allocation-এ আপনার ভূমিকা set করুন।',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.brown, height: 1.5),
            ),
          ]),
        ),
      ),
    );
  }
}