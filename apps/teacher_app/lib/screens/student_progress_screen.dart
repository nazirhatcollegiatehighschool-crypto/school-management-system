import 'package:flutter/material.dart';

import '../api.dart';
import 'student_profile_screen.dart';

class StudentProgressScreen extends StatefulWidget {
  final int classId;
  final String classLabel;
  final String subjectName;
  final bool showUniform;
  final bool uniformOnly;
  const StudentProgressScreen({
    super.key,
    required this.classId,
    required this.classLabel,
    required this.subjectName,
    this.showUniform = true,
    this.uniformOnly = false,
  });

  @override
  State<StudentProgressScreen> createState() => _StudentProgressScreenState();
}

class _StudentProgressScreenState extends State<StudentProgressScreen> {
  List _students = [];
  final Map<int, Map<String, dynamic>> _reports = {};
  final Set<int> _saving = {};
  final Set<int> _changed = {};
  bool _loading = true;
  String? _error;

  String get _date {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

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
      final results = await Future.wait([
        Api.get('/teacher/classes/${widget.classId}/students'),
        Api.get(
          widget.uniformOnly
              ? '/teacher/classes/${widget.classId}/uniform-reports?date=$_date'
              : '/teacher/classes/${widget.classId}/daily-reports?date=$_date',
        ),
      ]);
      if (!mounted) return;
      final rows = List.from(results[0] as List? ?? [])
        ..sort(
          (a, b) => (int.tryParse('${a['roll']}') ?? 0).compareTo(
            int.tryParse('${b['roll']}') ?? 0,
          ),
        );
      _reports.clear();
      for (final row in (results[1] as List? ?? [])) {
        if (row is! Map ||
            (!widget.uniformOnly && row['subject_name'] != widget.subjectName))
          continue;
        final id = int.tryParse('${row['student_id']}');
        if (id == null) continue;
        _reports[id] = widget.uniformOnly
            ? {
                'uniform_brought':
                    row['uniform_brought'] != false &&
                    row['uniform_brought'] != 0,
                'note': row['note']?.toString() ?? '',
              }
            : {
                'homework_status': row['homework_status'] ?? 'not_done',
                'learning_status': row['learning_status'] ?? 'partial',
                'performance': row['performance'] ?? 'average',
                'uniform_brought':
                    row['uniform_brought'] != false &&
                    row['uniform_brought'] != 0,
                'note': row['note']?.toString() ?? '',
              };
      }
      for (final student in rows) {
        if (student is! Map) continue;
        final id = int.tryParse('${student['id']}');
        if (id != null) {
          _reports.putIfAbsent(
            id,
            () => widget.uniformOnly
                ? {'uniform_brought': true, 'note': ''}
                : {
                    'homework_status': 'not_done',
                    'learning_status': 'partial',
                    'performance': 'average',
                    'uniform_brought': true,
                    'note': '',
                  },
          );
        }
      }
      setState(() {
        _students = rows;
        _changed.clear();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _save(Map student) async {
    final id = int.parse('${student['id']}');
    setState(() => _saving.add(id));
    try {
      final report = Map<String, dynamic>.from(_reports[id]!);
      if (widget.uniformOnly) {
        await Api.post('/teacher/classes/${widget.classId}/uniform-reports', {
          'student_id': id,
          'date': _date,
          'uniform_brought': report['uniform_brought'],
          'note': report['note'],
        });
      } else {
        report.remove('uniform_brought');
        await Api.post('/teacher/classes/${widget.classId}/daily-reports', {
          'student_id': id,
          'date': _date,
          'subject_name': widget.subjectName,
          ...report,
        });
      }
      _changed.remove(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${student['name']} — আজকের তথ্য সেভ হয়েছে')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text(e.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.classLabel),
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, textAlign: TextAlign.center),
            ),
          )
        : _students.isEmpty
        ? const Center(child: Text('এই class-এ শিক্ষার্থী নেই'))
        : ListView(
            padding: const EdgeInsets.all(14),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF293B75), Color(0xFF6657D9)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.uniformOnly
                          ? 'আজকের uniform report'
                          : 'আজকের শিক্ষার্থী আপডেট',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${widget.uniformOnly ? widget.classLabel : widget.subjectName}  ·  $_date',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.uniformOnly
                          ? 'শুধু uniform-এর তথ্য guardian-কে জানানো হবে।'
                          : 'শুধু পরিবর্তন করা পড়া ও শেখার তথ্য guardian-এর কাছে যাবে।',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              for (final raw in _students)
                if (raw is Map) _studentCard(raw),
            ],
          ),
  );

  Widget _studentCard(Map student) {
    final id = int.tryParse('${student['id']}');
    if (id == null) return const SizedBox.shrink();
    final values = _reports[id]!;
    if (widget.uniformOnly) return _uniformCard(student, id, values);
    Widget select(String label, String key, List<(String, String)> options) =>
        DropdownButtonFormField<String>(
          initialValue: '${values[key]}',
          isExpanded: true,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
          ),
          items: options
              .map(
                (o) => DropdownMenuItem(
                  value: o.$1,
                  child: Text(o.$2, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null)
              setState(() {
                values[key] = v;
                _changed.add(id);
              });
          },
        );
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 7),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(child: Text('${student['roll'] ?? '•'}')),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StudentProfileScreen(
                          studentId: id,
                          studentName: '${student['name'] ?? ''}',
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${student['name'] ?? ''}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF3B4A8A),
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: Colors.blueGrey,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            select('আজকের পড়া', 'homework_status', const [
              ('done', 'করেছে'),
              ('not_done', 'করেনি'),
            ]),
            const SizedBox(height: 9),
            select('পড়া শিখেছে', 'learning_status', const [
              ('learned', 'শিখেছে'),
              ('partial', 'আংশিক'),
              ('not_learned', 'শেখেনি'),
            ]),
            const SizedBox(height: 9),
            select('আজকের performance', 'performance', const [
              ('good', 'ভালো'),
              ('average', 'মধ্যম'),
              ('poor', 'খারাপ'),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving.contains(id) || !_changed.contains(id)
                    ? null
                    : () => _save(student),
                icon: _saving.contains(id)
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('পরিবর্তিত তথ্য সেভ করুন'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _uniformCard(Map student, int id, Map<String, dynamic> values) => Card(
    margin: const EdgeInsets.symmetric(vertical: 7),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(child: Text('${student['roll'] ?? '•'}')),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${student['name'] ?? ''}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('আজ uniform এনেছে'),
            value: values['uniform_brought'] == true,
            onChanged: (value) => setState(() {
              values['uniform_brought'] = value;
              _changed.add(id);
            }),
          ),
          if (values['uniform_brought'] != true)
            TextFormField(
              key: ValueKey('uniform-note-$id'),
              initialValue: values['note'] as String,
              decoration: const InputDecoration(
                labelText: 'Uniform না আনার নোট',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() {
                values['note'] = value;
                _changed.add(id);
              }),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving.contains(id) || !_changed.contains(id)
                  ? null
                  : () => _save(student),
              icon: _saving.contains(id)
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Uniform report সেভ করুন'),
            ),
          ),
        ],
      ),
    ),
  );
}
