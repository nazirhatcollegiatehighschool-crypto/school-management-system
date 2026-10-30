import 'package:flutter/material.dart';

import '../api.dart';

class PromotionScreen extends StatefulWidget {
  const PromotionScreen({super.key});
  @override
  State<PromotionScreen> createState() => _PromotionScreenState();
}

class _PromotionScreenState extends State<PromotionScreen> {
  List<Map<String, dynamic>> _exams = [];
  List<Map<String, dynamic>> _review = [];
  int? _classId;
  int? _eventId;
  bool _loading = false;
  bool _loaded = false;
  String _error = '';
  String _eventName = '';
  List<String> _graceSubjects = [];
  List<Map<String, dynamic>> _groupApprovals = [];
  bool _groupLoading = false;

  String _eventKey(Map<String, dynamic> event) =>
      '${event['class_id']}-${event['event_id']}';

  @override
  void initState() {
    super.initState();
    _loadExams();
    _loadGroupApprovals();
  }

  Future<void> _loadGroupApprovals() async {
    if (mounted) setState(() => _groupLoading = true);
    try {
      final r = await Api.get('/teacher/group-approval');
      if (!mounted) return;
      setState(() {
        _groupApprovals =
            (r is Map && r['students'] is List
                    ? r['students'] as List
                    : const [])
                .whereType<Map>()
                .map((v) => Map<String, dynamic>.from(v))
                .toList();
        _groupLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _groupLoading = false,
        ); // Not every teacher is a Class 9 class teacher.
      }
    }
  }

