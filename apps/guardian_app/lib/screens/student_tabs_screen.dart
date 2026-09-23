import 'package:flutter/material.dart';
import '../api.dart';
import 'marksheet_screen.dart';
import '../widgets/routine_view.dart';

class StudentTabsScreen extends StatefulWidget {
  final int studentId;
  final String studentName;
  final int initialTab;
  final String? initialExamId;
  const StudentTabsScreen({super.key, required this.studentId, required this.studentName, this.initialTab = 0, this.initialExamId});
  @override
  State<StudentTabsScreen> createState() => _StudentTabsScreenState();
}

class _StudentTabsScreenState extends State<StudentTabsScreen> {
  int _tab = 0;
  List? _routine;
  List? _attendance;
  List? _marks;
  List? _homework;
  List? _notifications;
  List? _complaints;
  List? _remarks;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    if (widget.initialExamId != null && widget.initialExamId!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openResultDetail(widget.initialExamId!));
    }
    _loadAll();
  }

  void _openResultDetail(String examId) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ResultDetailScreen(studentId: widget.studentId, examId: examId)));
  }

  Future<void> _loadAll() async {
    try {
      final id = widget.studentId;
      final cacheKey = 'student_$id';
      final cached = await Api.cacheGet(cacheKey);
      if (cached != null && mounted) {
        setState(() {
          _routine = cached['routine'];
          _attendance = cached['attendance'];
          _marks = cached['marks'];
          _homework = cached['homework'];
          _notifications = cached['notifications'];
          _complaints = cached.containsKey('complaints') ? cached['complaints'] : null;
          _remarks = cached.containsKey('remarks') ? cached['remarks'] : null;
        });
      }
      final results = await Future.wait([
        Api.get('/routine/student'),
        Api.get('/guardian/student/$id/attendance'),
        Api.get('/guardian/student/$id/marks'),
        Api.get('/guardian/student/$id/homework'),
        Api.get('/guardian/student/$id/notifications'),
        Api.get('/guardian/student/$id/complaints'),
      ]);
      await Api.cachePut(cacheKey, {
        'routine': results[0], 'attendance': results[1], 'marks': results[2],
        'homework': results[3], 'notifications': results[4],
        'complaints': results[5] is Map ? (results[5] as Map)['complaints'] : null,
        'remarks': results[5] is Map ? (results[5] as Map)['remarks'] : null,
      });
      if (!mounted) return;
      setState(() {
        _routine = results[0];
        _attendance = results[1];
        _marks = results[2];
        _homework = results[3];
        _notifications = results[4];
        if (results[5] is Map) {
          _complaints = (results[5] as Map)['complaints'];
          _remarks = (results[5] as Map)['remarks'];
        }
      });
    } catch (e) {
      setState(() => _error = 'অফলাইন ডেটা দেখানো হচ্ছে: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  Future<void> _markRead(Map n) async {
    try {
      await Api.post('/guardian/notifications/read', {'ids': [n['id']]});
    } catch (_) {}
  }

  Widget _buildMarksCard(dynamic m) {
    final marksVal = num.tryParse('${m['marks']}')?.toDouble() ?? 0;
    final totalVal = num.tryParse('${m['total']}')?.toDouble() ?? 0;
    final pct = (totalVal > 0 ? marksVal / totalVal * 100 : 0).toStringAsFixed(0);
    return Card(child: ListTile(
      title: Text('${m['subject_name']} — ${m['exam_name']}'),
      subtitle: Text('${m['exam_type'].toString().replaceAll('_', ' ')}${(m['comment'] ?? '').toString().isNotEmpty ? '\n💬 ${m['comment']}' : ''}'),
      isThreeLine: (m['comment'] ?? '').toString().isNotEmpty,
      trailing: Text('${m['marks']}/${m['total']}\n$pct%',
          textAlign: TextAlign.end,
          style: TextStyle(fontWeight: FontWeight.bold,
              color: num.parse(pct) >= 60 ? Colors.green : Colors.red)),
      onTap: m['exam_id'] != null
          ? () => _openResultDetail(m['exam_id'].toString())
          : null,
    ));
  }

  Color _statusColor(String s) =>
      s == 'present' ? Colors.green : s == 'absent' ? Colors.red : Colors.orange;

  @override
  Widget build(BuildContext context) {
    final tabs = const ['Routine', 'Attendance', 'Results', 'Homework', 'Notices', 'Complaints'];
    return Scaffold(
      appBar: AppBar(title: Text(widget.studentName)),
      body: Column(children: [
        if (_error != null)
          Container(width: double.infinity, color: Colors.amber.shade100,
            padding: const EdgeInsets.all(8),
            child: Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.brown))),
        Padding(padding: const EdgeInsets.all(10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<int>(
              segments: tabs.map((t) => ButtonSegment(value: tabs.indexOf(t), label: Text(t, style: const TextStyle(fontSize: 12)))).toList(),
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
          )),
        Expanded(child: _buildTab()),
      ]),
    );
  }

  Widget _buildTab() {
    if (_tab == 0) {
      if (_routine == null) return const Center(child: CircularProgressIndicator());
      final data = _routine!;
      return RoutineView(routines: data);
    }
    if (_tab == 1) {
      if (_attendance == null) return const Center(child: CircularProgressIndicator());
      return ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _attendance!.length,
        itemBuilder: (_, i) {
          final a = _attendance![i];
          return ListTile(
            leading: Icon(Icons.circle, color: _statusColor(a['status']), size: 14),
            title: Text(a['date'].toString().substring(0, 10)),
            trailing: Text(a['status'].toUpperCase(),
                style: TextStyle(color: _statusColor(a['status']), fontWeight: FontWeight.bold)),
            subtitle: a['remark'] != null ? Text(a['remark']) : null,
          );
        });
    }
if (_tab == 2) {
      if (_marks == null) return const Center(child: CircularProgressIndicator());
      if (_marks!.isEmpty) {
        return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('এখনো কোনো result নেই'),
          const SizedBox(height: 10),
          TextButton.icon(
            icon: const Icon(Icons.article_outlined),
            label: const Text('Full Marksheet'),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(
                  builder: (_) => MarksheetScreen(studentId: widget.studentId, studentName: widget.studentName)));
            },
          ),
        ]));
      }
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Align(alignment: Alignment.centerRight, child: TextButton.icon(
            icon: const Icon(Icons.article_outlined, size: 18),
            label: const Text('Full Marksheet'),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) =>
                  MarksheetScreen(studentId: widget.studentId, studentName: widget.studentName)));
            },
          )),
          for (final m in _marks!) _buildMarksCard(m),
          const SizedBox(height: 8),
        ],
      );
    }
    if (_tab == 3) {
      if (_homework == null) return const Center(child: CircularProgressIndicator());
      if (_homework!.isEmpty) return const Center(child: Text('কোনো homework নেই'));
      return ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _homework!.length,
        itemBuilder: (_, i) {
          final h = _homework![i];
          return Card(child: ListTile(
            leading: const Icon(Icons.edit_note, color: Colors.deepPurple),
            title: Text(h['title']),
            subtitle: Text([
              if (h['subject_name'] != null) '${h['subject_name']}',
              if (h['teacher_name'] != null) 'শিক্ষক: ${h['teacher_name']}',
              if ((h['description'] ?? '').toString().isNotEmpty && (h['description'] ?? '').toString().length <= 60)
                h['description'].toString(),
            ].join('\n')),
            isThreeLine: true,
            trailing: Text(h['due_date'] != null
                ? 'Due ${h['due_date'].toString().substring(0, 10)}'
                : 'No due date',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            onTap: h['id'] != null
                ? () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => HomeworkDetailScreen(
                      studentId: widget.studentId,
                      homework: Map.from(h),
                    )))
                : null,
          ));
        });
    }
    if (_tab == 5) {
      if (_complaints == null) return const Center(child: CircularProgressIndicator());
      final complaints = _complaints!;
      final remarks = _remarks ?? <dynamic>[];
      if (complaints.isEmpty && remarks.isEmpty) {
        return const Center(child: Text('কোনো অভিযোগ/মন্তব্য নেই'));
      }
      return RefreshIndicator(
        onRefresh: () async { _loadAll(); },
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (complaints.isNotEmpty) ...[
              const Padding(padding: EdgeInsets.only(bottom: 6),
                child: Text('অভিযোগ / বিশেষ সতর্কতা', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
              for (final n in complaints) Card(child: ListTile(
                leading: Icon(Icons.report_problem,
                    color: n['is_read'] == 1 ? Colors.grey : Colors.orange),
                title: Text(n['title'],
                    style: TextStyle(fontWeight: FontWeight.w600,
                        color: n['is_read'] == 1 ? Colors.grey[600] : Colors.black)),
                subtitle: Text([
                  n['body']?.toString() ?? '',
                  if (n['teacher_name'] != null) 'শিক্ষক: ${n['teacher_name']}',
                  n['created_at'] != null ? n['created_at'].toString().substring(0, 16).replaceAll('T', ' ') : '',
                ].where((s) => s.isNotEmpty).join('\n')),
                isThreeLine: true,
                onTap: () {
                  if (n['is_read'] != 1) {
                    setState(() => n['is_read'] = 1);
                    _markRead(n);
                  }
                },
              )),
              const SizedBox(height: 12),
            ],
            if (remarks.isNotEmpty) ...[
              const Padding(padding: EdgeInsets.only(bottom: 6),
                child: Text('পরীক্ষায় শিক্ষকের মন্তব্য', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
              for (final m in remarks) Card(child: ListTile(
                leading: const Icon(Icons.chat_bubble_outline, color: Colors.deepPurple),
                title: Text('${m['subject_name']} — ${m['exam_name']}'),
                subtitle: Text('💬 ${m['comment']}\n${m['recorded_at']?.toString().substring(0, 16).replaceAll('T', ' ') ?? ''}'),
                isThreeLine: true,
              )),
            ],
          ],
        ),
      );
    }
    if (_notifications == null) return const Center(child: CircularProgressIndicator());
    if (_notifications!.isEmpty) return const Center(child: Text('কোনো notification নেই'));
    return RefreshIndicator(
      onRefresh: () async { _loadAll(); },
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _notifications!.length,
        itemBuilder: (_, i) {
          final n = _notifications![i];
          IconData icon = Icons.notifications;
          Color color = Colors.indigo;
          if (n['type'] == 'attendance') { icon = Icons.event_busy; color = Colors.red; }
          if (n['type'] == 'result') { icon = Icons.emoji_events; color = Colors.amber.shade800; }
          if (n['type'] == 'notice' || n['type'] == 'special') { icon = Icons.campaign; color = Colors.blue; }
          if (n['type'] == 'homework') { icon = Icons.edit_note; color = Colors.deepPurple; }
          if (n['type'] == 'complaint') { icon = Icons.report_problem; color = Colors.orange; }
          return Card(child: ListTile(
            leading: Icon(icon, color: color),
            title: Text(n['title'],
                style: TextStyle(fontWeight: FontWeight.w600,
                    color: n['is_read'] == 1 ? Colors.grey[600] : Colors.black)),
            subtitle: Text(n['body']),
            isThreeLine: n['body'].toString().length > 40,
            trailing: Text(n['created_at'].toString().substring(0, 16).replaceAll('T', '\n'),
                style: const TextStyle(fontSize: 10, color: Colors.grey), textAlign: TextAlign.end),
            onTap: () {
              if (n['is_read'] != 1) {
                setState(() => n['is_read'] = 1);
                _markRead(n);
              }
              if (n['type'] == 'result' && n['exam_id'] != null) _openResultDetail(n['exam_id'].toString());
            },
          ));
        }),
    );
  }
}

