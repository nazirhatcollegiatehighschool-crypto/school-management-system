import 'package:flutter/material.dart';
import '../api.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PromotionScreen extends StatefulWidget {
  const PromotionScreen({super.key});
  @override
  State<PromotionScreen> createState() => _PromotionScreenState();
}

class _PromotionScreenState extends State<PromotionScreen> {
  int _sessionId = 0;
  int _classId = 9;
  List<Map<String, dynamic>> _students = [];
  bool _loading = false;
  String _error = '';

  static const _buckets = [
    (label: 'Pass (All Subjects)', threshold: 0),
    (label: '1-2 Subject Fail (Conditional)', threshold: 1),
    (label: '3+ Subject Fail (Retained)', threshold: 3),
  ];

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _sessionId = prefs.getInt('session_id') ?? 0;
    });
    if (_sessionId > 0) _loadReview();
  }

  int _failCount(Map<String, dynamic> s) {
    final fails = (s['condition'] as String?)?.isNotEmpty == true;
    return fails ? 1 : 0;
  }

  Future<void> _loadReview() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final data = await Api.promoteReview(_classId, _sessionId);
      final list = (data is List)
          ? List<Map<String, dynamic>>.from(data)
          : <Map<String, dynamic>>[];
      list.sort((a, b) =>
          (b['total_marks'] as num? ?? 0).compareTo(a['total_marks'] as num? ?? 0));
      setState(() {
        _students = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  List<Map<String, dynamic>> _bucket(int threshold) {
    return _students
        .where((s) => _failCount(s) >= threshold)
        .toList()
      ..sort((a, b) =>
          (b['total_marks'] as num? ?? 0).compareTo(a['total_marks'] as num? ?? 0));
  }

  void _promote(String id, String name) {
    Api.promoteExecute({
      'student_ids': [int.tryParse(id) ?? 0],
      'new_class_id': _classId + 1,
      'new_session_id': _sessionId + 1,
      'admin_note': 'Promoted via Teacher App (Phase D)',
    }).then((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name promoted')),
        );
      }
    }).catchError((e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isTen = _classId == 10;
    return Scaffold(
      appBar: AppBar(
        title: Text(isTen ? 'Promotion  →  SSC' : 'Promotion Review'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _sessionId > 0 ? _loadReview : null,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(child: Text(_error))
              : ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Class 9'),
                            selected: _classId == 9,
                            onSelected: (_) {
                              setState(() => _classId = 9);
                              _loadReview();
                            },
                          ),
                          ChoiceChip(
                            label: const Text('Class 10'),
                            selected: _classId == 10,
                            onSelected: (_) {
                              setState(() => _classId = 10);
                              _loadReview();
                            },
                          ),
                          if (_sessionId > 0)
                            Chip(label: Text('Session $_sessionId')),
                        ],
                      ),
                    ),
                    for (final bucket in _buckets)
                      _BucketSection(
                        title: bucket.label,
                        students: _bucket(bucket.threshold),
                        isSscBucket: isTen,
                        hasNoteField: bucket.threshold == 1,
                        onPromote: _promote,
                      ),
                  ],
                ),
    );
  }
}

class _BucketSection extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> students;
  final bool isSscBucket;
  final bool hasNoteField;
  final void Function(String id, String name) onPromote;

  const _BucketSection({
    required this.title,
    required this.students,
    required this.isSscBucket,
    required this.hasNoteField,
    required this.onPromote,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...students.isEmpty
                ? [const Padding(padding: EdgeInsets.all(8), child: Text('No students'))]
                : [
                    for (final s in students)
                      ListTile(
                        dense: true,
                        title: Text('${s['name']}  ·  Roll ${s['roll']}'),
                        subtitle: Row(children: [
                          Text('Total: ${s['total_marks'] ?? 0}'),
                          if (isSscBucket && ((s['student_class'] as num?) ?? 0) >= 12)
                            const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Chip(label: Text('SSC')),
                            ),
                        ]),
                        trailing: TextButton(
                          onPressed: () => onPromote(
                            '${s['id']}',
                            '${s['name']}',
                          ),
                          child: const Text('Promote'),
                        ),
                      ),
                  ],
          ],
        ),
      ),
    );
  }
}
