import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../api.dart';
import 'attendance_analytics_screen.dart';
import 'attendance_access_screen.dart';

/// Attendance v2 — today's pending list + per-session entry + history browse.
class AttendanceScreen extends StatefulWidget {
  final dynamic teacher;
  final int? initialClassId;
  const AttendanceScreen({super.key, required this.teacher, this.initialClassId});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  DateTime _date = DateTime.now();
  Map? _today;
  List _classes = [];
  bool _loading = true;
  String? _error;

  String get _dateStr => _date.toIso8601String().substring(0, 10);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await Api.get('/attendance/today?date=$_dateStr');
      if (!mounted) return;
      setState(() {
        _today = r is Map ? r : null;
        _classes = (r is Map && r['classes'] is List) ? r['classes'] as List : [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context, initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
    );
    if (d != null) { setState(() => _date = d); _load(); }
  }

  @override
  Widget build(BuildContext context) {
    final weekend = _today?['weekend'] == true;
    return Scaffold(
      appBar: AppBar(
        title: Text('হাজিরা · ${_dateStr}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz_rounded),
            tooltip: 'অনুমতি, delegation ও history',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceAccessScreen())).then((_) => _load()),
          ),
          IconButton(icon: const Icon(Icons.calendar_month), onPressed: _pickDate, tooltip: 'তারিখ'),
          IconButton(
            icon: const Icon(Icons.analytics),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceAnalyticsScreen())),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorView()
              : _classes.isEmpty
                  ? _emptyView()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          if (weekend) _weekendBanner(),
                          ..._classes.map((c) => _classCard(c)),
                          const SizedBox(height: 60),
                        ],
                      ),
                    ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 40, color: Colors.red),
          const SizedBox(height: 8),
          Text(_error ?? '', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('আবার চেষ্টা')),
        ]),
      ),
    );
  }

  Widget _emptyView() {
    final weekend = _today?['weekend'] == true;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(weekend ? Icons.beach_access : Icons.check_circle, size: 52,
              color: weekend ? Colors.orange : Colors.green),
          const SizedBox(height: 10),
          Text(weekend ? 'শুক্র/শনিবার — স্কুল বন্ধ' : 'আজ কোনো হাজিরার দায়িত্ব নেই',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(weekend ? 'চাইলে "Present call খুলুন" দিয়ে হাজিরা নিতে পারবেন।'
              : 'আপনি আজকের জন্য শ্রেণি শিক্ষক বা ৫ম পিরিয়ডের শিক্ষক নন।',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            icon: const Icon(Icons.meeting_room), label: const Text('Present call খুলুন'),
            onPressed: () => _openPresentCall(),
          ),
        ]),
      ),
    );
  }

  Widget _weekendBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFB923C)),
      ),
      child: const Row(children: [
        Icon(Icons.beach_access, color: Color(0xFFEA580C)),
        SizedBox(width: 10),
        Expanded(child: Text('শুক্র/শনিবার — স্কুল বন্ধ। Present call খুললেই হাজিরা নেওয়া যাবে।',
            style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF9A3412)))),
      ]),
    );
  }

  Future<void> _openPresentCall() async {
    final c = await showModalBottomSheet<Map<String, dynamic>>(
      context: context, isScrollControlled: true,
      builder: (_) => const _OpenCallSheet(),
    );
    if (c == null || !mounted) return;
    try {
      final classId = c['class_id'] as int;
      final session = c['session'] as String;
      await Api.postOptimistic('/attendance/class/$classId/open',
          {'date': _dateStr, 'session': session}, {});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Present call খোলা হয়েছে')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Widget _classCard(Map c) {
    final role = c['role'] as String? ?? 'ct';
    final roleBn = role == 'ct' ? 'শ্রেণি শিক্ষক' : role == 'p5' ? '৫ম পিরিয়ড' : 'প্রতিনিধি';
    final roleCol = role == 'ct' ? Colors.blue : role == 'p5' ? Colors.teal : Colors.purple;
    final sessions = <String>[];
    if (c['morning'] is Map) sessions.add('morning');
    if (c['p5'] is Map) sessions.add('p5');
    final holiday = c['is_holiday'] == true;
    final occ = c['occasion'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${c['class_name'] ?? ''} ${c['section'] ?? ''} ${c['group_name'] ?? ''}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: roleCol.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(roleBn, style: TextStyle(color: roleCol, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ]),
          if (holiday) Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('📅 ছুটি${occ != null ? ' — $occ' : ''}',
                style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 8),
          ...sessions.map((s) => _sessionRow(c, s)),
        ]),
      ),
    );
  }

  Widget _sessionRow(Map c, String sess) {
    final m = c[sess] as Map? ?? {};
    final taken = m['taken'] == true;
    final open = m['open'] == true;
    final reason = m['reason'] as String? ?? '';
    final reasonBn = switch (reason) {
      'locked' => 'জমা হয়ে গেছে',
      'window' => 'এখন নেওয়া যাবে',
      'reopened' => 'Reopen করা হয়েছে',
      'opened' => 'Present call খোলা',
      'weekend' => 'ছুটি',
      'holiday' => 'ছুটি',
      'outside' => 'পিরিয়ডের সময় নেই',
      'no_p5' => '৫ম পিরিয়ড নেই',
      _ => '',
    };
    final sessBn = sess == 'p5' ? '৫ম পিরিয়ড' : 'সকাল';
    final present = m['present'] ?? 0;
    final absent = m['absent'] ?? 0;
    final total = m['total'] ?? 0;
    final takenAt = m['taken_at'] as String?;

    final color = taken ? Colors.green : open ? Colors.blue : Colors.grey;
    return InkWell(
      onTap: open || taken ? () => _openEntry(c, sess) : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: .25)),
        ),
        child: Row(children: [
          Icon(taken ? Icons.check_circle : open ? Icons.radio_button_unchecked : Icons.lock,
              color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$sessBn — $reasonBn',
                  style: TextStyle(fontWeight: FontWeight.w600, color: color, fontSize: 13)),
              if (taken && sess == 'p5') ...[
                Text('মোট ${m['eligible'] ?? 0} জন যোগ্য',
                    style: const TextStyle(fontSize: 11, color: Colors.black54)),
                Wrap(spacing: 2, children: [
                  TextButton(
                    onPressed: () => _openEntry(c, sess, p5Filter: 'with_leave'),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    child: Text('ছুটি নিয়ে ${m['with_leave'] ?? 0} জন', style: const TextStyle(fontSize: 11, color: Colors.purple)),
                  ),
                  TextButton(
                    onPressed: () => _openEntry(c, sess, p5Filter: 'without_leave'),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    child: Text('ছুটি ছাড়া ${m['without_leave'] ?? 0} জন', style: const TextStyle(fontSize: 11, color: Colors.brown)),
                  ),
                ]),
              ] else if (taken) Text('$present উপস্থিত · $absent অনুপস্থিত · $total মোট',
                  style: const TextStyle(fontSize: 11, color: Colors.black54)),
              if (taken && takenAt != null) Text('নেওয়া: ${takenAt.substring(0, 16)}',
                  style: const TextStyle(fontSize: 10, color: Colors.black38)),
            ]),
          ),
          if (taken) const Icon(Icons.chevron_right, color: Colors.black26),
        ]),
      ),
    );
  }

  void _openEntry(Map c, String sess, {String? p5Filter}) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _EntryScreen(
        classId: c['class_id'] as int,
        className: '${c['class_name'] ?? ''} ${c['section'] ?? ''}',
        session: sess,
        date: _dateStr,
        canSubmit: true,
        p5Filter: p5Filter,
      ),
    )).then((_) => _load());
  }
}

