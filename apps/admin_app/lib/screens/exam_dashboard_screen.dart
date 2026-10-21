import 'package:flutter/material.dart';
import '../api.dart';
import '../pdf/admin_pdfs.dart';
import '../pdf/app_pdf.dart';

class ExamDashboardScreen extends StatefulWidget {
  const ExamDashboardScreen({super.key});
  @override
  State<ExamDashboardScreen> createState() => _ExamDashboardScreenState();
}

class _ExamDashboardScreenState extends State<ExamDashboardScreen> {
  List _events = [];
  bool _loading = true;
  String? _error;
  int? _expandedEvent;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await Api.get('/admin/exam-dashboard');
      setState(() {
        _events = r['events'] is List ? r['events'] : [];
        _loading = false;
        _error = null;
      });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  String _kindLabel(String kind) {
    switch (kind) {
      case 'half_yearly': return 'Half Yearly';
      case 'annual': return 'Annual';
      case 'pretest': return 'Pre-Test';
      case 'test': return 'Test';
      default: return kind;
    }
  }

  Color _kindColor(String kind) {
    switch (kind) {
      case 'half_yearly': return Colors.blue;
      case 'annual': return Colors.purple;
      case 'pretest': return Colors.orange;
      case 'test': return Colors.red;
      default: return Colors.grey;
    }
  }

  String _fmtD(dynamic d) => d == null ? '—' : '$d'.substring(0, 10);

