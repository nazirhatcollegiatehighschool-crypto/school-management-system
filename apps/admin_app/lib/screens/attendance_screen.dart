import 'package:flutter/material.dart';
import '../api.dart';

/// Admin attendance section: live board (who submitted today), reopen requests,
/// direct unlock, per-class report %, audit trail, settings, CSV export.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  DateTime _date = DateTime.now();

  String get _dateStr => _date.toIso8601String().substring(0, 10);

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context, initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _date = d);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('হাজিরা · $_dateStr'),
        actions: [IconButton(icon: const Icon(Icons.calendar_month), onPressed: _pickDate)],
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Live Board'),
            Tab(text: 'Requests'),
            Tab(text: 'Report'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _BoardTab(date: _dateStr),
          _RequestsTab(date: _dateStr),
          _ReportTab(date: _dateStr),
        ],
      ),
    );
  }
}

// ============================================================ LIVE BOARD
class _BoardTab extends StatefulWidget {
  final String date;
  const _BoardTab({required this.date});
  @override
  State<_BoardTab> createState() => _BoardTabState();
}

class _BoardTabState extends State<_BoardTab> {
  List _classes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _BoardTab old) {
    super.didUpdateWidget(old);
    if (old.date != widget.date) _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await Api.get('/attendance/admin/board?date=${widget.date}');
      if (!mounted) return;
      setState(() {
        _classes = r is Map && r['classes'] is List ? r['classes'] as List : [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!, textAlign: TextAlign.center),
        const SizedBox(height: 10),
        FilledButton(onPressed: _load, child: const Text('Retry')),
      ]));
    }
    if (_classes.isEmpty) return const Center(child: Text('No classes'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _classes.length,
        itemBuilder: (_, i) => _classCard(_classes[i]),
      ),
    );
  }

  Widget _classCard(Map c) {
    final m = c['morning'] as Map? ?? {};
    final a = c['p5'] as Map? ?? {};
    final holiday = c['is_holiday'] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${c['class_name'] ?? ''} ${c['section'] ?? ''} ${c['group_name'] ?? ''}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            if (holiday) const Icon(Icons.beach_access, color: Colors.orange, size: 18),
          ]),
          const SizedBox(height: 6),
          Text('Class teacher: ${c['class_teacher'] ?? '—'} · ${c['total_students']} জন',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 8),
          _sessionLine('সকাল', m),
          const SizedBox(height: 4),
          _sessionLine('৫ম পিরিয়ড', a),
        ]),
      ),
    );
  }

  Widget _sessionLine(String label, Map m) {
    final taken = m['taken'] == true;
    final by = m['by'] as String?;
    final present = m['present'] ?? 0;
    final absent = m['absent'] ?? 0;
    final state = m['state'] as Map? ?? {};
    final open = state['open'] == true;
    final col = taken ? Colors.green : open ? Colors.blue : Colors.grey;
    return Row(children: [
      Icon(taken ? Icons.check_circle : open ? Icons.radio_button_unchecked : Icons.lock,
          color: col, size: 16),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
            taken ? '$label — $by ($present উপস্থিত, $absent অনুপস্থিত)' : (open ? '$label — open' : '$label — বাকি'),
            style: TextStyle(fontSize: 12, color: col, fontWeight: FontWeight.w600)),
      ),
    ]);
  }
}

// ============================================================ REQUESTS
class _RequestsTab extends StatefulWidget {
  final String date;
  const _RequestsTab({required this.date});
  @override
  State<_RequestsTab> createState() => _RequestsTabState();
}

