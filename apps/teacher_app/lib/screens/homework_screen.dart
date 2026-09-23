import 'package:flutter/material.dart';
import '../api.dart';

class HomeworkScreen extends StatefulWidget {
  final dynamic teacher;
  const HomeworkScreen({super.key, required this.teacher});
  @override
  State<HomeworkScreen> createState() => _HomeworkScreenState();
}

class _HomeworkScreenState extends State<HomeworkScreen> {
  List _homework = [];
  List _classes = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadClasses();
    _load();
  }

  Future<void> _loadClasses() async {
    try {
      final r = await Api.get('/teacher/profile');
      if (mounted) setState(() => _classes = r['classes']);
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final r = await Api.get('/teacher/homework');
      if (mounted) setState(() { _homework = r; _loading = false; _error = null; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _createHomework() async {
    if (_classes.isEmpty) return;
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final dueCtrl = TextEditingController();
    int? classId = _classes.first['id'] as int;
    DateTime? dueDate;

    await showDialog(context: context, builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setCtx) {
        return AlertDialog(
          title: const Text('New Homework'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<int>(
              initialValue: classId,
              decoration: const InputDecoration(labelText: 'Class'),
              items: _classes.map((c) => DropdownMenuItem(
                  value: c['id'] as int,
                  child: Text('${c['class_name']} (${c['section']})'))).toList(),
              onChanged: (v) => setCtx(() => classId = v),
            ),
            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title'),
                maxLines: 1, autofocus: true),
            TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description (optional)'),
                maxLines: 3),
            TextField(controller: dueCtrl, readOnly: true, onTap: () async {
              final d = await showDatePicker(context: ctx,
                  initialDate: dueDate ?? DateTime.now(),
                  firstDate: DateTime(2020), lastDate: DateTime(2035));
              if (d != null) {
                dueDate = d;
                setCtx(() => dueCtrl.text = d.toIso8601String().substring(0, 10));
              }
            }, decoration: const InputDecoration(labelText: 'Due date (optional)')),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () async {
              if (titleCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              try {
                final r = await Api.post('/teacher/homework', {
                  'class_id': classId,
                  'title': titleCtrl.text.trim(),
                  'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                  'due_date': dueDate?.toIso8601String().substring(0, 10),
                });
                _load();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Homework assigned (push: ${r['push']?['sent'] ?? 'n/a'})')));
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    backgroundColor: Colors.red,
                    content: Text(e.toString().replaceFirst('Exception: ', ''))));
              }
            }, child: const Text('Assign')),
          ],
        );
      });
    });
  }

  Future<void> _sendComplaint() async {
    if (_classes.isEmpty) return;
    int? classId = _classes.first['id'] as int;
    List students = [];
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    bool special = false;
    int? studentId;

    await showDialog(context: context, builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setCtx) {
        Future<void> loadStudents() async {
          try {
            final r = await Api.get('/teacher/classes/$classId/students');
            setCtx(() { students = r; if (r.isNotEmpty) studentId = r.first['id'] as int; });
          } catch (_) {}
        }
        return AlertDialog(
          title: const Text('Complaint / Special Notice'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<int>(
              initialValue: classId,
              decoration: const InputDecoration(labelText: 'Class'),
              items: _classes.map((c) => DropdownMenuItem(
                  value: c['id'] as int, child: Text('${c['class_name']} (${c['section']})'))).toList(),
              onChanged: (v) => setCtx(() { classId = v; studentId = null; loadStudents(); }),
            ),
            if (students.isEmpty)
              Padding(padding: const EdgeInsets.only(top: 8),
                  child: TextButton(onPressed: loadStudents, child: const Text('Load students')))
            else
              DropdownButtonFormField<int>(
                initialValue: studentId,
                decoration: const InputDecoration(labelText: 'Student'),
                items: students.map((s) => DropdownMenuItem(
                    value: s['id'] as int, child: Text('${s['roll']}. ${s['name']}'))).toList(),
                onChanged: (v) => setCtx(() => studentId = v),
              ),
            const SizedBox(height: 6),
            SwitchListTile(
              value: special,
              onChanged: (v) => setCtx(() => special = v),
              title: const Text('Special direct notice (not complaint)'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title')),
            TextField(controller: bodyCtrl, decoration: const InputDecoration(labelText: 'Message'), maxLines: 3),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () async {
              if (studentId == null || titleCtrl.text.trim().isEmpty || bodyCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              try {
                final r = await Api.post('/teacher/complaints', {
                  'student_id': studentId,
                  'title': titleCtrl.text.trim(),
                  'body': bodyCtrl.text.trim(),
                  'kind': special ? 'special' : 'complaint',
                });
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Sent (push: ${r['push']?['sent'] ?? 'n/a'})')));
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    backgroundColor: Colors.red,
                    content: Text(e.toString().replaceFirst('Exception: ', ''))));
              }
            }, child: const Text('Send')),
          ],
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Homework & Notices')),
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        FloatingActionButton.small(heroTag: 'hw', onPressed: _createHomework,
            tooltip: 'Assign homework',
            child: const Icon(Icons.edit_note)),
        const SizedBox(height: 8),
        FloatingActionButton.small(heroTag: 'comp', onPressed: _sendComplaint,
            tooltip: 'Complaint / special notice',
            child: const Icon(Icons.campaign)),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _homework.length,
                    itemBuilder: (_, i) {
                      final h = _homework[i];
                      return Card(child: ListTile(
                        leading: const Icon(Icons.edit_note, color: Colors.deepPurple),
                        title: Text(h['title']),
                        subtitle: Text([
                          '${h['class_name']} (${h['section']})',
                          if (h['subject_name'] != null) h['subject_name'].toString(),
                          if ((h['description'] ?? '').toString().isNotEmpty) h['description'].toString(),
                        ].join('\n')),
                        isThreeLine: true,
                        trailing: Text(h['due_date'] != null
                            ? 'Due ${h['due_date'].toString().substring(0, 10)}'
                            : 'No due date',
                            style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ));
                    },
                  ),
                ),
    );
  }
}