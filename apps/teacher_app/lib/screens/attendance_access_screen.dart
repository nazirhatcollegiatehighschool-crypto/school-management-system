import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';

class AttendanceAccessScreen extends StatefulWidget {
  const AttendanceAccessScreen({super.key});
  @override
  State<AttendanceAccessScreen> createState() => _AttendanceAccessScreenState();
}

class _AttendanceAccessScreenState extends State<AttendanceAccessScreen> {
  Map _options = const {};
  List _sent = const [], _inbox = const [], _history = const [];
  int? _classId, _teacherId;
  String _session = 'morning';
  bool _loading = true, _saving = false;
  String? _error;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  bool _expired(Map row) {
    final status = '${row['status'] ?? ''}';
    if (status == 'expired') return true;
    if (status != 'pending') return false;
    final at = int.tryParse('${row['expires_at_epoch'] ?? ''}');
    return at != null && at <= DateTime.now().millisecondsSinceEpoch;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await Future.wait([
        Api.get('/attendance/access/options'),
        Api.get('/attendance/access-requests?box=sent'),
        Api.get('/attendance/access-requests?box=inbox'),
        Api.get('/attendance/delegated-history'),
      ]);
      if (!mounted) return;
      final options = data[0] is Map ? data[0] as Map : {};
      final classes = options['classes'] is List
          ? options['classes'] as List
          : [];
      final teachers = options['teachers'] is List
          ? options['teachers'] as List
          : [];
      setState(() {
        _options = options;
        _sent = data[1] is List ? data[1] as List : [];
        _inbox = data[2] is List ? data[2] as List : [];
        _history = data[3] is List ? data[3] as List : [];
        _classId ??= classes
            .whereType<Map>()
            .map((r) => int.tryParse('${r['id']}'))
            .whereType<int>()
            .firstOrNull;
        _teacherId ??= teachers
            .whereType<Map>()
            .map((r) => int.tryParse('${r['id']}'))
            .whereType<int>()
            .firstOrNull;
        _loading = false;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
    }
  }

  Future<void> _save({required bool direct}) async {
    if (_classId == null || (direct && _teacherId == null)) return;
    setState(() => _saving = true);
    try {
      await Api.post(
        direct ? '/attendance/delegations' : '/attendance/access-requests',
        {
          'class_id': _classId,
          'date':
              '${_options['date'] ?? DateTime.now().toIso8601String().substring(0, 10)}',
          'session': _session,
          if (direct) 'teacher_id': _teacherId,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            direct
                ? 'দায়িত্ব দেওয়া হয়েছে'
                : 'Class teacher-কে request পাঠানো হয়েছে',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _decision(Map row, bool accept) async {
    try {
      await Api.post('/attendance/access-requests/${row['id']}/decision', {
        'decision': accept ? 'accept' : 'reject',
      });
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      await _load();
    }
  }

  Future<void> _showHistory(Map item) async {
    try {
      final row = await Api.get('/attendance/delegated-history/${item['id']}');
      if (!mounted || row is! Map) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            '${row['class_name']} ${row['section'] ?? ''} · Roll ${row['roll']}',
          ),
          content: Text(
            'শিক্ষার্থী: ${row['student_name']}\nতারিখ: ${row['date']}\nসেশন: ${row['session']}\nহাজিরা: ${row['status']}\nমন্তব্য: ${row['remark'] ?? '—'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('বন্ধ করুন'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('হাজিরার অনুমতি ও History'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
        bottom: const TabBar(
          tabs: [
            Tab(icon: Icon(Icons.send_outlined), text: 'Request'),
            Tab(icon: Icon(Icons.assignment_ind_outlined), text: 'Delegate'),
            Tab(icon: Icon(Icons.history), text: 'History'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : TabBarView(
              children: [_requestTab(), _delegateTab(), _historyTab()],
            ),
    ),
  );

  Widget _classPicker() => DropdownButtonFormField<int>(
    initialValue: _classId,
    decoration: const InputDecoration(
      labelText: 'Class / Section',
      border: OutlineInputBorder(),
    ),
    items: (_options['classes'] as List? ?? [])
        .whereType<Map>()
        .map(
          (r) => DropdownMenuItem<int>(
            value: int.tryParse('${r['id']}'),
            child: Text(
              '${r['name']} ${r['section'] ?? ''} · ${r['class_teacher_name'] ?? 'Class Teacher নেই'}',
            ),
          ),
        )
        .where((i) => i.value != null)
        .toList(),
    onChanged: (v) => setState(() => _classId = v),
  );

  Widget _sessionPicker() => DropdownButtonFormField<String>(
    initialValue: _session,
    decoration: const InputDecoration(
      labelText: 'Attendance period',
      border: OutlineInputBorder(),
    ),
    items: const [
      DropdownMenuItem(value: 'morning', child: Text('দৈনিক হাজিরা')),
      DropdownMenuItem(value: 'p5', child: Text('৫ম পিরিয়ড')),
    ],
    onChanged: (v) => setState(() => _session = v ?? 'morning'),
  );

  Widget _requestTab() => RefreshIndicator(
    onRefresh: _load,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _classPicker(),
        const SizedBox(height: 12),
        _sessionPicker(),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _saving ? null : () => _save(direct: false),
          icon: const Icon(Icons.send),
          label: Text(
            _saving ? 'পাঠানো হচ্ছে…' : 'Class Teacher-কে Request পাঠান',
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'আপনার পাঠানো Request',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        ..._sent.map((r) => _requestCard(r, inbox: false)),
      ],
    ),
  );

  Widget _delegateTab() => RefreshIndicator(
    onRefresh: _load,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _classPicker(),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _teacherId,
          decoration: const InputDecoration(
            labelText: 'Teacher',
            border: OutlineInputBorder(),
          ),
          items: (_options['teachers'] as List? ?? [])
              .whereType<Map>()
              .map(
                (r) => DropdownMenuItem<int>(
                  value: int.tryParse('${r['id']}'),
                  child: Text('${r['name']} · ${r['phone'] ?? 'ফোন নেই'}'),
                ),
              )
              .where((i) => i.value != null)
              .toList(),
          onChanged: (v) => setState(() => _teacherId = v),
        ),
        const SizedBox(height: 12),
        _sessionPicker(),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _saving ? null : () => _save(direct: true),
          icon: const Icon(Icons.assignment_ind_outlined),
          label: const Text('Teacher-কে দায়িত্ব দিন'),
        ),
        const SizedBox(height: 20),
        const Text(
          'আপনার class-এর pending Request',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        ..._inbox
            .where((r) => '${r['status']}' == 'pending')
            .map((r) => _requestCard(r, inbox: true)),
        if (_inbox.where((r) => '${r['status']}' == 'pending').isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('কোনো pending request নেই।'),
          ),
      ],
    ),
  );

  Widget _requestCard(Map row, {required bool inbox}) {
    final status = '${row['status'] ?? ''}';
    final expired = _expired(row);
    final effectiveStatus = expired && status == 'pending' ? 'expired' : status;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${row['class_name'] ?? ''} ${row['section'] ?? ''} · ${row['session'] == 'p5' ? '৫ম পিরিয়ড' : 'দৈনিক'}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              inbox
                  ? 'অনুরোধ: ${row['requester_name'] ?? ''}'
                  : 'তারিখ: ${row['attendance_date'] ?? ''}',
            ),
            Text(
              'অবস্থা: $effectiveStatus'
              '${effectiveStatus == 'expired' ? ' — সময় শেষ, আর অনুমোদন করা যাবে না' : ''}',
            ),
            if (inbox && status == 'pending' && !expired)
              Row(
                children: [
                  TextButton(
                    onPressed: () => _decision(row, false),
                    child: const Text('Reject'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => _decision(row, true),
                    child: const Text('Accept'),
                  ),
                ],
              )
            else if (inbox && effectiveStatus == 'expired')
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Chip(
                  avatar: Icon(Icons.timer_off_outlined, size: 16),
                  label: Text('মেয়াদোত্তীর্ণ'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _historyTab() => RefreshIndicator(
    onRefresh: _load,
    child: _history.isEmpty
        ? ListView(
            children: const [
              SizedBox(height: 180),
              Center(child: Text('অন্য class-এ নেওয়া হাজিরার history নেই।')),
            ],
          )
        : ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _history.length,
            itemBuilder: (_, i) {
              final r = _history[i];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.fact_check_outlined),
                  ),
                  title: Text(
                    '${r['class_name']} ${r['section'] ?? ''} · ${r['session']}',
                  ),
                  subtitle: Text(
                    '${r['date']} · Roll ${r['roll']} ${r['student_name']} · ${r['status']}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showHistory(r),
                ),
              );
            },
          ),
  );
}