// ============================================================ ENTRY SCREEN
class _EntryScreen extends StatefulWidget {
  final int classId;
  final String className;
  final String session;
  final String date;
  final bool canSubmit;
  final String? p5Filter;
  const _EntryScreen({required this.classId, required this.className,
    required this.session, required this.date, required this.canSubmit, this.p5Filter});

  @override
  State<_EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<_EntryScreen> {
  List _students = [];
  Map<int, String> _status = {};
  Map<int, String> _notes = {};
  Map? _meta;
  bool _loading = true;
  bool _saving = false;
  bool _submitted = false;
  String? _error;
  String _search = '';
  final _searchCtl = TextEditingController();

  String get _sessBn => widget.session == 'p5' ? '৫ম পিরিয়ড' : 'সকাল';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await Api.get(
          '/attendance/class/${widget.classId}?date=${widget.date}&session=${widget.session}');
      if (!mounted) return;
      final list = (r is Map && r['students'] is List) ? r['students'] as List : [];
      setState(() {
        _meta = r is Map ? r : null;
        _students = list;
        _status = {};
        _notes = {};
        for (final s in list) {
          final sid = s['student_id'] as int;
          final saved = s['status'];
          final remark = s['remark'];
          // NO default status — the teacher must choose for every student.
          if (saved != null) _status[sid] = saved as String;
          if (remark != null && remark.toString().trim().isNotEmpty) {
            _notes[sid] = remark.toString();
          }
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  /// P5 shows only students who were Present in 1st period.
  List get _visibleStudents => widget.session == 'p5'
      ? _students.where((s) => s['p5_eligible'] == true).toList()
      : _students;

  bool get _readOnly {
    final state = _meta?['state'];
    return _submitted || _meta?['can_take'] != true ||
        (state is Map && state['open'] != true);
  }

  List get _filtered {
    var base = _visibleStudents;
    if (widget.p5Filter == 'with_leave') {
      base = base.where((s) => (s['p5_outcome'] ?? s['status']) == 'early_departure_with_leave').toList();
    } else if (widget.p5Filter == 'without_leave') {
      base = base.where((s) => (s['p5_outcome'] ?? s['status']) == 'early_departure_no_leave').toList();
    }
    if (_search.isEmpty) return base;
    final q = _search.toLowerCase();
    return base.where((s) {
      final n = (s['name'] ?? '').toString().toLowerCase();
      final r = (s['roll'] ?? '').toString();
      return n.contains(q) || r.contains(q);
    }).toList();
  }

  int _count(String st) => _status.values.where((v) => v == st).length;

  Future<void> _save() async {
    if (_saving) return;
    // 1st period: every student must get one of the 4 statuses.
    // 5th period: only mark the students who left early; the rest stayed.
    if (widget.session != 'p5') {
      final missing = _visibleStudents
          .where((s) => !_status.containsKey(s['student_id'] as int))
          .length;
      if (missing > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text('$missing জন শিক্ষার্থীর হাজিরা এখনো দেওয়া হয়নি। সবাইকে একটি স্ট্যাটাস দিন।'),
        ));
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final records = _visibleStudents.where((s) => _status.containsKey(s['student_id'] as int)).map((s) {
        final sid = s['student_id'] as int;
        return {
          'student_id': sid,
          'status': _status[sid],
          'remark': _notes[sid],
        };
      }).toList();
      final idem = const Uuid().v4();
      final result = await Api.postOptimistic(
          '/attendance/class/${widget.classId}',
          {'date': widget.date, 'session': widget.session, 'records': records, 'idem_key': idem},
          {});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Api.isQueued(result)
              ? '$_sessBn হাজিরা ফোনে সেভ হয়েছে; online হলে পাঠানো হবে'
              : '$_sessBn হাজিরা জমা হয়েছে')));
      setState(() { _submitted = true; _saving = false; });
      if (!Api.isQueued(result)) await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _requestReopen() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (c) {
        final ctl = TextEditingController();
        return AlertDialog(
          title: const Text('Reopen অনুরোধ'),
          content: TextField(
            controller: ctl, maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'কারণ', border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('বাতিল')),
            FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('পাঠান')),
          ],
        );
      },
    );
    if (reason == null || !mounted) return;
    try {
      await Api.postOptimistic(
          '/attendance/class/${widget.classId}/request-reopen',
          {'date': widget.date, 'session': widget.session, 'reason': reason}, {});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reopen অনুরোধ পাঠানো হয়েছে')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _editNote(int sid, {String? hint}) async {
    final ctl = TextEditingController(text: _notes[sid] ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('নোট / কারণ'),
        content: TextField(
          controller: ctl, maxLines: 3, autofocus: true,
          decoration: InputDecoration(
            hintText: hint ?? 'যেমন: অসুস্থতা, অভিভাবকের অনুমতি ইত্যাদি',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('বাতিল')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('সংরক্ষণ')),
        ],
      ),
    );
    if (v == null || !mounted) return;
    setState(() {
      final t = v.trim();
      if (t.isEmpty) {
        _notes.remove(sid);
      } else {
        _notes[sid] = t;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.className)),
        body: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('আবার চেষ্টা')),
          ]),
        )),
      );
    }
    final state = _meta?['state'] as Map? ?? {};
    final canTake = _meta?['can_take'] == true;
    final open = state['open'] == true;
    final holiday = _meta?['holiday'] == true;
    final occ = _meta?['occasion'] as String?;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.className} · $_sessBn'),
        actions: [
          IconButton(icon: const Icon(Icons.search),
              onPressed: () => showSearch(context: context, delegate: _RollSearch(_visibleStudents, _status))),
        ],
      ),
      body: Column(children: [
        // summary strip
        Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              widget.session == 'p5'
                  ? '৫ম পিরিয়ড: ${_visibleStudents.length} জন যোগ্য শিক্ষার্থীর মধ্যে ${_count('early_departure_with_leave') + _count('early_departure_no_leave')} জনের প্রস্থান রেকর্ড'
                  : '${_visibleStudents.length} জনের মধ্যে ${_count('present') + _count('late')} জন উপস্থিত, ${_count('absent')} জন অনুপস্থিত',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 14, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (widget.session == 'p5') ...[
              _sumChip('মোট যোগ্য ${_visibleStudents.length} জনের মধ্যে', _visibleStudents.length, Colors.indigo),
              _sumChip('ছুটি নিয়ে প্রস্থান', _count('early_departure_with_leave'), Colors.purple),
              _sumChip('ছুটি ছাড়া প্রস্থান', _count('early_departure_no_leave'), Colors.brown),
            ] else ...[
              _sumChip('মোট শিক্ষার্থী', _visibleStudents.length, Colors.indigo),
              _sumChip('উপস্থিত', _count('present') + _count('late'), Colors.green),
              _sumChip('অনুপস্থিত', _count('absent'), Colors.red),
              if (_count('late') > 0) _sumChip('দেরি', _count('late'), Colors.orange),
              if (_count('leave') > 0) _sumChip('ছুটি', _count('leave'), Colors.blue),
            ],
            if (_submitted) const Text('জমা সম্পন্ন', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            if (holiday) Text('📅 ${occ ?? 'ছুটি'}', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),
        // quick actions
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            if (widget.session != 'p5') ...[
              _quickBtn('সব উপস্থিত', Icons.done_all, Colors.green, () {
                setState(() {
                  for (final s in _students) {
                    _status[s['student_id'] as int] = 'present';
                  }
                });
              }),
              const SizedBox(width: 8),
            ],
            if (canTake) _quickBtn('Reopen চাই', Icons.lock_open, Colors.orange, _requestReopen),
          ]),
        ),
        if (!open && _meta?['taken'] == true)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFB923C)),
            ),
            child: const Row(children: [
              Icon(Icons.lock, size: 18, color: Color(0xFFEA580C)),
              SizedBox(width: 8),
              Expanded(child: Text('হাজিরা জমা হয়ে লক হয়েছে। পরিবর্তন করতে admin-এর কাছে Reopen চাই করুন।',
                  style: TextStyle(fontSize: 12, color: Color(0xFF9A3412)))),
            ]),
          ),
        if (widget.session == 'p5')
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Text(
              'যারা ছুটি নিয়ে/ছাড়া চলে গেছে শুধু তাদের মার্ক করুন। বাকিরা স্কুলে আছে ধরা হবে।',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
        const SizedBox(height: 6),
        // roster
        Expanded(
          child: _filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      widget.session == 'p5'
                          ? '১ম পিরিয়ডে উপস্থিত কোনো শিক্ষার্থী নেই।\nআগে সকালের হাজিরা দিন।'
                          : 'কোনো ছাত্রছাত্রী নেই',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) => _studentRow(_filtered[i]),
                ),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: (open && canTake && !_saving && !_submitted) ? _save : null,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save),
            label: Text(_saving ? 'জমা হচ্ছে...' : (widget.session == 'p5' ? '৫ম পিরিয়ড জমা দিন' : 'হাজিরা জমা দিন')),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: open && canTake ? const Color(0xFF2563EB) : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }

  Widget _sumChip(String label, int n, Color c) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Column(children: [
        Text('$n', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
      ]),
    );
  }

  Widget _quickBtn(String label, IconData icon, Color c, VoidCallback onTap) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: onTap, icon: Icon(icon, size: 18, color: c), label: Text(label, style: TextStyle(color: c, fontSize: 12)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: c.withValues(alpha: .4)),
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  Widget _studentRow(Map s) {
    final sid = s['student_id'] as int;
    final roll = s['roll'] ?? '';
    final name = s['name'] ?? '';
    final note = _notes[sid];
    final morning = s['morning_status'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('$roll. $name', style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (widget.session == 'p5' && morning != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text('সকাল: ${_statusBn(morning)}',
                    style: const TextStyle(fontSize: 10, color: Colors.black45)),
              ),
            if (!_readOnly) IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'নোট / কারণ',
              icon: Icon(
                (note != null && note.isNotEmpty) ? Icons.sticky_note_2 : Icons.note_add_outlined,
                size: 20,
                color: (note != null && note.isNotEmpty) ? Colors.indigo : Colors.grey,
              ),
              onPressed: () => _editNote(sid),
            ),
          ]),
          if (note != null && note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('নোট: $note', style: const TextStyle(fontSize: 11, color: Colors.black54)),
            ),
          const SizedBox(height: 2),
          if (_readOnly && widget.session == 'p5')
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  (s['p5_outcome'] ?? s['status']) == null && _meta?['taken'] != true
                      ? '৫ম পিরিয়ডের হাজিরা এখনো জমা হয়নি'
                      : _statusBn((s['p5_outcome'] ?? s['status'] ?? '').toString()),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
            )
          else Wrap(spacing: 6, runSpacing: 6, children: widget.session == 'p5'
              ? [
                  _statusChip(sid, 'early_departure_with_leave', 'ছুটি নিয়ে প্রস্থান', Colors.purple),
                  _statusChip(sid, 'early_departure_no_leave', 'ছুটি ছাড়া প্রস্থান', Colors.brown),
                ]
              : [
                  _statusChip(sid, 'present', 'উপস্থিত', Colors.green),
                  _statusChip(sid, 'absent', 'অনুপস্থিত', Colors.red),
                  _statusChip(sid, 'late', 'দেরি', Colors.orange),
                  _statusChip(sid, 'leave', 'ছুটি', Colors.blue),
                ]),
        ]),
      ),
    );
  }

  String _statusBn(String st) => switch (st) {
    'present' => 'উপস্থিত',
    'absent' => 'অনুপস্থিত',
    'late' => 'দেরি',
    'leave' => 'ছুটি',
    'early_departure_with_leave' => 'ছুটি নিয়ে প্রস্থান',
    'early_departure_no_leave' => 'ছুটি ছাড়া প্রস্থান',
    'p5_stayed' => '৫ম পিরিয়ড পর্যন্ত স্কুলে ছিলেন',
    '' => 'প্রস্থান রেকর্ড নেই',
    _ => st,
  };

  Widget _statusChip(int sid, String value, String label, Color color) {
    final sel = _status[sid] == value;
    return InkWell(
      onTap: _readOnly ? null : () {
        setState(() => _status[sid] = value);
        if (value == 'leave' ||
            value == 'early_departure_with_leave' ||
            value == 'early_departure_no_leave') {
          _editNote(sid, hint: '${_statusBn(value)}-এর কারণ লিখুন');
        }
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? color : color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? color : color.withValues(alpha: .25), width: sel ? 1.5 : 1),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: sel ? Colors.white : color)),
      ),
    );
  }
}

