import 'package:flutter/material.dart';
import '../api.dart';

class ExamDetailScreen extends StatefulWidget {
  final int examId;
  final String examName;
  const ExamDetailScreen({super.key, required this.examId, required this.examName});
  @override
  State<ExamDetailScreen> createState() => _ExamDetailScreenState();
}

class _ExamDetailScreenState extends State<ExamDetailScreen> {
  Map? _data;
  bool _loading = true;
  bool _published = false;
  String? _error;
  late Map<int, TextEditingController> _controllers;
  late Map<int, TextEditingController> _commentControllers;
  Set<int> _lockedIds = {};

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await Api.get('/teacher/exams/${widget.examId}');
      _controllers = {};
      _commentControllers = {};
      _lockedIds = {};
      _published = r['exam']['status'] == 'published';
      for (final m in (r['marks'] as List)) {
        _controllers[m['student_id']] = TextEditingController(text: m['marks'].toString());
        _commentControllers[m['student_id']] = TextEditingController(text: (m['comment'] ?? '').toString());
        if (m['editable'] == 0 || m['editable'] == false) _lockedIds.add(m['student_id']);
      }
      for (final s in (r['students'] as List)) {
        _controllers.putIfAbsent(s['id'], () => TextEditingController());
      }
      setState(() { _data = r; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _saveMarks() async {
    final messenger = ScaffoldMessenger.of(context);
    final records = <Map<String, dynamic>>[];
    final defaultTotal = num.tryParse('${(_data?['exam'] ?? {})['full_marks'] ?? ''}') ?? 100;
    for (final s in (_data!['students'] as List)) {
      final c = _controllers[s['id']];
      if (c == null || c.text.trim().isEmpty) continue;
      records.add({
        'student_id': s['id'],
        'marks': num.tryParse(c.text.trim()) ?? 0,
        'total': defaultTotal.toDouble(),
        'comment': _commentControllers[s['id']]?.text.trim() ?? '',
      });
    }
    if (records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('কোনো marks দেওয়া হয়নি')));
      return;
    }
    try {
      final r = await Api.post('/teacher/exams/${widget.examId}/marks', {'records': records});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.teal,
          content: Text(r['message'] ?? 'Saved')));
      _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

    Future<void> _notify() async {
    final messenger = ScaffoldMessenger.of(context);
    final students = (_data?['students'] as List?) ?? const [];
    final ids = students.map((s) => s['id']).toList();
    if (ids.isEmpty) return;
    try {
      final r = await Api.post('/teacher/notify', {
        'student_ids': ids,
        'title': 'ผลสอบ published',
        'body': '${widget.examName} - result Published',
      });
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          backgroundColor: Colors.green,
          content: Text('${r['notified']} জন student-এর guardian-কে জানানো হয়েছে')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _publish() async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Publish Result?'),
        content: const Text('Publish করলে guardian-রা notification পাবে এবং আর edit করা যাবে না।'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Publish')),
        ],
      ));
    if (ok != true) return;
    try {
      final r = await Api.post('/teacher/exams/${widget.examId}/publish');
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          backgroundColor: Colors.green,
          content: Text('${r['notified']} জন student-এর guardian-কে জানানো হয়েছে')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.examName),
        actions: [
          if (_published)
            const Padding(padding: EdgeInsets.only(right: 12),
                child: Center(child: Chip(backgroundColor: Colors.green, label: Text('Published', style: TextStyle(color: Colors.white, fontSize: 12)))))
          else
            Padding(padding: const EdgeInsets.only(right: 8),
                child: TextButton.icon(icon: const Icon(Icons.publish, size: 18), label: const Text('Publish'), onPressed: _publish)),
        ],
      ),
      floatingActionButton: (_loading || _published) ? null : FloatingActionButton.extended(
        icon: const Icon(Icons.save),
        label: const Text('Save Marks'),
        onPressed: _saveMarks,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Column(children: [
                  Padding(padding: const EdgeInsets.all(12),
                      child: Card(color: Colors.amber.shade50, child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          const Icon(Icons.timer, color: Colors.amber),
                          const SizedBox(width: 8),
                          Expanded(child: Text(
                              'Marks সেভ করার পর ১০ মিনিট edit করা যাবে। এরপর admin permission লাগবে।',
                              style: TextStyle(fontSize: 13, color: Colors.brown.shade700))),
                        ]),
                      ))),
                  Expanded(child: ListView.builder(
                    padding: const EdgeInsets.only(left: 12, right: 12, bottom: 90),
                    itemCount: (_data!['students'] as List).length,
                    itemBuilder: (_, i) {
                      final s = _data!['students'][i];
                      final locked = _published || _lockedIds.contains(s['id']);
                      return Card(child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          const SizedBox(width: 8),
                          CircleAvatar(child: Text('${s['roll']}')),
                          const SizedBox(width: 8),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s['name']),
                            if (locked)
                              const Text('🔒 Locked', style: TextStyle(color: Colors.red, fontSize: 11))
                            else
                              TextField(
                                controller: _commentControllers[s['id']],
                                enabled: !locked,
                                decoration: const InputDecoration(hintText: 'Comment (optional)', isDense: true, border: InputBorder.none, labelStyle: TextStyle(fontSize: 11)),
                                style: const TextStyle(fontSize: 12),
                              ),
                          ])),
                          SizedBox(width: 80, child: TextField(
                            controller: _controllers[s['id']],
                            enabled: !locked,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            decoration: const InputDecoration(hintText: 'Marks', border: OutlineInputBorder()),
                          )),
                          const SizedBox(width: 8),
                        ]),
                      ));
                    },
                  )),
                  SafeArea(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.notifications_active),
                      label: const Text('Result Notification → Guardians'),
                      onPressed: _notify,
                    ))),
                ]),
    );
  }
}