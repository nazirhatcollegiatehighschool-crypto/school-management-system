import 'package:flutter/material.dart';
import '../api.dart';
import 'attendance_analytics_screen.dart';

class AttendanceScreen extends StatefulWidget {
  final dynamic teacher;
  final int? initialClassId;
  const AttendanceScreen({super.key, required this.teacher, this.initialClassId});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  List _classes = [];
  int? _selectedClass;
  DateTime _date = DateTime.now();
  List _students = [];
  Map<int, String> _status = {};
  bool _loading = false;
  String? _error;
  // Two-stage checkpoint: 0 = Stage 1 (initial/morning), 1 = Stage 2 (post-leisure P5).
  int _sessionTab = 0;
  // Stage-1 snapshot loaded from server for the verify screen.
  Map<int, Map<String, dynamic>> _stage1 = {};
  // Stage-2 per-student resolution: present_now | early_departure | not_found | verified_left.
  Map<int, String> _stage2 = {};
  Map<int, String> _stage2Note = {};
  bool _stage2Loading = false;

  @override
  void initState() {
    super.initState();
    Api.get('/teacher/profile').then((r) {
      setState(() {
        _classes = r['classes'] ?? [];
        final wanted = widget.initialClassId;
        if (wanted != null && _classes.any((c) => c['id'] == wanted)) {
          _selectedClass = wanted;
          _loadStudents();
        }
      });
    }).catchError((e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    });
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (d != null) {
      setState(() => _date = d);
      if (_selectedClass != null) _loadStudents();
    }
  }

