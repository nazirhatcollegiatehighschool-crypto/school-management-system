import 'package:flutter/material.dart';

import '../api.dart';

class StudentProfileScreen extends StatefulWidget {
  final int studentId;
  final String studentName;
  const StudentProfileScreen({
    super.key,
    required this.studentId,
    required this.studentName,
  });
  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen> {
  Map? _data;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.get(
        '/teacher/students/${widget.studentId}/profile-history',
      );
      if (mounted) setState(() => _data = r is Map ? r : {});
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.studentName)),
    body: _data == null
        ? Center(
            child: _error == null
                ? const CircularProgressIndicator()
                : Text(_error!),
          )
        : RefreshIndicator(onRefresh: _load, child: _body()),
  );

  Widget _body() {
    final data = _data!;
    final student = Map<String, dynamic>.from(data['student'] as Map? ?? {});
    final attendance = Map<String, dynamic>.from(
      data['attendance'] as Map? ?? {},
    );
    final reports = data['daily_reports'] as List? ?? [];
    final complaints = data['complaints'] as List? ?? [];
    final repeats = data['repeated_classes'] as List? ?? [];
    final scholarship =
        student['receives_scholarship'] == true ||
        student['receives_scholarship'] == 1;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF27396F), Color(0xFF6657D9)],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${student['name'] ?? widget.studentName}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${student['class_name'] ?? ''} (${student['section'] ?? ''})  ·  Roll ${student['roll'] ?? '—'}',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _pill('উপস্থিত ${attendance['attended_days'] ?? 0} দিন'),
                  _pill('অনুপস্থিত ${attendance['absent_days'] ?? 0} দিন'),
                  _pill(
                    'Uniform আনেনি ${data['uniform_missing_reports'] ?? 0} বার',
                  ),
                  if (scholarship) _pill('উপবৃত্তি পায়'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (repeats.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'একই শ্রেণিতে থাকার ইতিহাস',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  for (final r in repeats)
                    if (r is Map)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.history,
                          color: Colors.orange,
                        ),
                        title: Text(
                          '${r['from_class'] ?? 'শ্রেণি'} → ${r['to_class'] ?? 'একই শ্রেণি'}',
                        ),
                        subtitle: Text(
                          '${r['decision'] ?? ''}  ·  ${r['passing_year'] ?? ''}',
                        ),
                      ),
                ],
              ),
            ),
          ),
        _section(
          'তারিখভিত্তিক পড়া ও performance',
          reports,
          (r) =>
              '${r['report_date']} · ${r['subject_name']}\nপড়া: ${r['homework_status'] == 'done' ? 'করেছে' : 'করেনি'}  ·  শেখা: ${r['learning_status']}  ·  performance: ${r['performance']}\nUniform: ${r['uniform_brought'] == true || r['uniform_brought'] == 1 ? 'এনেছে' : 'আনেনি'}${(r['note'] ?? '').toString().isEmpty ? '' : '\nনোট: ${r['note']}'}',
        ),
        _section(
          'শিক্ষকদের অভিযোগ',
          complaints,
          (r) =>
              '${r['title']}\n${r['teacher_name'] ?? ''}  ·  ${r['created_at'] ?? ''}\n${r['body'] ?? ''}',
        ),
      ],
    );
  }

  Widget _pill(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .15),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
    ),
  );

  Widget _section(String title, List rows, String Function(Map) body) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'এখনো কোনো record নেই',
                style: TextStyle(color: Colors.blueGrey),
              ),
            ),
          for (final raw in rows)
            if (raw is Map)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_note_outlined),
                title: Text(body(Map.from(raw))),
                isThreeLine: true,
              ),
        ],
      ),
    ),
  );
}