class _RollSearch extends SearchDelegate<String> {
  final List students;
  final Map<int, String> status;
  _RollSearch(this.students, this.status);

  @override
  String get searchFieldLabel => 'রোল বা নাম খুঁজুন';

  @override
  List<Widget>? buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];

  @override
  Widget? buildLeading(BuildContext context) =>
      IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, ''));

  @override
  Widget buildResults(BuildContext context) => _list(context);

  @override
  Widget buildSuggestions(BuildContext context) => _list(context);

  Widget _list(BuildContext context) {
    final q = query.toLowerCase();
    final filtered = q.isEmpty ? students : students.where((s) {
      return (s['name'] ?? '').toString().toLowerCase().contains(q) ||
          (s['roll'] ?? '').toString().contains(q);
    }).toList();
    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (_, i) {
        final s = filtered[i];
        final st = status[s['student_id']];
        final color = switch (st) {
          'absent' => Colors.red,
          'late' => Colors.orange,
          'leave' => Colors.blue,
          'early_departure_with_leave' || 'early_departure_no_leave' => Colors.purple,
          'present' => Colors.green,
          _ => Colors.grey,
        };
        return ListTile(
          leading: CircleAvatar(child: Text('${s['roll'] ?? ''}', style: const TextStyle(fontSize: 12))),
          title: Text(s['name'] ?? ''),
          trailing: Chip(
            label: Text(st ?? '—', style: const TextStyle(color: Colors.white, fontSize: 11)),
            backgroundColor: color,
          ),
          onTap: () => close(context, '${s['name']}'),
        );
      },
    );
  }
}