class _RequestsTabState extends State<_RequestsTab> {
  List _reqs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Api.get('/attendance/admin/requests');
      if (!mounted) return;
      setState(() { _reqs = r is List ? r : []; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decide(int id, bool approve) async {
    try {
      await Api.post('/attendance/admin/requests/$id/decide', {'approve': approve});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(approve ? 'Approved — 2h reopen' : 'Denied')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _unlock() async {
    final cid = TextEditingController();
    final date = TextEditingController(text: widget.date);
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Direct unlock (2h)'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: cid, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Class ID', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: date, decoration: const InputDecoration(labelText: 'Date (YYYY-MM-DD)', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Unlock')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await Api.post('/attendance/admin/unlock', {
        'class_id': int.tryParse(cid.text) ?? 0,
        'date': date.text.trim(),
        'session': 'morning',
        'reason': reason.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unlocked for 2h')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _reqs.isEmpty
                  ? const Center(child: Text('No pending reopen requests'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _reqs.length,
                      itemBuilder: (_, i) => _reqCard(_reqs[i]),
                    ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _unlock,
        icon: const Icon(Icons.lock_open),
        label: const Text('Direct unlock'),
      ),
    );
  }

  Widget _reqCard(Map r) {
    final id = r['id'] as int? ?? 0;
    final sess = (r['session'] ?? 'morning').toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${r['class_name'] ?? ''} ${r['section'] ?? ''}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('${r['date']?.toString().substring(0, 10)} · $sess · by ${r['requested_by_name'] ?? '—'}',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          if (r['reason'] != null && '${r['reason']}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${r['reason']}', style: const TextStyle(fontSize: 12, color: Colors.black87)),
            ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _decide(id, true),
                icon: const Icon(Icons.check, size: 18), label: const Text('Approve (2h)'),
                style: FilledButton.styleFrom(backgroundColor: Colors.green),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _decide(id, false),
                icon: const Icon(Icons.close, size: 18), label: const Text('Deny'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ============================================================ REPORT
class _ReportTab extends StatefulWidget {
  final String date;
  const _ReportTab({required this.date});
  @override
  State<_ReportTab> createState() => _ReportTabState();
}

class _ReportTabState extends State<_ReportTab> {
  List _classes = [];
  int? _classId;
  Map? _report;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    try {
      final r = await Api.get('/admin/classes');
      if (!mounted) return;
      setState(() => _classes = r is List ? r : (r is Map && r['classes'] is List ? r['classes'] as List : []));
    } catch (_) {}
  }

  Future<void> _run() async {
    if (_classId == null) return;
    setState(() => _loading = true);
    try {
      final month = widget.date.substring(0, 7);
      final r = await Api.get('/attendance/admin/report?class_id=$_classId&from=$month-01&to=${widget.date}');
      if (!mounted) return;
      setState(() { _report = r is Map ? r : null; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _showActivity(Map student) async {
    final sid = student['student_id'];
    final month = widget.date.substring(0, 7);
    try {
      final r = await Api.get('/attendance/guardian/$sid?month=$month');
      if (!mounted) return;
      final records = (r is Map && r['records'] is List) ? r['records'] as List : [];
      final summary = r is Map ? r['summary'] as Map? : null;
      final s = summary ?? {};
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => DraggableScrollableSheet(
          initialChildSize: 0.7, maxChildSize: 0.95,
          expand: false,
          builder: (_, scroll) => Container(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${student['name'] ?? ''} — হাজিরার বিস্তারিত',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('মাস: $month · উপস্থিত ${s['present_days'] ?? 0} · দেরি ${s['late_days'] ?? 0} · '
                  'ছুটি ${s['leave_days'] ?? 0} · অনুপস্থিত ${s['absent_days'] ?? 0} · '
                  '${s['percent'] ?? 0}%',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
              const Divider(),
              Expanded(
                child: records.isEmpty
                    ? const Center(child: Text('এই মাসে কোনো রেকর্ড নেই'))
                    : ListView.builder(
                        controller: scroll,
                        itemCount: records.length,
                        itemBuilder: (_, i) {
                          final a = records[i];
                          final st = '${a['status'] ?? a['final_state'] ?? ''}';
                          final sess = a['session'] == 'p5' ? '৫ম পিরিয়ড' : 'সকাল';
                          final remark = '${a['remark'] ?? ''}'.trim();
                          return ListTile(
                            dense: true,
                            title: Text('${a['date'].toString().substring(0, 10)} · $sess'),
                            subtitle: Text([
                              if (a['recorded_by'] != null) 'নিয়েছেন: ${a['recorded_by']}',
                              if (remark.isNotEmpty) 'নোট: $remark',
                            ].join(' · '), style: const TextStyle(fontSize: 12)),
                            trailing: Text(_statusLabel(st),
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                                    color: _statusColor(st))),
                          );
                        },
                      ),
              ),
            ]),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  String _statusLabel(String st) => switch (st) {
    'present' => 'উপস্থিত',
    'absent' => 'অনুপস্থিত',
    'late' => 'দেরি',
    'leave' => 'ছুটি',
    'early_departure_with_leave' => 'ছুটি নিয়ে প্রস্থান',
    'early_departure_no_leave' => 'ছুটি ছাড়া প্রস্থান',
    _ => st,
  };

  Color _statusColor(String st) => switch (st) {
    'present' => Colors.green,
    'absent' => Colors.red,
    'late' => Colors.orange,
    'leave' => Colors.blue,
    'early_departure_with_leave' || 'early_departure_no_leave' => Colors.purple,
    _ => Colors.grey,
  };

  Future<void> _export() async {
    try {
      final r = await Api.get('/attendance/admin/export');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export ready (${r is String ? r.split('\n').length : 0} rows) — see /api/attendance/admin/export')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final students = _report?['students'] is List ? _report!['students'] as List : [];
    final thr = _report?['threshold'] ?? 75;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: _classId,
              decoration: const InputDecoration(labelText: 'Class', border: OutlineInputBorder(), isDense: true),
              items: _classes.map<DropdownMenuItem<int>>((c) {
                final id = int.tryParse('${c['id']}') ?? 0;
                return DropdownMenuItem(value: id, child: Text('${c['name'] ?? ''} ${c['section'] ?? ''}'));
              }).toList(),
              onChanged: (v) => setState(() { _classId = v; _report = null; }),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: _classId == null || _loading ? null : _run,
              child: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Report')),
          IconButton(icon: const Icon(Icons.download), onPressed: _export, tooltip: 'CSV export'),
        ]),
      ),
      Expanded(
        child: students.isEmpty
            ? const Center(child: Text('Select a class and run report'))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: students.length,
                itemBuilder: (_, i) {
                  final s = students[i];
                  final pct = (s['percent'] is num) ? (s['percent'] as num).toDouble() : 0.0;
                  final low = pct < (thr is num ? thr.toDouble() : 75);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    child: ListTile(
                      dense: true,
                      onTap: () => _showActivity(Map<String, dynamic>.from(s as Map)),
                      leading: CircleAvatar(child: Text('${s['roll'] ?? ''}', style: const TextStyle(fontSize: 12))),
                      title: Text('${s['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${s['present'] ?? 0}P ${s['late'] ?? 0}L ${s['absent'] ?? 0}A ${s['leave'] ?? 0}Lv · ${s['school_days'] ?? 0} দিন',
                          style: const TextStyle(fontSize: 12)),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (low ? Colors.red : Colors.green).withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('${pct.toStringAsFixed(1)}%',
                            style: TextStyle(color: low ? Colors.red : Colors.green, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}
