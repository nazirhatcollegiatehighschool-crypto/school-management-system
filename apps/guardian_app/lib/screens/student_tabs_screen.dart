import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../config.dart';
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
  Map? _attSummary; // v2 monthly summary {percent, present_days, ...}
  List? _attRecords; // v2 records with who-took
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
        Api.get('/attendance/guardian/$id').catchError((_) => null),
      ]);
      await Api.cachePut(cacheKey, {
        'routine': results[0], 'attendance': results[1], 'marks': results[2],
        'homework': results[3], 'notifications': results[4],
        'complaints': results[5] is Map ? (results[5] as Map)['complaints'] : null,
        'remarks': results[5] is Map ? (results[5] as Map)['remarks'] : null,
        'att_v2': results[6] is Map ? results[6] : null,
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
        if (results[6] is Map) {
          final m = results[6] as Map;
          _attSummary = m['summary'] is Map ? m['summary'] as Map : null;
          _attRecords = m['records'] is List ? m['records'] as List : null;
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
    final isPass = (num.tryParse(pct) ?? 0) >= 40;
    final isGood = (num.tryParse(pct) ?? 0) >= 60;
    final scoreColor = isGood ? const Color(0xFF16A34A) : isPass ? const Color(0xFFD97706) : const Color(0xFFDC2626);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: m['exam_id'] != null ? () => _openResultDetail(m['exam_id'].toString()) : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${m['subject_name']}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF0F172A)),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${m['exam_name']} • ${m['exam_type'].toString().replaceAll('_', ' ')}',
                            style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: scoreColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: scoreColor.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${m['marks']} / ${m['total']}',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: scoreColor),
                          ),
                          Text(
                            '$pct%',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: scoreColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if ((m['comment'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.chat_bubble_outline_rounded, size: 14, color: Colors.grey),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            m['comment'].toString(),
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontStyle: FontStyle.italic),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _statusColor(String s) =>
      s == 'present' ? const Color(0xFF16A34A) : s == 'absent' ? const Color(0xFFDC2626) : const Color(0xFFD97706);

  Widget _attSummaryCard(Map s) {
    final pct = (s['percent'] is num) ? (s['percent'] as num).toDouble() : 0.0;
    final present = s['present_days'] ?? 0;
    final late = s['late_days'] ?? 0;
    final leave = s['leave_days'] ?? 0;
    final absent = s['absent_days'] ?? 0;
    final school = s['school_days'] ?? 0;
    final col = pct >= 75 ? const Color(0xFF16A34A) : pct >= 50 ? const Color(0xFFF59E0B) : const Color(0xFFDC2626);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [col, col.withValues(alpha: .8)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: [
        Text('এই মাসের হাজিরা', style: TextStyle(color: Colors.white.withValues(alpha: .9), fontSize: 13)),
        const SizedBox(height: 4),
        Text('${pct.toStringAsFixed(1)}%', style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _sumItem('উপস্থিত', present + late, Colors.white),
          _sumItem('অনুপস্থিত', absent, Colors.white),
          _sumItem('ছুটি', leave, Colors.white),
          _sumItem('মোট দিন', school, Colors.white),
        ]),
      ]),
    );
  }

  Widget _sumItem(String label, int n, Color c) {
    return Column(children: [
      Text('$n', style: TextStyle(color: c, fontSize: 18, fontWeight: FontWeight.w800)),
      Text(label, style: TextStyle(color: c.withValues(alpha: .85), fontSize: 11)),
    ]);
  }

  Widget _attRow(Map a) {
    final st = (a['status'] ?? a['final_state'] ?? '').toString().toLowerCase();
    final sess = (a['session'] ?? 'morning').toString();
    final sessBn = sess == 'p5' ? '৫ম পিরিয়ড' : 'সকাল';
    final by = a['recorded_by'] as String?;
    final at = a['recorded_at'] as String?;
    final label = switch (st) {
      'present' => 'উপস্থিত', 'absent' => 'অনুপস্থিত',
      'late' => 'দেরি', 'leave' => 'ছুটি', _ => st,
    };
    final color = _statusColor(st);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
      ),
      child: ListTile(
        dense: true,
        leading: Container(
          width: 12, height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        title: Text('${a['date'].toString().substring(0, 10)} · $sessBn',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: (by != null && by.isNotEmpty)
            ? Text('নেওয়াছেন: $by${at != null ? ' · ${at.substring(0, 16)}' : ''}',
                style: const TextStyle(fontSize: 12, color: Colors.black54))
            : (a['remark'] != null ? Text(a['remark'], style: TextStyle(fontSize: 12, color: Colors.grey.shade600)) : null),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indigo = theme.colorScheme.primary;

    final tabItems = const [
      (0, 'রুটিন', Icons.calendar_month_rounded),
      (1, 'হাজিরা', Icons.fact_check_rounded),
      (2, 'ফলাফল', Icons.emoji_events_rounded),
      (3, 'হোমওয়ার্ক', Icons.edit_note_rounded),
      (4, 'নোটিশ', Icons.campaign_rounded),
      (5, 'অভিযোগ', Icons.report_problem_rounded),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5FB),
      appBar: AppBar(
        title: Text(widget.studentName.isNotEmpty ? widget.studentName : 'শিক্ষার্থীর তথ্য'),
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              color: const Color(0xFFFFFBEB),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(_error!, style: const TextStyle(fontSize: 12, color: Color(0xFF92400E))),
            ),

          // Horizontal Category Chips Bar
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.15))),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: tabItems.map((item) {
                  final isSelected = _tab == item.$1;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () => setState(() => _tab = item.$1),
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? indigo : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? indigo : Colors.grey.withValues(alpha: 0.20),
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: indigo.withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              item.$3,
                              size: 16,
                              color: isSelected ? Colors.white : Colors.grey.shade600,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              item.$2,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? Colors.white : const Color(0xFF334155),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          Expanded(child: _buildTab()),
        ],
      ),
    );
  }

  Widget _buildTab() {
    if (_tab == 0) {
      if (_routine == null) return const Center(child: CircularProgressIndicator());
      final data = _routine!;
      return RoutineView(routines: data);
    }
    if (_tab == 1) {
      // v2 data preferred (summary + who-took + leave), fallback to legacy list
      final recs = (_attRecords != null && _attRecords!.isNotEmpty) ? _attRecords! : _attendance;
      if (recs == null) return const Center(child: CircularProgressIndicator());
      if (recs.isEmpty) return const Center(child: Text('কোনো হাজিরা রেকর্ড পাওয়া যায়নি'));
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_attSummary != null) _attSummaryCard(_attSummary!),
          ...recs.map((a) => _attRow(a)),
        ],
      );
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
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('সংযুক্ত ফাইল', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          Builder(builder: (_) {
            final files = (h['attachments'] as List?) ?? const [];
            if (files.isEmpty) {
              return const Text('কোনো ফাইল নেই', style: TextStyle(color: Colors.grey, fontSize: 13));
            }
            return Column(children: [
              for (final a in files)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                      '${a['mime_type'] ?? ''}'.startsWith('image/')
                          ? Icons.image_outlined
                          : Icons.picture_as_pdf_outlined,
                      color: '${a['mime_type'] ?? ''}'.startsWith('image/')
                          ? Colors.teal
                          : Colors.red),
                  title: Text('${a['file_name']}', style: const TextStyle(fontSize: 13)),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () async {
                    final uri = Uri.parse('${Config.api}${a['url'] ?? ''}');
                    try {
                      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
                      if (!ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('ফাইল খোলা যায়নি')));
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(e.toString().replaceFirst('Exception: ', ''))));
                      }
                    }
                  },
                ),
            ]);
          }),
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