import 'package:flutter/material.dart';
import '../api.dart';

class CreateExamScreen extends StatefulWidget {
  final dynamic teacher;
  const CreateExamScreen({super.key, required this.teacher});
  @override
  State<CreateExamScreen> createState() => _CreateExamScreenState();
}

class _CreateExamScreenState extends State<CreateExamScreen> {
  final _name = TextEditingController();
  String _type = 'class_test';
  int? _subjectId;
  DateTime? _date;
  List _subjects = [];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Api.get('/teacher/subjects').then((r) => setState(() => _subjects = r)).catchError((e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    });
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    if (_subjectId == null) {
      setState(() => _error = 'Subject নির্বাচন করুন');
      return;
    }
    final subj = _subjects.firstWhere((s) => s['id'] == _subjectId);
    setState(() { _saving = true; _error = null; });
    try {
      await Api.post('/teacher/exams', {
        'name': _name.text.trim(),
        'exam_type': _type,
        'class_id': subj['class_id'],
        'subject_id': _subjectId,
        'exam_date': _date?.toIso8601String().substring(0, 10),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Exam created! এখন marks দিতে পারেন।')));
      Navigator.pop(context);
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Exam')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(controller: _name,
              decoration: const InputDecoration(labelText: 'Exam Name *', border: OutlineInputBorder(),
                  hintText: 'যেমন: Class Test 3 - Math')),
          const SizedBox(height: 16),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _subjectId,
            decoration: const InputDecoration(labelText: 'Subject (আপনাকে দেওয়া subject) *', border: OutlineInputBorder()),
            items: _subjects.map<DropdownMenuItem<int>>((s) =>
                DropdownMenuItem(value: s['id'], child: Text('${s['name']} — ${s['class_name']} (${s['section']})'))).toList(),
            onChanged: (v) => setState(() => _subjectId = v),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Text(_date == null ? 'Exam date: not set' : 'Date: ${_date.toString().substring(0, 10)}')),
            TextButton(onPressed: _pickDate, child: const Text('Pick Date')),
          ]),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Padding(padding: const EdgeInsets.all(14),
                child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Create Exam')),
          ),
        ],
      ),
    );
  }
}