class ResultDetailScreen extends StatefulWidget {
  final int studentId;
  final String examId;
  const ResultDetailScreen({super.key, required this.studentId, required this.examId});
  @override
  State<ResultDetailScreen> createState() => _ResultDetailScreenState();
}

class _ResultDetailScreenState extends State<ResultDetailScreen> {
  Map? _result;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final r = await Api.get('/guardian/student/${widget.studentId}/result/${widget.examId}');
      setState(() => _result = r);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Result Detail')),
      body: _error != null
          ? Center(child: Text(_error!))
          : _result == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Card(child: ListTile(
                    leading: const Icon(Icons.emoji_events, color: Colors.amber),
                    title: Text(_result!['exam_name'] ?? 'Exam'),
                    subtitle: Text('${_result!['subject_name'] ?? ''}${_result!['class_name'] != null ? ' • ${_result!['class_name']}' : ''}'),
                  )),
                  const SizedBox(height: 10),
                  Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
                    Row(children: [
                      Text('মার্কস', style: const TextStyle(color: Colors.grey)),
                      const Spacer(),
                      Text('${_result!['marks']} / ${_result!['total']}',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 8),
                    if ((_result!['comment'] ?? '').toString().isNotEmpty)
                      Align(alignment: Alignment.centerLeft, child: Text('💬 ${_result!['comment']}')),
                  ]))),
                  const SizedBox(height: 10),
                  Card(child: ListTile(
                    leading: const Icon(Icons.event_note),
                    title: const Text('শিক্ষকের মন্তব্য / রেকর্ড সময়'),
                    subtitle: Text(_result!['recorded_at']?.toString() ?? '-'),
                  )),
                ]),
    );
  }
}