  Future<void> _approveGroup(Map<String, dynamic> student) async {
    String? group, compulsory, optional;
    final choice = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text('${student['name']} — group approval'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: group,
                decoration: const InputDecoration(labelText: 'Group *'),
                items: const ['Arts', 'Commerce', 'Science']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setDialog(() {
                  group = v;
                  compulsory = null;
                  optional = null;
                }),
              ),
              if (group == 'Arts') ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: compulsory,
                  decoration: const InputDecoration(
                    labelText: 'Compulsory subject *',
                  ),
                  items: const ['Civics', 'Economics']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) => setDialog(() => compulsory = v),
                ),
              ],
              if (group != null && (group != 'Arts' || compulsory != null)) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: ValueKey(group),
                  initialValue: optional,
                  decoration: const InputDecoration(
                    labelText: 'Optional subject *',
                  ),
                  items:
                      (group == 'Science'
                              ? const [
                                  'Higher Mathematics',
                                  'Agriculture',
                                  'Home Science',
                                ]
                              : const ['Agriculture', 'Home Science'])
                          .map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          )
                          .toList(),
                  onChanged: (v) => setDialog(() => optional = v),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('বাতিল'),
            ),
            FilledButton(
              onPressed:
                  group == null ||
                      optional == null ||
                      (group == 'Arts' && compulsory == null)
                  ? null
                  : () => Navigator.pop(dialogContext, {
                      'group': group!,
                      'compulsory_subject': compulsory ?? '',
                      'optional_subject': optional!,
                    }),
              child: const Text('অনুমোদন করুন'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    try {
      await Api.post('/teacher/group-approval', {
        'student_id': student['student_id'],
        'from_class_id': student['from_class_id'],
        ...choice,
      });
      await _loadGroupApprovals();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${student['name']} ${choice['group']} group-এ গেছে'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _loadExams() async {
    if (_exams.isEmpty) {
      setState(() {
        _loading = true;
        _error = '';
      });
    }
    try {
      await Api.loadCachedFirst('/teacher/promotion/events', (data) {
        if (!mounted) return;
        final picks = (data is List ? data : <dynamic>[])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        final firstLoad = _exams.isEmpty;
        setState(() {
          _exams = picks;
          _loading = false;
        });
        if (firstLoad && _exams.isNotEmpty) {
          _classId = (_exams.first['class_id'] as num).toInt();
          _eventId = (_exams.first['event_id'] as num).toInt();
          _loadReview();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _loadReview() async {
    if (_classId == null || _eventId == null) return;
    if (!_loaded) {
      setState(() {
        _loading = true;
        _error = '';
      });
    }
    try {
      await Api.loadCachedFirst(
        '/teacher/promotion/review?class_id=$_classId&event_id=$_eventId',
        (data) {
          if (!mounted || data is! Map) return;
          setState(() {
            _review =
                (data['review'] is List
                        ? (data['review'] as List)
                        : <dynamic>[])
                    .cast<Map<String, dynamic>>();
            _graceSubjects = (data['grace_subjects'] as List? ?? const [])
                .map((value) => value.toString())
                .toList();
            _eventName = data['event']?['name']?.toString() ?? 'পরীক্ষা';
            _loaded = true;
            _loading = false;
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  String _decisionLabel(Map<String, dynamic> s) {
    final executed = s['executed'];
    if (executed == null) {
      if (s['grace_used'] == true) return 'প্রস্তাবিত: নির্বাচিত বিষয়ে Grace';
      if (s['decision'] == 'promoted') return 'প্রস্তাবিত: উত্তীর্ণ';
      return 'প্রস্তাবিত: রাখা হবে';
    }
    if (executed == 'promoted') return 'উত্তীর্ণ';
    if (executed == 'grace_promoted') return 'Grace-এ উত্তীর্ণ';
    if (executed == 'admin_override') return 'অ্যাডমিন সিদ্ধান্তে উত্তীর্ণ';
    return 'রাখা হয়েছে';
  }

  bool _isGreen(Map<String, dynamic> s) {
    final d = s['executed'] ?? s['decision'];
    return d == 'promoted' || d == 'grace_promoted' || d == 'admin_override';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Promotion review')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty && !_loaded && _groupApprovals.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(_error),
              ),
            )
          : _exams.isEmpty && _error.isEmpty && _groupApprovals.isEmpty
          ? const Center(
              child: Text('আপনার class-এর কোনো প্রকাশিত Annual/Test event নেই'),
            )
          : Column(
              children: [
                if (_groupApprovals.isNotEmpty || _groupLoading)
                  _groupApprovalPanel(),
                if (_exams.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: DropdownButtonFormField<String>(
                      initialValue: _classId == null || _eventId == null
                          ? null
                          : '$_classId-$_eventId',
                      decoration: const InputDecoration(
                        labelText: 'Promotion source event',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final e in _exams)
                          DropdownMenuItem<String>(
                            value: _eventKey(e),
                            child: Text(
                              '${e['name']} ${e['event_year'] ?? ''} • ${e['class_name']} ${e['section'] ?? e['group_name'] ?? ''}',
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        final pick = _exams.firstWhere(
                          (e) => _eventKey(e) == v,
                        );
                        setState(() {
                          _eventId = (pick['event_id'] as num).toInt();
                          _classId = (pick['class_id'] as num).toInt();
                        });
                        _loadReview();
                      },
                    ),
                  ),
                  if (_loaded)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$_eventName — Admin-এর প্রকাশিত subject-grace: ${_graceSubjects.isEmpty ? 'নেই' : _graceSubjects.join(', ')}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: _review.isEmpty && _loaded
                        ? const Center(child: Text('এই event-এ কোনো ফলাফল নেই'))
                        : ListView(
                            padding: const EdgeInsets.all(12),
                            children: [
                              for (int i = 0; i < _review.length; i++) ...[
                                if (i == 0 ||
                                    _review[i]['decision'] !=
                                        _review[i - 1]['decision'])
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 8,
                                      bottom: 2,
                                    ),
                                    child: Text(
                                      switch (_review[i]['decision']
                                          .toString()) {
                                        'promoted' => 'উত্তীর্ণের প্রস্তাব',
                                        'grace_promoted' =>
                                          'নির্বাচিত subject grace',
                                        _ => 'রাখা হবে',
                                      },
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: Colors.deepPurple,
                                      ),
                                    ),
                                  ),
                                _studentCard(_review[i]),
                              ],
                            ],
                          ),
                  ),
                ] else if (_groupApprovals.isEmpty && !_groupLoading)
                  const Expanded(
                    child: Center(child: Text('Class 10 promotion review নেই')),
                  ),
              ],
            ),
    );
  }

  Widget _groupApprovalPanel() => Card(
    margin: const EdgeInsets.fromLTRB(12, 8, 12, 2),
    child: Column(
      children: [
        ListTile(
          title: const Text(
            'Waiting for Group Approval',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: const Text(
            'Class 8-এর promoted student-দের result অনুযায়ী',
          ),
          trailing: IconButton(
            onPressed: _loadGroupApprovals,
            icon: const Icon(Icons.refresh),
          ),
        ),
        if (_groupLoading) const LinearProgressIndicator(),
        if (_groupApprovals.isNotEmpty)
          SizedBox(
            height: 250,
            child: ListView.builder(
              itemCount: _groupApprovals.length,
              itemBuilder: (context, index) {
                final row = _groupApprovals[index];
                return ListTile(
                  onTap: () => _approveGroup(row),
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    child: Text('${row['combined_rank'] ?? index + 1}'),
                  ),
                  title: Text('${row['name'] ?? ''}'),
                  subtitle: Text(
                    'Grade ${row['final_grade'] ?? '—'} · GPA ${row['final_gpa'] ?? 0} · মোট ${row['total_marks_obtained'] ?? 0}',
                  ),
                  trailing: TextButton(
                    onPressed: () => _approveGroup(row),
                    child: const Text('Group দিন'),
                  ),
                );
              },
            ),
          )
        else if (!_groupLoading)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('এখন কোনো student অপেক্ষায় নেই'),
          ),
      ],
    ),
  );

  Widget _studentCard(Map<String, dynamic> s) {
    final green = _isGreen(s);
    final fails = (s['failed_subjects'] is List
        ? (s['failed_subjects'] as List)
        : <dynamic>[]);
    final roll = s['promoted_roll'];
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: green ? Colors.green.shade50 : Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${s['name']} • রোল ${s['roll']}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'GPA ${((s['final_gpa'] as num?) ?? 0).toStringAsFixed(2)} • ${s['result_status']}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  if (fails.isNotEmpty)
                    Text(
                      'ফেল: ${fails.join(', ')}',
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            (s['ungraced_failed_subjects'] as List? ?? const [])
                                .isEmpty
                            ? Colors.teal
                            : Colors.deepOrange,
                      ),
                    ),
                  if ((s['grace_failed_subjects'] as List? ?? const [])
                      .isNotEmpty)
                    Text(
                      'নির্বাচিত Grace: ${(s['grace_failed_subjects'] as List).join(', ')}',
                      style: const TextStyle(fontSize: 11, color: Colors.teal),
                    ),
                  if (s['executed'] != null)
                    Text(
                      'Admin-এর promotion history: ${s['promoted_to_class'] ?? ''} ${s['promoted_to_section'] ?? ''} • রোল ${s['promoted_roll'] ?? '—'}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.blueGrey,
                      ),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _decisionLabel(s),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: green
                        ? Colors.green.shade800
                        : Colors.orange.shade900,
                  ),
                ),
                if (roll != null)
                  Text(
                    'নতুন SSC রোল: $roll',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.green.shade800,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
