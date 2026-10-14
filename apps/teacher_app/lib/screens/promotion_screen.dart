import 'package:flutter/material.dart';
import '../api.dart';

class PromotionScreen extends StatefulWidget {
  const PromotionScreen({super.key});
  @override
  State<PromotionScreen> createState() => _PromotionScreenState();
}

class _PromotionScreenState extends State<PromotionScreen> {
  List<Map<String, dynamic>> _exams = [];
  List<Map<String, dynamic>> _review = [];
  int? _classId;
  int? _eventId;
  bool _loading = false;
  bool _loaded = false;
  String _error = '';
  int _grace = 0;
  String _eventName = '';

  @override
  void initState() {
    super.initState();
    _loadExams();
  }

  Future<void> _loadExams() async {
    if (_exams.isEmpty) setState(() { _loading = true; _error = ''; });
    try {
      await Api.loadCachedFirst('/teacher/exams', (data) {
        if (!mounted) return;
        final all = (data is List ? data : <dynamic>[]).cast<Map<String, dynamic>>();
        // Promotion sources: admin-created Annual (Class 6–9) + Test (Class 10)
        // events. Rows show "Test Exam 2025" (name + year); tap → subjects.
        final seen = <String>{};
        final picks = <Map<String, dynamic>>[];
        for (final e in all) {
          if (e['source'] != 'admin') {
            continue;
          }
          final kind = e['exam_kind']?.toString() ?? '';
          final cls = e['class_name']?.toString() ?? '';
          final cid = e['class_id'];
          final eid = e['event_id'];
          if (cid == null || eid == null) continue;
          final is10 = RegExp(r'class\s*10', caseSensitive: false).hasMatch(cls);
          final okKind = is10 ? kind == 'test' : kind == 'annual';
          if (!okKind) continue;
          final key = '$cid-$eid';
          final year = e['event_year']?.toString() ?? e['year']?.toString() ?? '';
          final label = '${e['name']?.toString() ?? 'পরীক্ষা'}${year.isNotEmpty ? ' $year' : ''}';
          if (seen.add(key)) picks.add({
            'class_id': cid, 'event_id': eid, 'name': label,
            'class_name': cls, 'exam_kind': kind,
          });
        }
        final firstLoad = _exams.isEmpty;
        setState(() {
          _exams = picks;
          _loading = false;
        });
        if (firstLoad && _exams.isNotEmpty) {
          _classId = _exams.first['class_id'] as int;
          _eventId = _exams.first['event_id'] as int;
          _loadReview();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  Future<void> _loadReview() async {
    if (_classId == null || _eventId == null) return;
    if (!_loaded) setState(() { _loading = true; _error = ''; });
    try {
      await Api.loadCachedFirst('/teacher/promotion/review?class_id=$_classId&event_id=$_eventId', (data) {
        if (!mounted || data is! Map) return;
        setState(() {
          _review = (data['review'] is List ? (data['review'] as List) : <dynamic>[]).cast<Map<String, dynamic>>();
          _grace = (data['grace_failed'] as num?)?.toInt() ?? 0;
          _eventName = data['event']?['name']?.toString() ?? 'পরীক্ষা';
          _loaded = true;
          _loading = false;
        });
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  Future<void> _saveGrace() async {
    if (_classId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Class-teacher grace control: shared rule with the admin engine.
      await Api.put('/teacher/promotion/grace-limit', {
        'class_id': _classId,
        'grace_failed': _grace,
      });
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          backgroundColor: Colors.green,
          content: Text('Grace limit $_grace সেভ হয়েছে — review আবার লোড হচ্ছে')));
      _loadReview();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  String _decisionLabel(Map<String, dynamic> s) {
    final executed = s['executed'];
    if (executed == null || executed == 'retained') {
      if (s['decision'] == 'promoted') return 'প্রস্তাবিত: উত্তীর্ণ';
      if (s['decision'] == 'grace_promoted') return 'প্রস্তাবিত: Grace-তে উত্তীর্ণ';
      return 'প্রস্তাবিত: রাখা হবে';
    }
    if (executed == 'promoted') return 'উত্তীর্ণ (SSC)';
    if (executed == 'grace_promoted') return 'Grace-এ উত্তীর্ণ (SSC)';
    if (executed == 'admin_override') return 'অ্যাডমিন সিদ্ধান্তে উত্তীর্ণ';
    return 'রাখা হয়েছে';
  }

  bool _isGreen(Map<String, dynamic> s) {
    final d = s['executed'] ?? s['decision'];
    return d == 'promoted' || d == 'grace_promoted' || d == 'admin_override';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Promotion — SSC ফলাফল')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty && !_loaded
              ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error)))
              : _exams.isEmpty && _error.isEmpty
                  ? const Center(child: Text('Class 10 পরীক্ষার কোনো প্রকাশিত event নেই'))
                  : Column(children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                        child: DropdownButtonFormField<int>(
                          initialValue: _eventId,
                          decoration: const InputDecoration(labelText: 'Class 10 পরীক্ষা Event', border: OutlineInputBorder(), isDense: true),
                          items: [
                            for (final e in _exams)
                              DropdownMenuItem<int>(
                                value: (e['event_id'] as num).toInt(),
                                child: Text('${e['name']} • ${e['class_name']}'),
                              ),
                          ],
                          onChanged: (v) {
                            final pick = _exams.firstWhere((e) => (e['event_id'] as num).toInt() == v);
                            setState(() {
                              _eventId = v;
                              _classId = (pick['class_id'] as num).toInt();
                            });
                            _loadReview();
                          },
                        ),
                      ),
                      if (_loaded)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                          child: Row(children: [
                            Expanded(child: Text('$_eventName — Grace: $_graceটি subject fail পর্যন্ত উত্তীর্ণ',
                                style: const TextStyle(fontSize: 12, color: Colors.grey))),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                              onPressed: () => _showGraceEditor(),
                              icon: const Icon(Icons.tune, size: 15),
                              label: const Text('Grace বদলান', style: TextStyle(fontSize: 12)),
                            ),
                          ]),
                        ),
                      Expanded(
                        child: _review.isEmpty && _loaded
                            ? const Center(child: Text('এই event-এ কোনো ফলাফল নেই'))
                            : ListView(
                                padding: const EdgeInsets.all(12),
                                children: [
                                  for (int i = 0; i < _review.length; i++) ...[
                                    if (i == 0 || _review[i]['decision'] != _review[i - 1]['decision'])
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8, bottom: 2),
                                        child: Text(
                                          switch (_review[i]['decision'].toString()) {
                                            'promoted' => 'উত্তীর্ণ (সব subject পাস)',
                                            'grace_promoted' => 'গ্রেস-এ উত্তীর্ণ',
                                            _ => 'রাখা হবে',
                                          },
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.deepPurple),
                                        ),
                                      ),
                                    _studentCard(_review[i]),
                                  ],
                                ],
                              ),
                      ),
                    ]),
    );
  }

  Future<void> _showGraceEditor() async {
    var val = _grace;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, setD) => AlertDialog(
        title: const Text('Grace Limit — কত বিষয়ে fail হলেও উত্তীর্ণ?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('0 = শুধু সব-pass; 1–11 = তত বিষয় fail পর্যন্ত শর্তসাপেক্ষে উত্তীর্ণ।',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(onPressed: val > 0 ? () => setD(() => val--) : null,
                icon: const Icon(Icons.remove_circle_outline)),
            Text('$val', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            IconButton(onPressed: val < 11 ? () => setD(() => val++) : null,
                icon: const Icon(Icons.add_circle_outline)),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('বাতিল')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      )),
    );
    if (ok == true) {
      setState(() => _grace = val);
      _saveGrace();
    }
  }

  Widget _studentCard(Map<String, dynamic> s) {
    final green = _isGreen(s);
    final fails = (s['failed_subjects'] is List ? (s['failed_subjects'] as List) : <dynamic>[]);
    final roll = s['promoted_roll'];
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: green ? Colors.green.shade50 : Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${s['name']} • রোল ${s['roll']}', style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('GPA ${(s['final_gpa'] as num).toStringAsFixed(2)} • ${s['result_status']}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            if (!green && fails.isNotEmpty)
              Text('ফেল: ${fails.join(', ')}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_decisionLabel(s),
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12,
                    color: green ? Colors.green.shade800 : Colors.orange.shade900)),
            if (roll != null)
              Text('নতুন SSC রোল: $roll',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green.shade800)),
          ]),
        ]),
      ),
    );
  }
}