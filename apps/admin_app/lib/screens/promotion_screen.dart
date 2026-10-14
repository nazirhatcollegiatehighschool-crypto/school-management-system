import 'package:flutter/material.dart';
import '../api.dart';

class PromotionScreen extends StatefulWidget {
  const PromotionScreen({super.key});
  @override
  State<PromotionScreen> createState() => _PromotionScreenState();
}

class _PromotionScreenState extends State<PromotionScreen> {
  List _classes = [];
  List _events = [];
  List _review = [];
  int? _classId;
  int? _eventId;
  int _grace = 2;
  bool _reviewed = false;
  bool _loading = false;
  String _error = '';
  String _statusMsg = '';

  final Map<int, bool> _promote = {};      // student id -> promote?
  final Map<int, String> _decision = {};   // server-suggested decision
  final Map<int, String> _note = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final results = await Future.wait([
        Api.get('/admin/classes'),
        Api.get('/results/events'),
      ]);
      setState(() {
        _classes = results[0] is List ? results[0] : [];
        _events = results[1] is List ? results[1] : [];
        _loading = false;
      });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  Future<void> _runReview() async {
    if (_classId == null || _eventId == null) {
      setState(() => _error = 'প্রথমে শ্রেণি এবং পরীক্ষা নির্বাচন করুন');
      return;
    }
    setState(() { _loading = true; _error = ''; _reviewed = false; });
    try {
      final r = await Api.post('/promote/review', {
        'class_id': _classId,
        'event_id': _eventId,
      });
      final review = r['review'] is List ? (r['review'] as List) : [];
      setState(() {
        _review = review;
        _grace = (r['grace_failed'] as num?)?.toInt() ?? 2;
        _promote.clear();
        _decision.clear();
        _note.clear();
        for (final st in review) {
          final id = (st['id'] as num).toInt();
          _promote[id] = (st['decision'] == 'promoted' || st['decision'] == 'grace_promoted');
          _decision[id] = st['decision']?.toString() ?? 'retained';
        }
        _reviewed = true;
        _loading = false;
      });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  Future<void> _saveGrace() async {
    if (_classId == null) return;
    setState(() => _loading = true);
    try {
      await Api.put('/promote/grace', {
        'class_id': _classId,
        'exam_type': 'test',
        'grace_failed': _grace,
      });
      setState(() { _loading = false; _statusMsg = 'Grace নিয়ম সংরক্ষিত হয়েছে'; });
      _runReview();
    } catch (e) {
      setState(() { _loading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  Future<void> _execute() async {
    if (_classId == null || _eventId == null || _review.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Promotion নিশ্চিত করুন'),
        content: Text('${_promote.values.where((v) => v).length} জনকে SSC Batch এ উত্তীর্ণ করা হবে। '
            'পরীক্ষা event $_eventId) নিশ্চিত? ইতিমধ্যে দেয়া ফলাফল আবারও পাঠালে roll আপডেট হবে।'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('বাতিল')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('নিশ্চিত করুন')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() { _loading = true; _error = ''; });
    final students = <Map<String, dynamic>>[];
    for (final st in _review) {
      final id = (st['id'] as num).toInt();
      students.add({
        'id': id,
        'promote': _promote[id] == true,
        'decision': _promote[id] == true ? _decision[id] : 'retained',
        'final_gpa': st['final_gpa'],
        'note': _note[id] ?? '',
      });
    }
    try {
      final r = await Api.post('/promote/execute', {
        'class_id': _classId,
        'event_id': _eventId,
        'students': students,
      });
      setState(() {
        _loading = false;
        _statusMsg = '${r['promoted'] is List ? (r['promoted'] as List).length : 0} জন উত্তীর্ণ, '
            '${r['retained'] is List ? (r['retained'] as List).length : 0} জন খুঁজে পাইনি/রাখা হয়েছে';
      });
      final msgCtx = context;
      if (!msgCtx.mounted) return;
      ScaffoldMessenger.of(msgCtx)
          .showSnackBar(SnackBar(content: Text(_statusMsg)));
      if (mounted) _runReview();
    } catch (e) {
      setState(() { _loading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Class 10 → SSC Promotion')),
      body: _loading && _review.isEmpty && _classes.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(12), children: [
              if (_error.isNotEmpty)
                Card(color: Colors.red.shade50, child: Padding(padding: const EdgeInsets.all(10), child: Text(_error, style: TextStyle(color: Colors.red.shade800)))),
              if (_statusMsg.isNotEmpty)
                Card(color: Colors.green.shade50, child: Padding(padding: const EdgeInsets.all(10), child: Text(_statusMsg, style: TextStyle(color: Colors.green.shade800)))),
              _picker(
                label: 'শ্রেণি *',
                value: _classId,
                items: _classes.map((c) {
                  return (c['id'] as num).toInt();
                }).toList(),
                labels: _classes.map((c) {
                  final name = "${c['name']}${(c['group_name']?.toString() ?? '').isNotEmpty ? ' (${c['group_name']})' : (c['section']?.toString() ?? '')}";
                  return name;
                }).toList(),
                onChanged: (v) => setState(() => _classId = v),
              ),
              _picker(
                label: 'পরীক্ষা Event *',
                value: _eventId,
                items: _events.map((e) => (e['id'] as num).toInt()).toList(),
                labels: _events.map((e) => '${e['name'] ?? ''}').toList(),
                onChanged: (v) => setState(() => _eventId = v),
              ),
              const SizedBox(height: 8),
              Row(children: [
                const Text('Grace (যত subject fail পর্যন্ত pass দেবে): '),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _grace,
                  items: [for (var i = 0; i <= 11; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                  onChanged: (v) => setState(() => _grace = v ?? 0),
                ),
                const Spacer(),
                TextButton(onPressed: _saveGrace, child: const Text('Grace সেভ')),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: FilledButton(onPressed: _runReview, child: const Text('রিভিউ করুন'))),
                const SizedBox(width: 8),
                Expanded(child: FilledButton.icon(
                  onPressed: _reviewed && _review.isNotEmpty ? _execute : null,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Execute'),
                )),
              ]),
              if (_reviewed) ...[
                const SizedBox(height: 8),
                Text('মোট ${_review.length} জনের ফলাফল', style: const TextStyle(fontWeight: FontWeight.bold)),
                for (final st in _review)
                  _studentTile(st),
                const SizedBox(height: 80),
              ],
            ]),
    );
  }

  Widget _picker({
    required String label,
    required int? value,
    required List<int> items,
    required List<String> labels,
    required ValueChanged<int?> onChanged,
  }) {
    final pairs = <int, String>{};
    for (var i = 0; i < items.length; i++) {
      pairs[items[i]] = labels[i];
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<int>(
        initialValue: value,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: [for (final e in pairs.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
        onChanged: onChanged,
      ),
    );
  }

  Widget _studentTile(Map st) {
    final id = (st['id'] as num).toInt();
    final promote = _promote[id] == true;
    final failedSubjs = (st['failed_subjects'] as List?) ?? [];
    return Card(
      color: promote ? Colors.green.shade50 : Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${st['name']}  •  রোল ${st['roll']}', style: const TextStyle(fontWeight: FontWeight.w600))),
            Text('GPA ${(st['final_gpa'] as num).toStringAsFixed(2)}',
                style: TextStyle(color: promote ? Colors.green.shade800 : Colors.red.shade800, fontWeight: FontWeight.bold)),
          ]),
          Text('${st['result_status']}  •  অনুপস্থিত/ফেল subject: ${st['fail_count'] ?? 0}'
              '${failedSubjs.isEmpty ? '' : ' (${failedSubjs.join(', ')})'}',
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Row(children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('উত্তীর্ণ → SSC')),
                ButtonSegment(value: false, label: Text('রাখা হবে')),
              ],
              selected: {promote},
              onSelectionChanged: (s) => setState(() {
                _promote[id] = s.first;
                if (s.first) {
                  _decision[id] = (st['decision'] == 'grace_promoted' || st['decision'] == 'admin_override')
                      ? st['decision'].toString()
                      : 'promoted';
                }
              }),
            ),
            const Spacer(),
            PopupMenuButton<String>(
              tooltip: 'সিদ্ধান্ত mark',
              onSelected: (d) => setState(() { _decision[id] = d; }),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'promoted', child: Text('সাধারণ উত্তীর্ণ')),
                PopupMenuItem(value: 'grace_promoted', child: Text('Grace-এ উত্তীর্ণ')),
                PopupMenuItem(value: 'admin_override', child: Text('Admin override (যেকোনো যত fail) ')),
              ],
            ),
          ]),
          if (!promote)
            TextField(
              decoration: const InputDecoration(hintText: 'নোট (ঐচ্ছিক): উদাহরণ "বাবা-মায়ের সাথে পড়াশুনা"'),
              onChanged: (v) => setState(() => _note[id] = v),
            ),
        ]),
      ),
    );
  }
}