  Future<void> _loadStudents() async {
    if (_students.isEmpty) setState(() { _loading = true; _error = null; });
    try {
      await Api.loadCachedFirst('/teacher/classes/$_selectedClass/students', (r) {
        if (!mounted) return;
        final list = r is List ? r : [];
        setState(() {
          _students = list;
          _status = {for (final s in list) s['id'] as int: 'present'};
          _loading = false;
        });
      });
      // Also fetch today's saved session rows so Stage-2 can verify against Stage-1.
      _loadStage1();
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  /// Load today's saved attendance rows (both sessions) for the selected class.
  /// Never throws — Stage-2 degrades to "no initial record" state on failure.
  Future<void> _loadStage1() async {
    if (_selectedClass == null) return;
    setState(() => _stage2Loading = true);
    try {
      final d = _date.toIso8601String().substring(0, 10);
      final r = await Api.get('/teacher/attendance/class-day?class_id=$_selectedClass&date=$d');
      if (!mounted) return;
      final map = <int, Map<String, dynamic>>{};
      if (r is Map && r['rows'] is List) {
        for (final row in (r['rows'] as List)) {
          if (row is! Map) continue;
          final sid = row['student_id'] as int?;
          if (sid == null) continue;
          final sess = '${row['session'] ?? 'morning'}';
          map.putIfAbsent(sid, () => {})[sess] = row;
        }
      }
      setState(() {
        _stage1 = map;
        // Pre-fill Stage-2: everyone initially present starts as present_now.
        for (final s in _students) {
          final sid = s['id'] as int;
          final m = map[sid]?['morning'];
          final mStatus = m != null ? '${m['status'] ?? ''}' : '';
          if (mStatus == 'present' || mStatus == 'late') {
            _stage2.putIfAbsent(sid, () => 'present_now');
          } else if (!_stage2.containsKey(sid)) {
            _stage2[sid] = mStatus == 'leave' ? 'early_departure' : 'present_now';
          }
        }
        _stage2Loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _stage2Loading = false);
    }
  }

  Future<void> _save() async {
    try {
      // Stage-1 saves to the morning session; Stage-2 posts to the p5 session
      // with initial-status context so the server can verify discrepancies.
      final session = _sessionTab == 1 ? 'p5' : 'morning';
      final records = _sessionTab == 1
          ? _stage2.entries.map((e) {
              final sid = e.key;
              final v = e.value;
              String status;
              String? note = _stage2Note[sid];
              switch (v) {
                case 'present_now':
                  status = 'present';
                  break;
                case 'early_departure':
                  status = 'leave';
                  break;
                case 'verified_left':
                  status = 'absent';
                  break;
                case 'not_found':
                default:
                  status = 'absent';
                  break;
              }
              return {'student_id': sid, 'status': status, 'stage2': v, 'remark': note};
            }).toList()
          : _status.entries.map((e) => {'student_id': e.key, 'status': e.value}).toList();
      final r = await Api.post('/teacher/attendance', {
        'date': _date.toIso8601String().substring(0, 10),
        'session': session,
        'records': records,
      });
      if (!mounted) return;
      if (Api.isQueued(r)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text('ইন্টারনেট নেই — হাজিরা ফোনে সেভ আছে, online হলেই server-এ যাবে'),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attendance saved successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _notifyAbsent() async {
    final absentIds = _status.entries.where((e) => e.value != 'present').map((e) => e.key).toList();
    if (absentIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('সবাই present — notification পাঠানোর দরকার নেই')),
      );
      return;
    }
    try {
      final r = await Api.post('/teacher/notify', {
        'student_ids': absentIds,
        'title': 'Attendance alert',
        'body': 'আপনার সন্তান আজ (${_date.toString().substring(0, 10)}) school-এ absent/late ছিল।',
        'type': 'attendance',
      });
      if (!mounted) return;
      if (Api.isQueued(r)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text('ইন্টারনেট নেই — alert queue-তে আছে, online হলে যাবে'),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${absentIds.length} জনের guardian-কে alert পাঠানো হয়েছে')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  void _markAll(String status) {
    setState(() {
      for (final s in _students) {
        _status[s['id'] as int] = status;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emerald = theme.colorScheme.primary;

    final presentCount = _status.values.where((v) => v == 'present').length;
    final absentCount = _status.values.where((v) => v == 'absent').length;
    final lateCount = _status.values.where((v) => v == 'late').length;
    final hasAbsentees = absentCount > 0 || lateCount > 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F5),
      appBar: AppBar(
        title: const Text('হাজিরা (Attendance)'),
        actions: [
          if (_students.isNotEmpty)
            IconButton(
              icon: Icon(
                Icons.campaign_rounded,
                color: hasAbsentees ? const Color(0xFFFCA5A5) : Colors.white70,
              ),
              tooltip: 'Absent alert পাঠান',
              onPressed: _notifyAbsent,
            ),
          IconButton(
            icon: const Icon(Icons.insights_rounded),
            tooltip: 'Analytics',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AttendanceAnalyticsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Two-stage checkpoint tabs: Stage 1 (initial) | Stage 2 (post-leisure verify).
          if (_students.isNotEmpty)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Row(children: [
                Expanded(child: _sessionTabBtn(0, '① প্রাথমিক হাজিরা', Icons.wb_sunny_outlined, emerald)),
                const SizedBox(width: 8),
                Expanded(child: _sessionTabBtn(1, '② বিরতির পর যাচাই', Icons.verified_outlined, emerald)),
              ]),
            ),
          // Class and Date Selector Header Container
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.15))),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _selectedClass,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'শ্রেণি (Class)',
                          prefixIcon: Icon(Icons.school_outlined, color: emerald, size: 20),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        items: _classes.map<DropdownMenuItem<int>>((c) =>
                            DropdownMenuItem(value: c['id'], child: Text('${c['name']} (${c['section']})'))).toList(),
                        onChanged: (v) {
                          setState(() => _selectedClass = v);
                          if (v != null) _loadStudents();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                        decoration: BoxDecoration(
                          color: emerald.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: emerald.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today_rounded, size: 16, color: emerald),
                            const SizedBox(width: 8),
                            Text(
                              _date.toIso8601String().substring(0, 10),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: emerald,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (_students.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  // Real-time counter & Mark all button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          _countChip('P: $presentCount', const Color(0xFF16A34A), const Color(0xFFDCFCE7)),
                          const SizedBox(width: 6),
                          _countChip('A: $absentCount', const Color(0xFFDC2626), const Color(0xFFFEE2E2)),
                          const SizedBox(width: 6),
                          _countChip('L: $lateCount', const Color(0xFFD97706), const Color(0xFFFEF3C7)),
                        ],
                      ),
                      InkWell(
                        onTap: () => _markAll('present'),
                        child: Text(
                          'সবাই Present',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: emerald,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          if (_error != null)
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _students.isEmpty
                    ? _classes.isEmpty
                        ? const Center(child: _RestrictedCard())
                        : Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.touch_app_outlined, size: 48, color: Colors.grey.shade400),
                                const SizedBox(height: 10),
                                const Text(
                                  'উপরে শ্রেণি নির্বাচন করুন',
                                  style: TextStyle(color: Colors.grey, fontSize: 15, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          )
                    : _sessionTab == 1
                        ? _buildStage2List(emerald)
                        : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 96),
                        itemCount: _students.length,
                        itemBuilder: (_, i) {
                          final s = _students[i];
                          final id = s['id'] as int;
                          final currStatus = _status[id] ?? 'present';

                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.02),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              child: Row(
                                children: [
                                  // Roll avatar
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: emerald.withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${s['roll']}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: emerald,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Name
                                  Expanded(
                                    child: Text(
                                      s['name'] ?? '',
                                      style: const TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                  ),

                                  // Segmented status buttons
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _statusButton('P', 'present', currStatus, id, const Color(0xFF16A34A)),
                                      const SizedBox(width: 6),
                                      _statusButton('A', 'absent', currStatus, id, const Color(0xFFDC2626)),
                                      const SizedBox(width: 6),
                                      _statusButton('L', 'late', currStatus, id, const Color(0xFFD97706)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: _students.isEmpty
          ? null
          : FloatingActionButton.extended(
              backgroundColor: emerald,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.save_rounded),
              label: const Text('সংরক্ষণ করুন (Save)', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: _save,
            ),
    );
  }

  Widget _sessionTabBtn(int idx, String label, IconData icon, Color emerald) {
    final on = _sessionTab == idx;
    return InkWell(
      onTap: () => setState(() => _sessionTab = idx),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: on ? emerald : emerald.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: emerald.withValues(alpha: on ? 1 : 0.3)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 17, color: on ? Colors.white : emerald),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800,
              color: on ? Colors.white : emerald)),
        ]),
      ),
    );
  }

  /// Stage-2 verify list: loads Stage-1 (morning) status per student, lets the
  /// teacher resolve each initially-present student. Amber = needs verify,
  /// red styling ONLY for verified unauthorized departure.
  Widget _buildStage2List(Color emerald) {
    if (_stage2Loading) {
      return const Center(
          child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
    }
    final initial = _stage1.values.where((m) => m['morning'] != null).length;
    String initLabel(int sid) {
      final m = _stage1[sid]?['morning'];
      if (m == null) return 'প্রাথমিক রেকর্ড নেই';
      switch ('${m['status'] ?? ''}') {
        case 'present': return 'সকালে: উপস্থিত';
        case 'late': return 'সকালে: দেরি';
        case 'absent': return 'সকালে: অনুপস্থিত';
        case 'leave': return 'সকালে: ছুটি';
        default: return 'সকালে: ${m['status']}';
      }
    }
    final counts = {'present_now': 0, 'early_departure': 0, 'not_found': 0, 'verified_left': 0};
    for (final s in _students) {
      final v = _stage2[s['id'] as int] ?? 'present_now';
      counts[v] = (counts[v] ?? 0) + 1;
    }
    return Column(children: [
      Container(
        margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('POST-LEISURE যাচাই — প্রাথমিক রেকর্ড: $initial/${_students.length} জন',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _countChip('✓ এখন: ${counts['present_now']}', const Color(0xFF16A34A), const Color(0xFFDCFCE7)),
            _countChip('⛱ ছুটি: ${counts['early_departure']}', const Color(0xFF2563EB), const Color(0xFFDBEAFE)),
            _countChip('⚠ খুঁজে পাওয়া যায়নি: ${counts['not_found']}', const Color(0xFFD97706), const Color(0xFFFEF3C7)),
            _countChip('🔴 verified: ${counts['verified_left']}', const Color(0xFFDC2626), const Color(0xFFFEE2E2)),
          ]),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 96),
          itemCount: _students.length,
          itemBuilder: (_, i) {
            final s = _students[i];
            final sid = s['id'] as int;
            final v = _stage2[sid] ?? 'present_now';
            Color edge = Colors.grey.withValues(alpha: 0.12);
            if (v == 'not_found') edge = const Color(0xFFF59E0B);
            if (v == 'verified_left') edge = const Color(0xFFDC2626);
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: edge, width: v == 'present_now' ? 1 : 1.6),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: emerald.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(child: Text('${s['roll']}',
                          style: TextStyle(fontWeight: FontWeight.w800, color: emerald, fontSize: 14))),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${s['name'] ?? ''}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      Text(initLabel(sid), style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
                    ])),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    _stage2Chip(sid, 'present_now', '✓ এখন উপস্থিত', const Color(0xFF16A34A)),
                    _stage2Chip(sid, 'early_departure', '⛱ অনুমোদিত প্রস্থান', const Color(0xFF2563EB)),
                    _stage2Chip(sid, 'not_found', '⚠ পাওয়া যায়নি', const Color(0xFFD97706)),
                    _stage2Chip(sid, 'verified_left', '🔴 যাচাইকৃত অনুমতিহীন', const Color(0xFFDC2626)),
                  ]),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _stage2Chip(int sid, String value, String label, Color color) {
    final on = (_stage2[sid] ?? 'present_now') == value;
    return InkWell(
      onTap: () => _onStage2Tap(sid, value),
      borderRadius: BorderRadius.circular(99),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: on ? color : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withValues(alpha: on ? 1 : 0.35)),
        ),
        child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800,
            color: on ? Colors.white : color)),
      ),
    );
  }