class HomeworkDetailScreen extends StatefulWidget {
  final int studentId;
  final Map homework;
  const HomeworkDetailScreen({super.key, required this.studentId, required this.homework});
  @override
  State<HomeworkDetailScreen> createState() => _HomeworkDetailScreenState();
}

class _HomeworkDetailScreenState extends State<HomeworkDetailScreen> {
  String _status = 'pending';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Api.get('/guardian/student/${widget.studentId}/homework');
      if (res is List) {
        for (final item in res) {
          if (item is Map && item['id'] == widget.homework['id']) {
            if (mounted) setState(() { _status = 'সর্বশেষ ডেটা দেখানো হচ্ছে'; });
          }
        }
      }
    } catch (_) {}
  }

  String _date(dynamic v) {
    if (v == null) return '-';
    final s = v.toString();
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.homework;
    return Scaffold(
      appBar: AppBar(title: const Text('Homework Detail')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.edit_note, color: Colors.deepPurple, size: 28),
            const SizedBox(width: 10),
            Expanded(child: Text(h['title']?.toString() ?? 'Homework',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          ]),
          const SizedBox(height: 8),
          if (h['subject_name'] != null)
            _row(Icons.menu_book, 'বিষয়', h['subject_name'].toString()),
          if (h['teacher_name'] != null)
            _row(Icons.person, 'শিক্ষক', h['teacher_name'].toString()),
          _row(Icons.event, 'জমা দেওয়ার তারিখ', _date(h['due_date'])),
          _row(Icons.schedule, 'প্রকাশের সময়', _date(h['created_at'])),
        ]))),
        const SizedBox(height: 10),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('বিস্তারিত', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          Text((h['description'] ?? '').toString().isNotEmpty
              ? h['description'].toString()
              : 'কোনো বিস্তারিত নেই'),
        ]))),
        const SizedBox(height: 10),
        Center(child: Text(_status, style: TextStyle(color: Colors.green.shade700, fontSize: 12))),
      ]),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
      Icon(icon, size: 18, color: Colors.grey),
      const SizedBox(width: 8),
      Text('$label: ', style: const TextStyle(color: Colors.grey)),
      Expanded(child: Text(value)),
    ]));
  }
}