import 'package:flutter/material.dart';

import '../api.dart';

class CreateExamScreen extends StatefulWidget {
  final dynamic teacher;
  const CreateExamScreen({super.key, required this.teacher});
  @override
  State<CreateExamScreen> createState() => _CreateExamScreenState();
}

class _CreateExamScreenState extends State<CreateExamScreen> {
  final TextEditingController _name = TextEditingController();
  final String _type = 'class_test';
  int? _subjectId;
  DateTime? _date;
  List _subjects = [];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Api.loadCachedFirst('/teacher/subjects', (r) {
      if (!mounted) return;
      setState(() => _subjects = r is List ? r : []);
    }).catchError((e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    });
  }

  bool _flag(dynamic value) => value == true || value == 1 || value == '1';

  /// Backward-compatible: cached payloads from older servers have no flags.
  bool get _hasSubjectFlags =>
      _subjects.any((s) => s is Map && s.containsKey('own_subject'));

  bool _isOwnSubject(Map s) => !_hasSubjectFlags || _flag(s['own_subject']);

  bool _isClassSubject(Map s) =>
      !_isOwnSubject(s) && _flag(s['class_teacher_subject']);

  String _subjectLabel(Map s) {
    final group = '${s['group_name'] ?? ''}'.trim();
    final section = '${s['section'] ?? ''}'.trim();
    final tail = group.isNotEmpty ? group : section;
    return '${s['name']} — ${s['class_name']}${tail.isEmpty ? '' : ' ($tail)'}';
  }

  List<DropdownMenuItem<int>> _subjectItems() {
    final own = <Map>[];
    final classroom = <Map>[];
    for (final s in _subjects.whereType<Map>()) {
      if (_isOwnSubject(s)) {
        own.add(s);
      } else if (_isClassSubject(s)) {
        classroom.add(s);
      }
    }
    return [
      if (own.isNotEmpty)
        const DropdownMenuItem<int>(
          value: -1,
          enabled: false,
          child: Padding(
            padding: EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              'আমার Subject',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF202A49),
              ),
            ),
          ),
        ),
      ...own.map(
        (s) => DropdownMenuItem<int>(
          value: (s['id'] as num).toInt(),
          child: Text(_subjectLabel(s), overflow: TextOverflow.ellipsis),
        ),
      ),
      if (classroom.isNotEmpty)
        const DropdownMenuItem<int>(
          value: -2,
          enabled: false,
          child: Padding(
            padding: EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              'আমার Class-এর সব Subject',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF0B6B4F),
              ),
            ),
          ),
        ),
      ...classroom.map(
        (s) => DropdownMenuItem<int>(
          value: (s['id'] as num).toInt(),
          child: Text(_subjectLabel(s), overflow: TextOverflow.ellipsis),
        ),
      ),
    ];
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
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final r = await Api.post('/teacher/exams', {
        'name': _name.text.trim(),
        'exam_type': _type,
        'class_id': subj['class_id'],
        'subject_id': _subjectId,
        'exam_date': _date?.toIso8601String().substring(0, 10),
      });
      if (!mounted) return;
      if (Api.isQueued(r)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text(
              'ইন্টারনেট নেই — exam ফোনে সেভ আছে, online হলেই তৈরি হবে',
            ),
          ),
        );
        Navigator.pop(context);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exam created! এখন marks দিতে পারেন।')),
      );
      Navigator.pop(context);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Exam')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Exam Name *',
              border: OutlineInputBorder(),
              hintText: 'যেমন: Class Test 3 - Math',
            ),
          ),
          const SizedBox(height: 16),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _subjectId,
            decoration: const InputDecoration(
              labelText: 'Subject নির্বাচন করুন *',
              border: OutlineInputBorder(),
            ),
            items: _subjectItems(),
            onChanged: (v) => setState(() => _subjectId = v),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  _date == null
                      ? 'Exam date: not set'
                      : 'Date: ${_date.toString().substring(0, 10)}',
                ),
              ),
              TextButton(onPressed: _pickDate, child: const Text('Pick Date')),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create Exam'),
            ),
          ),
        ],
      ),
    );
  }
}