  /// Sensitive transitions (verified_left) require explicit confirmation +
  /// verifier note. not_found is reversible with one tap; verified_left needs
  /// the confirm dialog so "escaped" is never recorded by accident.
  Future<void> _onStage2Tap(int sid, String value) async {
    if (value == 'verified_left') {
      final name = (_students.firstWhere((s) => s['id'] == sid, orElse: () => {'name': ''})['name'] ?? '').toString();
      final noteCtl = TextEditingController(text: _stage2Note[sid] ?? '');
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('🔴 অনুমতিহীন প্রস্থান যাচাই'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('"$name" সকালে উপস্থিত ছিল, এখন পাওয়া যাচ্ছে না।\n\nশ্রেণিকক্ষ, অনুমোদিত স্থান ও ছুটির রেকর্ড যাচাই করেছেন কি? শুধু authorized verifier-ই confirm করবেন।'),
            const SizedBox(height: 10),
            TextField(controller: noteCtl, maxLines: 2,
                decoration: const InputDecoration(labelText: 'যাচাই নোট *', border: OutlineInputBorder(), isDense: true)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('বাতিল')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
              onPressed: () {
                if (noteCtl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(c).showSnackBar(
                      const SnackBar(content: Text('যাচাই নোট লিখুন (কে, কখন, কোথায় খুঁজলেন)')));
                  return;
                }
                Navigator.pop(c, true);
              },
              child: const Text('যাচাই Confirm'),
            ),
          ],
        ),
      );
      noteCtl.dispose();
      if (ok != true || !mounted) return;
      setState(() {
        _stage2[sid] = value;
        _stage2Note[sid] = noteCtl.text.trim();
      });
      return;
    }
    setState(() => _stage2[sid] = value);
  }

  Widget _countChip(String text, Color textCol, Color bgCol) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgCol,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: textCol.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(color: textCol, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _statusButton(String label, String value, String current, int studentId, Color color) {
    final isSelected = current == value;
    return InkWell(
      onTap: () => setState(() => _status[studentId] = value),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.25),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: isSelected ? Colors.white : color,
            ),
          ),
        ),
      ),
    );
  }
}

class _RestrictedCard extends StatelessWidget {
  const _RestrictedCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline_rounded, size: 44, color: Color(0xFFD97706)),
            const SizedBox(height: 10),
            const Text(
              'Attendance Restricted',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
            ),
            const SizedBox(height: 8),
            Text(
              'শুধুমাত্র designated Class Teacher-ই attendance নিতে পারবেন।\n'
              'আপনি আপাতত কোনো class-এর class teacher নন।\n'
              'Admin panel → Class & Class Teacher Allocation-এ আপনার ভূমিকা set করুন।',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.brown.shade700, height: 1.5, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}