import 'dart:convert';

import 'package:flutter/material.dart';

import '../api.dart';

class DeleteLogsScreen extends StatefulWidget {
  const DeleteLogsScreen({super.key});
  @override
  State<DeleteLogsScreen> createState() => _DeleteLogsScreenState();
}

class _DeleteLogsScreenState extends State<DeleteLogsScreen> {
  List _rows = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  Future<void> _load({bool append = false}) async {
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
        _hasMore = true;
      }
    });
    try {
      final before = append && _rows.isNotEmpty
          ? '&before=${_rows.last['id']}'
          : '';
      final r = await Api.get('/admin/delete-logs?limit=100$before');
      if (mounted)
        setState(() {
          final page = r is List ? r : [];
          _rows = append ? [..._rows, ...page] : page;
          _hasMore = page.length == 100;
          _loading = false;
          _loadingMore = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
          _loadingMore = false;
        });
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('স্থায়ী delete log'),
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(child: Text(_error!))
        : _rows.isEmpty
        ? const Center(child: Text('এখনো কোনো student বা exam delete log নেই।'))
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _rows.length + (_hasMore ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _rows.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: _loadingMore
                          ? const CircularProgressIndicator()
                          : OutlinedButton.icon(
                              onPressed: () => _load(append: true),
                              icon: const Icon(Icons.expand_more),
                              label: const Text('আরও পুরোনো log দেখুন'),
                            ),
                    ),
                  );
                }
                final row = Map<String, dynamic>.from(_rows[i] as Map);
                dynamic detail;
                try {
                  detail = jsonDecode('${row['detail']}');
                } catch (_) {
                  detail = {};
                }
                final isStudent = row['action'] == 'student_delete';
                final isExam = row['action'] == 'exam_delete';
                final title = isStudent
                    ? (detail['student']?['name'] ?? 'Deleted student')
                    : isExam
                    ? (detail['exam']?['name'] ?? 'Deleted exam subject')
                    : (detail['event']?['name'] ?? 'Deleted exam');
                final deletedAt =
                    detail['deleted_at'] ?? row['created_at'] ?? '';
                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ExpansionTile(
                    leading: CircleAvatar(
                      backgroundColor: isStudent
                          ? Colors.orange.shade50
                          : Colors.red.shade50,
                      child: Icon(
                        isStudent
                            ? Icons.person_remove_alt_1
                            : Icons.event_busy,
                        color: isStudent ? Colors.deepOrange : Colors.red,
                      ),
                    ),
                    title: Text(
                      '$title',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${isStudent
                          ? 'শিক্ষার্থী'
                          : isExam
                          ? 'বিষয়ভিত্তিক পরীক্ষা'
                          : 'পরীক্ষা'}  ·  ${row['admin_name'] ?? detail['deleted_by']?['name'] ?? 'Admin'}  ·  $deletedAt',
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      _line('কারণ', detail['reason']),
                      if (isStudent && detail['student'] is Map) ...[
                        _line(
                          'শ্রেণি',
                          '${detail['student']['class_name'] ?? ''} ${detail['student']['class_section'] ?? ''}',
                        ),
                        _line(
                          'Student code',
                          detail['student']['student_code'],
                        ),
                        _line('Roll', detail['student']['roll']),
                        _line(
                          'Attendance record',
                          (detail['attendance'] as List? ?? []).length,
                        ),
                        _line(
                          'Marks record',
                          (detail['marks'] as List? ?? []).length,
                        ),
                        _line(
                          'Daily report',
                          (detail['daily_reports'] as List? ?? []).length,
                        ),
                        _line(
                          'Promotion record',
                          (detail['promotions'] as List? ?? []).length,
                        ),
                      ],
                      if (!isStudent && detail['event'] is Map) ...[
                        _line(
                          'Academic session',
                          detail['event']['session_id'],
                        ),
                        _line('Exam type', detail['event']['exam_kind']),
                        _line('Exam year', detail['event']['year']),
                        _line(
                          'Subjects',
                          (detail['exams'] as List? ?? []).length,
                        ),
                        _line('Marks', (detail['marks'] as List? ?? []).length),
                        _line(
                          'Result records',
                          (detail['results'] as List? ?? []).length,
                        ),
                      ],
                      if (isExam && detail['exam'] is Map) ...[
                        _line('Academic session', detail['exam']['session_id']),
                        _line('Exam type', detail['exam']['exam_kind']),
                        _line('Exam year', detail['exam']['year']),
                        _line(
                          'Class',
                          '${detail['exam']['class_name'] ?? ''} ${detail['exam']['section'] ?? ''}',
                        ),
                        _line('Subject', detail['exam']['subject_name']),
                        _line(
                          'Marks record',
                          (detail['marks'] as List? ?? []).length,
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
  );

  Widget _line(String label, dynamic value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            '$label:',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: Text('${value ?? '—'}')),
      ],
    ),
  );
}
