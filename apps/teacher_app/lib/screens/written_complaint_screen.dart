import 'package:flutter/material.dart';

import '../api.dart';

class WrittenComplaintScreen extends StatefulWidget {
  const WrittenComplaintScreen({super.key});

  @override
  State<WrittenComplaintScreen> createState() => _WrittenComplaintScreenState();
}

class _WrittenComplaintScreenState extends State<WrittenComplaintScreen> {
  List _classes = [];
  List _complaints = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await Future.wait([
        Api.get('/teacher/profile'),
        Api.get('/teacher/complaints'),
      ]);
      if (!mounted) return;
      setState(() {
        _classes = data[0]['classes'] as List? ?? [];
        _complaints = data[1] as List? ?? [];
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _newComplaint() async {
    if (_classes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('লিখিত অভিযোগ পাঠাতে আপনাকে class teacher হতে হবে।'),
        ),
      );
      return;
    }
    int? classId = int.tryParse('${_classes.first['id']}');
    int? studentId;
    List students = [];
    bool loadingStudents = false;
    BuildContext? dialogContextRef;
    final title = TextEditingController();
    final message = TextEditingController();
    try {
      students =
          await Api.get('/teacher/classes/$classId/students') as List? ?? [];
      studentId = students.isEmpty
          ? null
          : int.tryParse('${students.first['id']}');
    } catch (_) {}
    Future<void> fetchStudents(StateSetter setDialog) async {
      if (classId == null || dialogContextRef?.mounted != true) return;
      setDialog(() {
        loadingStudents = true;
        students = [];
        studentId = null;
      });
      try {
        final rows = await Api.get('/teacher/classes/$classId/students');
        if (dialogContextRef?.mounted != true) return;
        setDialog(() {
          students = rows as List? ?? [];
          studentId = students.isEmpty
              ? null
              : int.tryParse('${students.first['id']}');
          loadingStudents = false;
        });
      } catch (_) {
        if (dialogContextRef?.mounted == true)
          setDialog(() => loadingStudents = false);
      }
    }

    if (!mounted) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        dialogContextRef = dialogContext;
        return StatefulBuilder(
          builder: (ctx, setDialog) => AlertDialog(
            title: const Text('শিক্ষার্থীর লিখিত অভিযোগ'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: classId,
                    decoration: const InputDecoration(labelText: 'শ্রেণি'),
                    items: _classes
                        .map(
                          (c) => DropdownMenuItem<int>(
                            value: int.tryParse('${c['id']}'),
                            child: Text(
                              '${c['name'] ?? c['class_name']} (${c['section'] ?? c['group_name'] ?? ''})',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      classId = value;
                      fetchStudents(setDialog);
                    },
                  ),
                  const SizedBox(height: 8),
                  if (loadingStudents)
                    const LinearProgressIndicator()
                  else if (students.isEmpty)
                    const Text('এই শ্রেণিতে কোনো শিক্ষার্থী পাওয়া যায়নি।')
                  else
                    DropdownButtonFormField<int>(
                      initialValue: studentId,
                      decoration: const InputDecoration(
                        labelText: 'শিক্ষার্থী',
                      ),
                      items: students
                          .map(
                            (s) => DropdownMenuItem<int>(
                              value: int.tryParse('${s['id']}'),
                              child: Text('${s['roll']}. ${s['name']}'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setDialog(() => studentId = value),
                    ),
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(labelText: 'শিরোনাম'),
                  ),
                  TextField(
                    controller: message,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'অভিযোগের বিবরণ',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('বাতিল'),
              ),
              FilledButton(
                onPressed: () {
                  if (studentId == null ||
                      title.text.trim().isEmpty ||
                      message.text.trim().isEmpty)
                    return;
                  Navigator.pop(ctx, {
                    'student_id': studentId,
                    'title': title.text.trim(),
                    'body': message.text.trim(),
                  });
                },
                child: const Text('Guardian-কে পাঠান'),
              ),
            ],
          ),
        );
      },
    );
    dialogContextRef = null;
    if (result == null || !mounted) return;
    setState(() => _sending = true);
    try {
      final response = await Api.post('/teacher/complaints', result);
      if (Api.isQueued(response)) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('সংযোগ না থাকায় অভিযোগটি queue-তে রাখা হয়েছে।'),
            ),
          );
      } else {
        await _load();
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('লিখিত অভিযোগ Guardian-কে পাঠানো হয়েছে।'),
            ),
          );
      }
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('লিখিত অভিযোগ'),
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _sending ? null : _newComplaint,
      icon: const Icon(Icons.edit_note),
      label: const Text('নতুন অভিযোগ'),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(child: Text(_error!))
        : _complaints.isEmpty
        ? const Center(child: Text('এখনও কোনো লিখিত অভিযোগ পাঠানো হয়নি।'))
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _complaints.length,
              itemBuilder: (_, index) {
                final row = _complaints[index];
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.description_outlined),
                    ),
                    title: Text('${row['title'] ?? 'লিখিত অভিযোগ'}'),
                    subtitle: Text(
                      'রোল ${row['roll'] ?? '—'} · ${row['student_name'] ?? ''}\n${row['body'] ?? ''}',
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
          ),
  );
}