  Future<void> _toggleEntry(int eventId, int newValue) async {
    try {
      await Api.post('/results/events/$eventId/entry-open', {'open': newValue});
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.red,
        content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _publishEvent(Map ev, bool notify) async {
    final id = ev['id'];
    try {
      final r = await Api.post('/results/events/$id/publish', {'notify_guardians': notify});
      if (!mounted) return;
      _load();
      final already = r['already_notified'] == true;
      String msg;
      if (already) {
        msg = '"${ev['name']}" Published (already notified).';
      } else {
        msg = notify ? '"${ev['name']}" Published! Guardians notified (${r['notified']}).' : '"${ev['name']}" Published!';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.green,
        content: Text(msg),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.red,
        content: Text(e.toString().replaceFirst('Exception: ', ''))));
}
}

Future<void> _showCoverage(Map ev) async {
    final id = ev['id'];
    try {
      final r = await Api.get('/results/events/$id/coverage');
      if (!mounted) return;
      showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => CoverageBottomSheet(data: r));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.red,
        content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exam Session Dashboard', style: TextStyle(fontSize: 16)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(icon: const Icon(Icons.analytics), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AnalyticsScreen()))),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : _events.isEmpty
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.event_busy, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('No exam sessions found', style: TextStyle(fontSize: 16, color: Colors.grey)),
                      const SizedBox(height: 8),
                      FilledButton.icon(icon: const Icon(Icons.add), label: const Text('Create Session'), onPressed: _showCreateSession),
                    ]))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _events.length,
                        itemBuilder: (_, i) => _buildEventCard(_events[i]),
                      ),
                    ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New Session'),
        onPressed: _showCreateSession,
      ),
    );
  }

  Widget _buildEventCard(Map ev) {
    final published = ev['is_published'] == 1;
    final kind = ev['exam_kind'] ?? 'other';
    final hasEntryOpen = ((ev['entry_open_count'] as num?)?.toInt() ?? 0) > 0;
    final isExpanded = _expandedEvent == ev['id'];
    final eventId = ev['id'] as int;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: published ? Colors.green.shade50 : Colors.blueGrey.shade50,
      child: Column(
        children: [
          // Event Header Banner
          InkWell(
            onTap: () => setState(() => _expandedEvent = isExpanded ? null : eventId),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Kind badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _kindColor(kind),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(_kindLabel(kind), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                  const SizedBox(width: 12),
                  // Session info
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(ev['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 2),
                      Wrap(spacing: 8, children: [
                        Chip(label: Text('Year: ${ev['year'] ?? '—'}'), backgroundColor: Colors.white, labelStyle: const TextStyle(fontSize: 11)),
                        Chip(label: Text(ev['session_name'] ?? ''), backgroundColor: Colors.white, labelStyle: const TextStyle(fontSize: 11)),
                        if (published) Chip(label: const Text('Published', style: TextStyle(fontSize: 11, color: Colors.green)), backgroundColor: Colors.green.shade100),
                        if (!published && hasEntryOpen) Chip(label: const Text('Entry Open', style: TextStyle(fontSize: 11, color: Colors.blue)), backgroundColor: Colors.blue.shade100),
                      ]),
                    ]),
                  ),
                  // Quick actions
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    if (!published) ...[
                      IconButton(
                        icon: Icon(hasEntryOpen ? Icons.lock_open : Icons.lock, color: hasEntryOpen ? Colors.green : Colors.grey),
                        tooltip: 'Toggle Teacher Entry',
                        onPressed: () => _toggleEntry(ev['id'], hasEntryOpen ? 0 : 1),
                      ),
                      IconButton(
                        icon: const Icon(Icons.publish, color: Colors.blue),
                        tooltip: 'Publish Exam',
                        onPressed: () => _showPublishDialog(ev),
                      ),
                    ],
                    IconButton(
                      icon: Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
                      onPressed: () => setState(() => _expandedEvent = isExpanded ? null : ev['id']),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          // Expanded details
          if (isExpanded)
            Column(
              children: [
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: _buildEventDetails(ev),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildEventDetails(Map ev) {
    final classes = ev['classes'] as List? ?? [];
    final eventId = ev['id'] as int;

    if (classes.isEmpty) {
      return Column(children: [
        const Text('No classes assigned to this session', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 8),
        FilledButton.icon(icon: const Icon(Icons.settings), label: const Text('Assign Classes'), onPressed: () => _showAssignClasses(ev)),
      ]);
    }

    return Column(
      children: [
        // Progress summary
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
          child: Column(
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _statChip('Classes', '${classes.length}'),
                _statChip('Subjects', '${classes.fold<int>(0, (sum, c) => sum + ((c['subject_count'] as num?)?.toInt() ?? 0))}'),
                _statChip('Students', '${ev['total_students'] ?? 0}'),
                _statChip('Entry %', '${((ev['entry_open_count'] as num? ?? 0) / (ev['exam_count'] as num? ?? 1) * 100).round()}%'),
              ]),
              const SizedBox(height: 8),
              if (ev['entry_deadline'] != null)
                Text('Entry Deadline: ${_fmtD(ev['entry_deadline'])}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Classes list
        for (final c in classes) _buildClassCard(c, eventId),
        const SizedBox(height: 8),
        // Actions
        Row(children: [
          Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.analytics), label: const Text('Coverage'), onPressed: () => _showCoverage(ev))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.picture_as_pdf), label: const Text('All PDFs'), onPressed: () => _generateAllPdfs(ev))),
          const SizedBox(width: 8),
          Expanded(child: FilledButton.icon(icon: const Icon(Icons.auto_fix_high), label: const Text('Auto-Create Missing'), onPressed: () => _autoCreateSubjects(ev))),
        ]),
      ],
    );
  }

  Widget _statChip(String label, String value) => Column(children: [
    Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
  ]);

  Widget _buildClassCard(Map c, int eventId) {
    final subjectCount = c['subject_count'] as num? ?? 0;
    final subjectsWithMarks = c['subjects_with_marks'] as num? ?? 0;
    final studentCount = c['student_count'] as num? ?? 0;
    final studentsWithMarks = c['students_with_marks'] as num? ?? 0;
    final subjects = c['subjects'] as List? ?? [];
    final ready = c['ready'] == true;
    final subjPct = c['subject_pct'] as num? ?? 0;
    final stuPct = c['student_pct'] as num? ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: ready ? Colors.green : (subjPct > 0 ? Colors.orange : Colors.grey),
          child: Text('$subjectCount', style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),
        title: Text('${c['class_name']} ${c['group_name'] ?? c['section'] ?? ''}'),
        subtitle: Text('Students: $studentCount | Subjects: $subjectCount | Subj: $subjectsWithMarks/$subjectCount | Stu: $studentsWithMarks/$studentCount'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (ready) const Icon(Icons.check_circle, color: Colors.green, size: 20),
          Chip(label: Text('$subjPct% | $stuPct%'), backgroundColor: ready ? Colors.green.shade100 : Colors.orange.shade100, labelStyle: const TextStyle(fontSize: 11)),
        ]),
        children: [
          // Subject progress bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                LinearProgressIndicator(value: subjPct / 100, backgroundColor: Colors.grey.shade200, color: Colors.blue, minHeight: 6),
                const SizedBox(height: 4),
                Text('Subject Progress: $subjectsWithMarks / $subjectCount (${subjPct}%)', style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          // Subjects list
          for (final s in subjects) _buildSubjectRow(s, eventId, c['class_id']),
          // Actions
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.analytics), label: const Text('Coverage'), onPressed: () => _showClassCoverage(context, eventId, c['class_id']))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.picture_as_pdf), label: const Text('Class PDF'), onPressed: () => _generateClassPdf(context, eventId, c['class_id']))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton.icon(icon: const Icon(Icons.edit), label: const Text('Marks Entry'), onPressed: () => _openMarksEntry(context, c['class_id'], eventId))),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectRow(Map s, int eventId, int classId) {
    final entered = s['entered_count'] as num? ?? 0;
    final total = s['student_count'] as num? ?? 0;
    final published = s['exam_published'] == true;
    final entryOpen = s['entry_open'] == 1;
    final isMine = s['subject_mine'] == 1;
    final deadline = s['exam_entry_deadline']?.toString();
    final closed = published || !entryOpen || (deadline != null && deadline.isNotEmpty && _pastDeadline(deadline));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(s['subject_name'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            if (isMine) const Padding(padding: EdgeInsets.only(left: 4), child: Text('(Mine)', style: TextStyle(fontSize: 11, color: Colors.blue))),
          ]),
          Text(
            published ? 'Published' : (!entryOpen ? 'Entry Closed' : (deadline != null && _pastDeadline(deadline) ? 'Deadline Passed' : 'Entry Open')),
            style: TextStyle(fontSize: 11, color: closed ? Colors.red : Colors.green),
          ),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: (entered > 0) ? Colors.green.shade100 : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('$entered/$total', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: entered > 0 ? Colors.green.shade800 : Colors.grey.shade700)),
        ),
        const SizedBox(width: 8),
        FilledButton.tonal(
          style: FilledButton.styleFrom(minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
          onPressed: closed && !isMine ? null : () => _openSubjectEntry(context, s, classId, eventId),
          child: Text(published ? 'View' : (isMine ? 'Entry' : 'Open'), style: const TextStyle(fontSize: 11)),
        ),
      ]),
    );
  }

  void _showCreateSession() {
    final nameCtrl = TextEditingController();
    String kind = 'test';
    int? sessionId;
    int? year;
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Create Exam Session'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Session Name *', border: OutlineInputBorder())),
        DropdownButtonFormField<String>(initialValue: kind, decoration: const InputDecoration(labelText: 'Kind', border: OutlineInputBorder()),
          items: ['half_yearly', 'annual', 'pretest', 'test', 'other'].map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
          onChanged: (v) => kind = v!),
        FutureBuilder<dynamic>(future: Api.get('/admin/sessions'), builder: (_, snap) {
          if (!snap.hasData) return const SizedBox();
          final sessions = snap.data as List;
          return DropdownButtonFormField<int>(initialValue: sessionId, decoration: const InputDecoration(labelText: 'Academic Session', border: OutlineInputBorder()),
            items: sessions.map<DropdownMenuItem<int>>((s) => DropdownMenuItem(value: s['id'] as int, child: Text(s['name'] as String))).toList(),
            onChanged: (v) => sessionId = v);
        }),
        TextField(decoration: const InputDecoration(labelText: 'Year (e.g., 2026)', border: OutlineInputBorder()), keyboardType: TextInputType.number,
          onChanged: (v) => year = int.tryParse(v)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          try {
            await Api.post('/results/events', {'name': nameCtrl.text.trim(), 'exam_kind': kind, 'session_id': sessionId, 'year': year});
            Navigator.pop(context);
            _load();
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session created')));
          } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text(e.toString()))); }
        }, child: const Text('Create')),
      ],
    ));
  }

  void _showPublishDialog(Map ev) {
    bool notify = true;
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text('Publish "${ev['name']}"?'),
      content: CheckboxListTile(title: const Text('Notify guardians'), value: notify, onChanged: (v) => setState(() => notify = v!)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () { Navigator.pop(context); _publishEvent(ev, notify); }, child: const Text('Publish')),
      ],
    ));
  }

  void _showAssignClasses(Map ev) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Assign Classes - coming soon')));
  }

  Future<void> _autoCreateSubjects(Map ev) async {
    try {
      final r = await Api.post('/admin/auto-create-subject-exams', {'event_id': ev['id']});
      if (!mounted) return;
      _load();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.green, content: Text('Created ${r['created']} subject exams')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text(e.toString())));
    }
  }

  void _generateAllPdfs(Map ev) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All PDFs - coming soon')));
  }

  void _generateClassPdf(BuildContext context, int eventId, int classId) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Class PDF - coming soon')));
  }

  void _showClassCoverage(BuildContext context, int eventId, int classId) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Class coverage - coming soon')));
  }

  void _openMarksEntry(BuildContext context, int classId, int eventId) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marks entry - coming soon')));
  }

  void _openSubjectEntry(BuildContext context, Map s, int classId, int eventId) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Subject entry - coming soon')));
  }

  bool _pastDeadline(String raw) {
    try { return DateTime.now().isAfter(DateTime.parse(raw.replaceAll(' ', 'T'))); } catch (_) { return false; }
  }
}

class CoverageBottomSheet extends StatelessWidget {
  final Map data;
  const CoverageBottomSheet({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final classes = data['classes'] as List? ?? [];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Coverage: ${data['event_ready'] == true ? 'Ready to Publish' : 'Not Ready'}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        for (final c in classes) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${c['class_name']} ${c['section']}', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('Subjects: ${c['subjects_with_marks']}/${c['subject_count']} | Students: ${c['students_with_marks']}/${c['student_count']}'),
          Text(c['ready'] == true ? 'Ready' : 'Missing: ${c["gaps"] ?? []}'),
        ]))),
        const SizedBox(height: 16),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ]),
    );
  }
}

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.analytics, size: 64, color: Colors.grey),
        const SizedBox(height: 16),
        const Text('Analytics Dashboard', style: TextStyle(fontSize: 18)),
        const SizedBox(height: 8),
        const Text('Coming soon: Class pass%, GPA trends, teacher workload', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 24),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
      ])),
    );
  }
}