// ============================================================ OPEN CALL SHEET
class _OpenCallSheet extends StatefulWidget {
  const _OpenCallSheet();
  @override
  State<_OpenCallSheet> createState() => _OpenCallSheetState();
}

class _OpenCallSheetState extends State<_OpenCallSheet> {
  List _classes = [];
  int? _classId;
  String _session = 'morning';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.get('/teacher/profile');
      if (!mounted) return;
      setState(() {
        _classes = r is Map && r['classes'] is List ? r['classes'] as List : [];
        if (_classes.isNotEmpty) _classId = _classes[0]['id'] as int;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Present call খুলুন',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: _classId,
                  decoration: const InputDecoration(labelText: 'শ্রেণি', border: OutlineInputBorder()),
                  items: _classes.map<DropdownMenuItem<int>>((c) => DropdownMenuItem(
                      value: c['id'] as int,
                      child: Text('${c['name'] ?? ''} ${c['section'] ?? ''}'))).toList(),
                  onChanged: (v) => setState(() => _classId = v),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'morning', label: Text('সকাল')),
                    ButtonSegment(value: 'p5', label: Text('৫ম পিরিয়ড')),
                  ],
                  selected: {_session},
                  onSelectionChanged: (s) => setState(() => _session = s.first),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _classId == null
                        ? null
                        : () => Navigator.pop(context, {'class_id': _classId, 'session': _session}),
                    child: const Text('খুলুন'),
                  ),
                ),
              ]),
      ),
    );
  }
}
