import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../api.dart';
import '../pdf/app_pdf.dart';

class ExamDashboardScreen extends StatefulWidget {
  const ExamDashboardScreen({super.key});
  @override
  State<ExamDashboardScreen> createState() => _ExamDashboardScreenState();
}

class _ExamDashboardScreenState extends State<ExamDashboardScreen> {
  List _events = [];
  List _sessions = [];
  int? _selectedSessionId;
  int? _currentAcademicYear;
  bool _loading = true;
  String? _error;
  int? _expandedEvent;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({int? preferredSessionYear}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Api.get('/admin/exam-dashboard');
      setState(() {
        _events = r['events'] is List ? r['events'] : [];
        _sessions = r['sessions'] is List ? r['sessions'] : [];
        _currentAcademicYear = (r['current_year'] as num?)?.toInt();
        final preferredSessions = preferredSessionYear == null
            ? <dynamic>[]
            : _sessions
                  .where(
                    (s) => (s['year'] as num?)?.toInt() == preferredSessionYear,
                  )
                  .toList();
        final preferred = preferredSessions.isEmpty
            ? null
            : preferredSessions.first;
        if (preferred != null) {
          _selectedSessionId = (preferred['id'] as num?)?.toInt();
        } else if (_selectedSessionId == null ||
            !_sessions.any(
              (s) => (s['id'] as num?)?.toInt() == _selectedSessionId,
            )) {
          final active = _sessions
              .where((s) => s['is_active'] == true || s['is_active'] == 1)
              .toList();
          final defaultSession = active.isNotEmpty
              ? active.first
              : (_sessions.isNotEmpty ? _sessions.first : null);
          _selectedSessionId = (defaultSession?['id'] as num?)?.toInt();
        }
        _loading = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  List get _sessionEvents => _selectedSessionId == null
      ? _events
      : _events
            .where(
              (e) => (e['session_id'] as num?)?.toInt() == _selectedSessionId,
            )
            .toList();

  String _kindLabel(String kind) {
    switch (kind) {
      case 'half_yearly':
        return 'Half Yearly';
      case 'annual':
        return 'Annual';
      case 'pretest':
        return 'Pre-Test';
      case 'test':
        return 'Test';
      case 'special_model_test':
        return 'Special Model Test';
      default:
        return kind;
    }
  }

  Color _kindColor(String kind) {
    switch (kind) {
      case 'half_yearly':
        return Colors.blue;
      case 'annual':
        return Colors.purple;
      case 'pretest':
        return Colors.orange;
      case 'test':
        return Colors.red;
      case 'special_model_test':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  String _fmtD(dynamic d) => d == null ? '—' : '$d'.substring(0, 10);

  Future<void> _toggleEntry(int eventId, int newValue) async {
    try {
      await Api.post('/results/events/$eventId/entry-open', {'open': newValue});
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _toggleSubjectEntry(int examId, bool open) async {
    try {
      await Api.put('/admin/exams/$examId/entry', {'entry_open': open ? 1 : 0});
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _deleteEvent(Map event) async {
    final reasonCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('পরীক্ষা মুছে ফেলবেন?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${event['name']} এবং এর নম্বর/ফলাফলও মুছে যাবে। সম্পূর্ণ তথ্য ও কারণ স্থায়ী delete log-এ থাকবে।',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Delete করার কারণ *',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              if (reasonCtl.text.trim().isEmpty) {
                ScaffoldMessenger.of(dialogContext)
                    .showSnackBar(const SnackBar(content: Text('কারণ লিখুন।')));
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: const Text('স্থায়ীভাবে মুছুন'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await Api.delete(
        '/results/events/${event['id']}',
        body: {'reason': reasonCtl.text.trim()},
      );
      if (!mounted) return;
      setState(() => _expandedEvent = null);
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'পরীক্ষা delete হয়েছে; full record delete log-এ রাখা হয়েছে।',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _publishEvent(
    Map ev,
    bool notify,
    List<Map<String, dynamic>> graceSubjects,
  ) async {
    final id = ev['id'];
    try {
      final r = await Api.post('/results/events/$id/publish', {
        'notify_guardians': notify,
        'grace_subjects': graceSubjects,
      });
      var graceMoved = 0;
      final review = r['promotion_review'];
      if (review is Map && (review['auto_approved'] as num? ?? 0) > 0) {
        final moved = await Api.post('/admin/promotion/execute', {
          'target_session_id': review['target_session_id'],
          'source_event_id': id,
        });
        graceMoved = (moved['moved'] as num?)?.toInt() ?? 0;
      }
      if (!mounted) return;
      final nextYear = int.tryParse('${r['next_year_session'] ?? ''}');
      await _load(preferredSessionYear: nextYear);
      final already = r['already_notified'] == true;
      String msg;
      if (already) {
        msg = '"${ev['name']}" Published (already notified).';
      } else {
        msg = notify
            ? '"${ev['name']}" Published! Guardians notified (${r['notified']}).'
            : '"${ev['name']}" Published!';
      }
      if (graceMoved > 0) msg += ' Grace-এ $graceMoved জন পরের শ্রেণিতে গেছেন।';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.green, content: Text(msg)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _showCoverage(Map ev) async {
    final id = ev['id'];
    try {
      final r = await Api.get('/results/events/$id/coverage');
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => CoverageBottomSheet(data: r),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedSession = _sessions.cast<Map>().firstWhere(
      (s) => (s['id'] as num?)?.toInt() == _selectedSessionId,
      orElse: () => const {},
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Exam Session Dashboard',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(
            icon: const Icon(Icons.analytics),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
          : _events.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.event_busy, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'কোনো পরীক্ষা নেই। আগে একাডেমিক সেশন তৈরি করুন।',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('নতুন সেশন'),
                    onPressed: _showCreateSession,
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _load(),
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (_sessions.isNotEmpty)
                    DropdownButtonFormField<int>(
                      initialValue:
                          _sessions.any(
                            (s) =>
                                (s['id'] as num?)?.toInt() ==
                                _selectedSessionId,
                          )
                          ? _selectedSessionId
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'একাডেমিক সেশন',
                        border: OutlineInputBorder(),
                      ),
                      items: _sessions
                          .map<DropdownMenuItem<int>>(
                            (s) => DropdownMenuItem<int>(
                              value: (s['id'] as num).toInt(),
                              child: Text(
                                '${s['name']}${s['is_active'] == true || s['is_active'] == 1 ? ' · বর্তমান' : ''}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _selectedSessionId = value),
                    ),
                  const SizedBox(height: 12),
                  if (selectedSession['is_open'] != true)
                    Card(
                      color: Colors.orange.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '${selectedSession['blocked_reason'] ?? 'আগের session-এর Class 10 Test exam publish হওয়ার পর এই session খুলবে।'}',
                          style: TextStyle(color: Colors.orange.shade900),
                        ),
                      ),
                    )
                  else if (_sessionEvents.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 38),
                      child: Center(
                        child: Text(
                          'এই শিক্ষাবর্ষে কোনো পরীক্ষার event নেই।',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
                  for (final event in _sessionEvents) _buildEventCard(event),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('নতুন একাডেমিক সেশন'),
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
    final sessionYear = RegExp(r'(19|20)\d{2}')
        .firstMatch(ev['session_name']?.toString() ?? '')
        ?.group(0);
    final examYear = ev['year']?.toString();
    final yearMismatch =
        sessionYear != null && examYear != null && sessionYear != examYear;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: published ? Colors.green.shade50 : Colors.blueGrey.shade50,
      child: Column(
        children: [
          // Event Header Banner
          InkWell(
            onTap: () =>
                setState(() => _expandedEvent = isExpanded ? null : eventId),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Kind badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _kindColor(kind),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _kindLabel(kind),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Session info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ev['name']?.toString() ?? 'পরীক্ষা',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Wrap(
                          spacing: 8,
                          children: [
                            Chip(
                              label: Text('বছর ${ev['year'] ?? '—'}'),
                              backgroundColor: Colors.white,
                              labelStyle: const TextStyle(fontSize: 11),
                            ),
                            if ((ev['session_name']?.toString() ?? '')
                                .isNotEmpty)
                              Chip(
                                label: Text('সেশন ${ev['session_name']}'),
                                backgroundColor: Colors.white,
                                labelStyle: const TextStyle(fontSize: 11),
                              ),
                            if (yearMismatch)
                              const Chip(
                                label: Text(
                                  'বছর মিলছে না',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.deepOrange,
                                  ),
                                ),
                                backgroundColor: Color(0xFFFFF1E6),
                              ),
                            if (published)
                              Chip(
                                label: const Text(
                                  'Published',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.green,
                                  ),
                                ),
                                backgroundColor: Colors.green.shade100,
                              ),
                            if (!published && hasEntryOpen)
                              Chip(
                                label: const Text(
                                  'Entry Open',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blue,
                                  ),
                                ),
                                backgroundColor: Colors.blue.shade100,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Quick actions
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!published) ...[
                        IconButton(
                          icon: Icon(
                            hasEntryOpen ? Icons.lock_open : Icons.lock,
                            color: hasEntryOpen ? Colors.green : Colors.grey,
                          ),
                          tooltip: 'Toggle Teacher Entry',
                          onPressed: () =>
                              _toggleEntry(ev['id'], hasEntryOpen ? 0 : 1),
                        ),
                      ],
                      IconButton(
                        tooltip: 'কারণ লিখে পরীক্ষা delete করুন',
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.redAccent,
                        ),
                        onPressed: () => _deleteEvent(ev),
                      ),
                      IconButton(
                        icon: Icon(
                          isExpanded ? Icons.expand_less : Icons.expand_more,
                        ),
                        onPressed: () => setState(
                          () => _expandedEvent = isExpanded ? null : ev['id'],
                        ),
                      ),
                    ],
                  ),
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
    if (classes.isEmpty) {
      return Column(
        children: [
          const Text(
            'এখনও বিষয়ভিত্তিক পরীক্ষা তৈরি হয়নি।',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('বিষয়ভিত্তিক পরীক্ষা তৈরি করুন'),
            onPressed: () => _autoCreateSubjects(ev),
          ),
        ],
      );
    }

    return Column(
      children: [
        // Progress summary
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statChip('Classes', '${classes.length}'),
                  _statChip(
                    'Subjects',
                    '${classes.fold<int>(0, (sum, c) => sum + ((c['subject_count'] as num?)?.toInt() ?? 0))}',
                  ),
                  _statChip('Students', '${ev['total_students'] ?? 0}'),
                  _statChip(
                    'Entry %',
                    '${((ev['entry_open_count'] as num? ?? 0) / (ev['exam_count'] as num? ?? 1) * 100).round()}%',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (ev['entry_deadline'] != null)
                Text(
                  'Entry Deadline: ${_fmtD(ev['entry_deadline'])}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Classes list
        for (final c in classes) _buildClassCard(c),
        const SizedBox(height: 8),
        // Actions
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.analytics),
              label: const Text('Coverage'),
              onPressed: () => _showCoverage(ev),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Auto-Create Missing'),
              onPressed: () => _autoCreateSubjects(ev),
            ),
            if (ev['is_published'] != 1)
              FilledButton.icon(
                icon: const Icon(Icons.publish),
                label: const Text('Publish'),
                onPressed: () => _showPublishDialog(ev),
              ),
          ],
        ),
      ],
    );
  }

  Widget _statChip(String label, String value) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
    ],
  );

  Widget _buildClassCard(Map c) {
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
          backgroundColor: ready
              ? Colors.green
              : (subjPct > 0 ? Colors.orange : Colors.grey),
          child: Text(
            '$subjectCount',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
        title: Text(
          '${c['class_name']} ${c['group_name'] ?? c['section'] ?? ''}',
        ),
        subtitle: Text(
          'Students: $studentCount | Subjects: $subjectCount | Subj: $subjectsWithMarks/$subjectCount | Stu: $studentsWithMarks/$studentCount',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ready)
              const Icon(Icons.check_circle, color: Colors.green, size: 20),
            Chip(
              label: Text('$subjPct% | $stuPct%'),
              backgroundColor: ready
                  ? Colors.green.shade100
                  : Colors.orange.shade100,
              labelStyle: const TextStyle(fontSize: 11),
            ),
          ],
        ),
        children: [
          // Subject progress bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                LinearProgressIndicator(
                  value: subjPct / 100,
                  backgroundColor: Colors.grey.shade200,
                  color: Colors.blue,
                  minHeight: 6,
                ),
                const SizedBox(height: 4),
                Text(
                  'Subject Progress: $subjectsWithMarks / $subjectCount ($subjPct%)',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          // Subjects list
          for (final s in subjects) _buildSubjectRow(s),
          // Actions
        ],
      ),
    );
  }

  Widget _buildSubjectRow(Map s) {
    final entered = s['entered_count'] as num? ?? 0;
    final total = s['student_count'] as num? ?? 0;
    final published = s['exam_published'] == true;
    final entryOpen = s['entry_open'] == 1;
    final isMine = s['subject_mine'] == 1;
    final deadline = s['exam_entry_deadline']?.toString();
    final closed =
        published ||
        !entryOpen ||
        (deadline != null && deadline.isNotEmpty && _pastDeadline(deadline));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: entryOpen && !published
                ? Colors.green.shade100
                : Colors.red.shade100,
            child: Icon(
              entryOpen && !published ? Icons.lock_open : Icons.lock,
              size: 24,
              color: entryOpen && !published ? Colors.green : Colors.red,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        s['subject_name'],
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (isMine)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Text(
                          '(Mine)',
                          style: TextStyle(fontSize: 11, color: Colors.blue),
                        ),
                      ),
                  ],
                ),
                Text(
                  published
                      ? 'Published'
                      : (!entryOpen
                            ? 'Entry Closed'
                            : (deadline != null && _pastDeadline(deadline)
                                  ? 'Deadline Passed'
                                  : 'Entry Open')),
                  style: TextStyle(
                    fontSize: 11,
                    color: closed ? Colors.red : Colors.green,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (entered > 0)
                  ? Colors.green.shade100
                  : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$entered/$total',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: entered > 0
                    ? Colors.green.shade800
                    : Colors.grey.shade700,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Switch(
            value: entryOpen && !published,
            onChanged: published
                ? null
                : (val) => _toggleSubjectEntry(s['exam_id'] as int, val),
            activeThumbColor: Colors.green,
            inactiveThumbColor: Colors.red,
          ),
        ],
      ),
    );
  }

  void _showCreateSession() {
    final yearCtrl = TextEditingController(
      text: _currentAcademicYear?.toString() ?? '',
    );
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('নতুন একাডেমিক সেশন'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: yearCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'শিক্ষাবর্ষ',
                hintText: 'যেমন ২০২৭',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'সেশন তৈরি হলে Class 6–9-এর Half-Yearly ও Annual, Class 10-এর Pre-Test ও Test, এবং SSC Batch-এর Special Model Test স্বয়ংক্রিয়ভাবে তৈরি হবে।',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            onPressed: () async {
              final year = int.tryParse(yearCtrl.text.trim());
              if (year == null || year < 2000 || year > 2200) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('সঠিক শিক্ষাবর্ষ লিখুন।')),
                );
                return;
              }
              try {
                final result = await Api.post('/admin/sessions', {
                  'name': '$year',
                });
                if (!mounted) return;
                Navigator.pop(dialogContext);
                await _load();
                final isCurrent =
                    result['is_active'] == true || result['is_active'] == 1;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      isCurrent
                          ? '$year শিক্ষাবর্ষ তৈরি হয়েছে এবং বর্তমান চলতি সেশন হিসেবে স্বয়ংক্রিয়ভাবে চালু হয়েছে।'
                          : '$year শিক্ষাবর্ষ তৈরি হয়েছে। চলতি বছরের সেশন স্বয়ংক্রিয়ভাবে চালু থাকবে।',
                    ),
                  ),
                );
              } catch (e) {
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: Colors.red,
                      content: Text(
                        e.toString().replaceFirst('Exception: ', ''),
                      ),
                    ),
                  );
              }
            },
            child: const Text('সেশন তৈরি করুন'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPublishDialog(Map ev) async {
    final kind = ev['exam_kind']?.toString();
    Map options = const {};
    if (kind == 'annual' || kind == 'test') {
      try {
        final response = await Api.get(
          '/results/events/${ev['id']}/promotion-grace-options',
        );
        if (response is Map) options = response;
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text(e.toString().replaceFirst('Exception: ', '')),
          ),
        );
        return;
      }
    }
    bool notify = true;
    final classRows = options['classes'] is List
        ? (options['classes'] as List).whereType<Map>().toList()
        : <Map>[];
    final selected = <int, Set<int>>{};
    for (final row in classRows) {
      final classId = (row['class_id'] as num?)?.toInt();
      if (classId == null) continue;
      selected[classId] =
          (row['selected_subject_ids'] is List
                  ? row['selected_subject_ids'] as List
                  : const [])
              .whereType<num>()
              .map((value) => value.toInt())
              .toSet();
    }
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Publish "${ev['name']}"?'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (kind == 'annual' || kind == 'test') ...[
                    const Text(
                      'কোন কোন mandatory subject-এ grace দেবেন বেছে নিন। Optional subject এখানে নেই। নির্বাচিত subject-এ fail করে অন্য mandatory subject-এ pass করা শিক্ষার্থীরা publish-এর পর promote হবে; অন্য mandatory fail-রা শ্রেণি উত্তরণ তালিকায় যাবে।',
                    ),
                    const SizedBox(height: 10),
                    for (final row in classRows) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '${row['class_name'] ?? ''}${(row['group_name'] ?? row['section'] ?? '').toString().isEmpty ? '' : ' (${row['group_name'] ?? row['section']})'}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      for (final subject
                          in (row['subjects'] is List
                              ? row['subjects'] as List
                              : const <dynamic>[]))
                        if (subject is Map)
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text('${subject['subject_name'] ?? ''}'),
                            value:
                                (subject['subject_ids'] is List
                                        ? subject['subject_ids'] as List
                                        : const [])
                                    .whereType<num>()
                                    .any(
                                      (id) =>
                                          selected[(row['class_id'] as num)
                                                  .toInt()]!
                                              .contains(id.toInt()),
                                    ),
                            onChanged: (checked) {
                              final classId = (row['class_id'] as num).toInt();
                              final subjectIds =
                                  (subject['subject_ids'] is List
                                          ? subject['subject_ids'] as List
                                          : const [])
                                      .whereType<num>()
                                      .map((id) => id.toInt())
                                      .toList();
                              setDialogState(() {
                                if (checked == true) {
                                  selected[classId]!.addAll(subjectIds);
                                } else {
                                  selected[classId]!.removeAll(subjectIds);
                                }
                              });
                            },
                          ),
                      if ((row['subjects'] as List? ?? const []).isEmpty)
                        const Text('কোনো mandatory subject পাওয়া যায়নি।'),
                    ],
                    const Divider(),
                  ],
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Notify guardians'),
                    value: notify,
                    onChanged: (v) => setDialogState(() => notify = v ?? false),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, {
                'notify': notify,
                'grace_subjects': [
                  for (final entry in selected.entries)
                    {
                      'class_id': entry.key,
                      'subject_ids': entry.value.toList()..sort(),
                    },
                ],
              }),
              child: const Text('Publish'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await _publishEvent(
      ev,
      result['notify'] == true,
      (result['grace_subjects'] as List?)
              ?.whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList() ??
          const [],
    );
  }

  Future<void> _autoCreateSubjects(Map ev) async {
    try {
      final r = await Api.post('/admin/auto-create-subject-exams', {
        'event_id': ev['id'],
      });
      if (!mounted) return;
      _load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green,
          content: Text('Created ${r['created']} subject exams'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text(e.toString())),
      );
    }
  }

  bool _pastDeadline(String raw) {
    try {
      return DateTime.now().isAfter(DateTime.parse(raw.replaceAll(' ', 'T')));
    } catch (_) {
      return false;
    }
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Coverage: ${data['event_ready'] == true ? 'Ready to Publish' : 'Not Ready'}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          for (final c in classes)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${c['class_name']} ${c['section']}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Subjects: ${c['subjects_with_marks']}/${c['subject_count']} | Students: ${c['students_with_marks']}/${c['student_count']}',
                    ),
                    Text(
                      c['ready'] == true
                          ? 'Ready'
                          : 'Missing: ${c["gaps"] ?? []}',
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  Map _data = {};
  int? _sessionId;
  int? _eventId;
  bool _busy = true;
  String? _error;

  Future<void> _load({int? sessionId, int? eventId}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final query = <String, String>{};
      if (sessionId != null) query['session_id'] = '$sessionId';
      if (eventId != null) query['event_id'] = '$eventId';
      final result = await Api.get('/admin/analytics', queryParams: query);
      if (!mounted) return;
      setState(() {
        _data = result is Map ? result : {};
        _sessionId = (_data['selected_session_id'] as num?)?.toInt();
        _eventId = eventId;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _sharePdf() async {
    try {
      final font = await AppPdf.banglaFont();
      final doc = pw.Document();
      final rows = (_data['students'] as List? ?? []).cast<Map>();
      final sessions = _data['sessions'] as List? ?? [];
      final selected = sessions
          .where((s) => (s['id'] as num?)?.toInt() == _sessionId)
          .toList();
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          build: (_) => [
            pw.Text(
              'Session Results Analytics · ${selected.isEmpty ? '' : selected.first['name']}',
              style: AppPdf.bn(font, size: 18, weight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: const [
                'Exam',
                'Year',
                'Class',
                'Student',
                'Roll',
                'Marks',
                'Full',
                'GPA',
                'Result',
                'Position',
              ],
              data: rows
                  .map(
                    (r) => [
                      '${r['exam_name'] ?? ''}',
                      '${r['year'] ?? ''}',
                      '${r['class_name'] ?? ''} ${r['section'] ?? ''}',
                      '${r['student_name'] ?? ''}',
                      '${r['roll'] ?? ''}',
                      '${r['marks_obtained'] ?? 0}',
                      '${r['marks_full'] ?? 0}',
                      '${r['final_gpa'] ?? '—'}',
                      '${r['result_status'] ?? '—'}',
                      '${r['combined_position'] ?? r['section_position'] ?? '—'}',
                    ],
                  )
                  .toList(),
              headerStyle: AppPdf.bn(font, size: 8, weight: pw.FontWeight.bold),
              cellStyle: AppPdf.bn(font, size: 7),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey300,
              ),
              cellAlignment: pw.Alignment.centerLeft,
            ),
          ],
        ),
      );
      await AppPdf.share(
        await doc.save(),
        'session-${_sessionId ?? 'analytics'}-results.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('PDF তৈরি হয়নি: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _data['sessions'] as List? ?? [];
    final exams = _data['exams'] as List? ?? [];
    final rows = _data['students'] as List? ?? [];
    final selectedEvents = exams
        .where(
          (e) =>
              _sessionId == null ||
              e['session_id'] == _sessionId ||
              e['event_id'] == _eventId,
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Analytics'),
        actions: [
          IconButton(
            onPressed: rows.isEmpty ? null : _sharePdf,
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'PDF শেয়ার/ডাউনলোড',
          ),
          IconButton(
            onPressed: () => _load(sessionId: _sessionId, eventId: _eventId),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
          : RefreshIndicator(
              onRefresh: () => _load(sessionId: _sessionId, eventId: _eventId),
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  DropdownButtonFormField<int>(
                    value:
                        sessions.any(
                          (s) => (s['id'] as num?)?.toInt() == _sessionId,
                        )
                        ? _sessionId
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Academic Session',
                      border: OutlineInputBorder(),
                    ),
                    items: sessions
                        .map<DropdownMenuItem<int>>(
                          (s) => DropdownMenuItem(
                            value: (s['id'] as num).toInt(),
                            child: Text('${s['name']}'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => _load(sessionId: v),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int?>(
                    value: _eventId,
                    decoration: const InputDecoration(
                      labelText: 'Exam (সব পরীক্ষা)',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('সব পরীক্ষা'),
                      ),
                      ...selectedEvents.map<DropdownMenuItem<int?>>(
                        (e) => DropdownMenuItem(
                          value: (e['event_id'] as num).toInt(),
                          child: Text('${e['exam_name']}'),
                        ),
                      ),
                    ],
                    onChanged: (v) => _load(sessionId: _sessionId, eventId: v),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'পরীক্ষা: ${exams.length}  ·  Student result row: ${rows.length}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  if (rows.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('এই session-এ প্রকাশিত result data নেই।'),
                      ),
                    ),
                  for (final exam in exams.where(
                    (e) =>
                        _eventId == null ||
                        (e['event_id'] as num?)?.toInt() == _eventId,
                  ))
                    Card(
                      child: ExpansionTile(
                        title: Text(
                          '${exam['exam_name']} · ${exam['year'] ?? ''}',
                        ),
                        subtitle: Text(
                          '${rows.where((r) => (r['event_id'] as num?)?.toInt() == (exam['event_id'] as num?)?.toInt()).length} student result',
                        ),
                        children: [
                          for (final r in rows.where(
                            (r) =>
                                (r['event_id'] as num?)?.toInt() ==
                                (exam['event_id'] as num?)?.toInt(),
                          ))
                            ListTile(
                              dense: true,
                              title: Text(
                                '${r['student_name']} · ${r['class_name']} ${r['section'] ?? ''}',
                              ),
                              subtitle: Text(
                                'Roll ${r['roll']} · Marks ${r['marks_obtained']}/${r['marks_full']} · GPA ${r['final_gpa'] ?? '—'} · ${r['result_status'] ?? '—'}',
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    'Class summary',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (final c in (_data['classStats'] as List? ?? []))
                    ListTile(
                      dense: true,
                      title: Text('${c['name']} ${c['section'] ?? ''}'),
                      subtitle: Text(
                        'Students ${c['students']} · Passed ${c['passed']} · Average GPA ${c['average_gpa'] ?? '—'}',
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
