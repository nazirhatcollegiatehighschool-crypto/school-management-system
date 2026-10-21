import 'package:flutter/material.dart';
import '../api.dart';
import 'event_detail_screen.dart';
import 'event_list_screen.dart';
import 'exam_detail_screen.dart';
import 'create_exam_screen.dart';

/// Exam tab — Current exam + running exam events + marks entry.
class ExamsScreen extends StatefulWidget {
  final dynamic teacher;
  const ExamsScreen({super.key, required this.teacher});
  @override
  State<ExamsScreen> createState() => ExamsScreenState();
}

class ExamsScreenState extends State<ExamsScreen> {
  Map? _data;
  List _classes = [];
  List _events = [];
  int? _classId;
  String _scope = 'mine';
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> reload() => _load();

  Future<void> _load() async {
    if (_data == null) setState(() { _loading = true; _error = null; });
    try {
      await Future.wait([
        Api.loadCachedFirst('/teacher/current-exam', (r) {
          if (!mounted) return;
          if (r is! Map) { setState(() => _loading = false); return; }
          final cls = (r['classes'] as List?) ?? const [];
          setState(() {
            _data = r;
            _classes = cls;
            final exists = _classes.any((c) => c['class_id'] == _classId);
            _classId = exists ? _classId : (_classes.isNotEmpty ? _classes.first['class_id'] : null);
            _loading = false;
          });
        }),
        Api.loadCachedFirst('/teacher/events', (r) {
          if (!mounted) return;
          setState(() { _events = r is List ? r : []; });
        }),
      ]);
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Map? get _cls {
    for (final c in _classes) {
      if (c['class_id'] == _classId) return c as Map;
    }
    return null;
  }

  bool get _isClassTeacher =>
      (_cls?['is_class_teacher'] == 1) || (_cls?['is_class_teacher'] == true);

  List get _subjects {
    final subs = (_cls?['subjects'] as List?) ?? const [];
    if (_scope == 'mine') {
      return subs.where((s) => s is Map && s['is_mine'] == true).toList();
    }
    return subs;
  }

  String _kindLabel(dynamic k) {
    switch ('$k') {
      case 'half_yearly': return 'Half Yearly';
      case 'annual': return 'Annual';
      case 'pretest': return 'Pre-Test';
      case 'test': return 'Test';
      default: return 'Exam';
    }
  }

  Future<void> _openEntry(Map subj) async {
    final event = _data?['event'];
    if (event == null || _classId == null) return;
    final mine = subj['is_mine'] == true;
    final published = subj['exam_published'] == true;
    final open = (subj['entry_open'] as num?)?.toInt() ?? 1;
    final canEdit = mine && !published && open == 1;
    final examId = await showDialog<int>(
      context: context,
      builder: (_) => MarksEntryDialog(
        eventId: event['id'],
        eventName: '${event['name']}',
        classId: _classId!,
        subject: subj,
        canEdit: canEdit,
      ),
    );
    if (examId != null && examId > 0) {
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(
          builder: (_) => ExamDetailScreen(examId: examId, examName: '${subj['subject_name']}')));
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final event = _data?['event'];
    final session = _data?['session'];
    return Scaffold(
      appBar: AppBar(title: const Text('পরীক্ষা (Exam)'), actions: [
        IconButton(
            icon: const Icon(Icons.event_note_outlined),
            tooltip: 'সব Exam Event',
            onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => EventListScreen(teacher: widget.teacher)))),
        PopupMenuButton<String>(onSelected: (v) async {
          if (v == 'new') {
            await Navigator.push(context, MaterialPageRoute(
                builder: (_) => CreateExamScreen(teacher: widget.teacher)));
            _load();
          }
        }, itemBuilder: (_) => const [
          PopupMenuItem(value: 'new', child: Row(children: [
            Icon(Icons.add), SizedBox(width: 8), Text('নতুন Test তৈরি')
          ])),
        ]),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errState(_error!)
              : event == null
                  ? const Center(child: Padding(padding: EdgeInsets.all(24),
                      child: Text('এই মুহূর্তে কোনো চলমান পরীক্ষা নেই।',
                          textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(padding: const EdgeInsets.all(12), children: [
                        // ===== চলমান পরীক্ষা / Exam Events (banner style) =====
                        if (_events.isNotEmpty) ...[
                          Text('পরীক্ষা', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 6),
                          for (final ev in _events.take(6))
                            Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => EventDetailScreen(
                                    eventId: ev['id'] as int,
                                    eventName: '${ev['name']}',
                                    event: ev,
                                  )),
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    gradient: LinearGradient(
                                      colors: [Colors.indigo.shade50, Colors.blue.shade50],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(color: Colors.indigo.shade100, shape: BoxShape.circle),
                                        child: const Icon(Icons.assignment, color: Colors.indigo),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('${ev['name']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                            const SizedBox(height: 2),
                                            Text('ক্লিক করে ক্লাস ও বিষয় নির্বাচন করুন', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right, color: Colors.indigo),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 14),
                        ],

                        _header(event, session),
                        const SizedBox(height: 10),
                        if (_classes.isEmpty)
                          const Card(child: Padding(padding: EdgeInsets.all(16),
                              child: Text('এই পরীক্ষায় আপনার কোনো class নেই।')))
                        else ...[
                          if (_classes.length > 1) ...[_classPicker(), const SizedBox(height: 8)],
                          _scopeToggle(),
                          const SizedBox(height: 10),
                          _progressCard(),
                          const SizedBox(height: 6),
                          ..._subjectRows(),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.insights_outlined),
                            label: const Text('Result ও Coverage দেখুন'),
                            onPressed: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => EventDetailScreen(
                                    eventId: event['id'],
                                    eventName: '${event['name']}',
                                    event: {
                                      'my_classes': _classes.map((c) => {
                                            'class_id': c['class_id'],
                                            'class_name': c['class_name'],
                                            'section': c['section'],
                                            'group_name': c['group_name'],
                                          }).toList()
                                    }))),
                          ),
                        ],
                      ]),
                    ),
      );
  }

  Widget _errState(String m) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.all(16), child: Text(m, textAlign: TextAlign.center)),
        FilledButton.tonal(onPressed: _load, child: const Text('আবার চেষ্টা করুন')),
      ]));

  Widget _pill(String t, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(20)),
      child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)));

  Widget _header(dynamic event, dynamic session) {
    final published = event['is_published'] == 1;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.indigo.shade700, Colors.indigo.shade400],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.indigo.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.assignment_outlined, color: Colors.white, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text('${event['name']}',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          _pill(_kindLabel(event['exam_kind']), Colors.white24),
          if (event['year'] != null) _pill('${event['year']}', Colors.white24),
          if (session != null && session['name'] != null) _pill('${session['name']} সেশন', Colors.white24),
          _pill(published ? 'Published' : 'চলমান', published ? Colors.green : Colors.orange),
        ]),
      ]),
    );
  }

  Widget _classPicker() => DropdownButtonFormField<int>(
      initialValue: _classId,
      decoration: const InputDecoration(labelText: 'Class', border: OutlineInputBorder(), isDense: true),
      items: _classes.map<DropdownMenuItem<int>>((c) => DropdownMenuItem<int>(
            value: c['class_id'],
            child: Text('${c['class_name']} (${c['group_name'] ?? c['section'] ?? ''})'),
          )).toList(),
      onChanged: (v) => setState(() => _classId = v));

  Widget _scopeToggle() => SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'mine', label: Text('আমার Subject'), icon: Icon(Icons.person_outline, size: 16)),
        ButtonSegment(value: 'all', label: Text('সব Subject'), icon: Icon(Icons.groups_outlined, size: 16)),
      ],
      selected: {_scope},
      onSelectionChanged: (s) => setState(() => _scope = s.first));

  Widget _progressCard() {
    final total = (_cls?['total_subjects'] as num?)?.toInt() ?? 0;
    final done = (_cls?['done_subjects'] as num?)?.toInt() ?? 0;
    final mine = (_cls?['my_subjects'] as num?)?.toInt() ?? 0;
    final pct = total == 0 ? 0.0 : done / total;
    return Card(
      color: Colors.teal.shade50,
      child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.donut_large, size: 18, color: Colors.teal),
          const SizedBox(width: 6),
          Expanded(child: Text(_isClassTeacher ? 'Class Teacher Progress — সব subject' : 'আমার Subject Progress',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
          Text('$done/$total', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: pct, minHeight: 8, backgroundColor: Colors.teal.shade100),
        ),
        const SizedBox(height: 6),
        Text('$doneটি subject-এ number দেওয়া হয়েছে, ${total - done}টি বাকি • আপনার subject $mineটি',
            style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ])),
    );
  }

  List<Widget> _subjectRows() {
    final subs = _subjects;
    if (subs.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: Text(
              _scope == 'mine' ? 'এই পরীক্ষায় আপনার কোনো subject নেই।' : 'কোনো subject নেই।',
              style: const TextStyle(color: Colors.grey))),
        )
      ];
    }
    return subs.map<Widget>((s) {
      final mine = s['is_mine'] == true;
      final submitted = s['submitted'] == true;
      final entered = (s['entered_count'] as num?)?.toInt() ?? 0;
      final stu = (s['student_count'] as num?)?.toInt() ?? 0;
      final published = s['exam_published'] == true;
      final open = (s['entry_open'] as num?)?.toInt() ?? 1;
      final closed = published || open == 0;
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          onTap: () => _openEntry(s as Map),
          leading: CircleAvatar(
            backgroundColor: mine ? Colors.indigo.shade50 : Colors.grey.shade200,
            child: Icon(mine ? Icons.edit_note : Icons.visibility_outlined, size: 18,
                color: mine ? Colors.indigo : Colors.grey.shade700),
          ),
          title: Text('${s['subject_name']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Text(mine ? 'আপনার subject' : 'শিক্ষক: ${s['subject_teacher_name'] ?? '—'}',
              style: TextStyle(fontSize: 11, color: mine ? Colors.indigo : Colors.black54)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: submitted ? Colors.green.shade100 : Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(10)),
              child: Text(submitted ? '$entered/$stu ✓' : 'Pending',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                      color: submitted ? Colors.green.shade800 : Colors.orange.shade900)),
            ),
            const SizedBox(width: 6),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              onPressed: () => _openEntry(s as Map),
              child: Text(mine ? (closed ? 'দেখুন' : 'Entry') : 'দেখুন', style: const TextStyle(fontSize: 12)),
            ),
          ]),
        ),
      );
    }).toList();
  }
}
