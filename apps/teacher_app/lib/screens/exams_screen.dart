import 'package:flutter/material.dart';
import '../api.dart';
import 'exam_detail_screen.dart';
import 'create_exam_screen.dart';
import 'event_list_screen.dart';

class ExamsScreen extends StatefulWidget {
  final dynamic teacher;
  const ExamsScreen({super.key, required this.teacher});
  @override
  State<ExamsScreen> createState() => ExamsScreenState();
}

class ExamsScreenState extends State<ExamsScreen> {
  List _exams = [];
  bool _loading = true;
  String? _error;
  String _filter = 'mine-subj';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> reload() => _load();

  Future<void> _load() async {
    if (_exams.isEmpty) setState(() { _loading = true; _error = null; });
    try {
      await Api.loadCachedFirst('/teacher/exams', (r) {
        if (!mounted) return;
        setState(() { _exams = r is List ? r : []; _loading = false; });
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  List get _filtered {
    if (_filter == 'admin') return _exams.where((e) => e['source'] == 'admin').toList();
    if (_filter == 'mine') return _exams.where((e) => e['is_mine'] == 1).toList();
    // Default: only exams of MY assigned subjects (+ my own created tests).
    // Unassigned / previously-removed subjects never show up here.
    return _exams.where((e) => e['subject_mine'] == 1 || e['is_mine'] == 1).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Exams'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New Exam'),
        onPressed: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => CreateExamScreen(teacher: widget.teacher)));
          _load();
        },
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  FilledButton.tonal(onPressed: _load, child: const Text('আবার চেষ্টা করুন')),
                ]))
              : Column(children: [
                  Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 0), child: Card(
                    color: Colors.indigo.shade50,
                    child: ListTile(
                      leading: const Icon(Icons.assessment_outlined, color: Colors.indigo),
                      title: const Text('Exam Events & Results', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Published সহ সব event • coverage • seat/admit PDF', style: TextStyle(fontSize: 12)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => EventListScreen(teacher: widget.teacher))),
                    ),
                  )),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'mine-subj', label: Text('আমার Subject')),
                        ButtonSegment(value: 'admin', label: Text('Admin Exam')),
                        ButtonSegment(value: 'mine', label: Text('আমার Test')),
                      ],
                      selected: {_filter},
                      onSelectionChanged: (s) => setState(() => _filter = s.first),
                    )),
                  Expanded(child: _filtered.isEmpty
                    ? Center(child: Padding(padding: const EdgeInsets.all(24),
                        child: Text(_filter == 'admin'
                            ? 'কোনো admin exam নেই।\n\nপ্রশাসনিক (admin-created) exam সেই class-এর Class Teacher এবং assigned subject teacher-রা দেখতে ও মার্কস দিতে পারেন।'
                            : 'কোনো exam নেই।', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, height: 1.5))))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final e = _filtered[i];
                          final open = (e['entry_open'] as num?)?.toInt() ?? 1;
                          final isPub = e['status'] == 'published';
                          final dead = e['entry_deadline']?.toString();
                          final closed = isPub || open == 0;
                        return Card(
                          child: ListTile(
                            title: Row(children: [
                              Expanded(child: Text(e['name'])),
                              if (isPub)
                                const Chip(backgroundColor: Colors.green, label: Text('Published', style: TextStyle(color: Colors.white, fontSize: 10)))
                              else if (open == 0)
                                const Chip(backgroundColor: Colors.red, label: Text('Entry বন্ধ', style: TextStyle(color: Colors.white, fontSize: 10))),
                            ]),
                            subtitle: Text(
                                '${e['subject_name']} • ${e['class_name']} (${e['section']}) • ${e['exam_type'].toString().replaceAll('_', ' ')}'
                                '${(!isPub && dead != null && dead.isNotEmpty && dead != 'null') ? '\n⏰ Deadline: ${dead.toString().replaceAll('T', ' ').substring(0, 16)} পর্যন্ত' : ''}'),
                            trailing: e['source'] == 'teacher'
                                ? PopupMenuButton<String>(
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(
                                          value: 'delete',
                                          child: Row(children: [
                                            Icon(Icons.delete_outline, color: Colors.red),
                                            SizedBox(width: 8),
                                            Text('Delete')
                                          ]))
                                    ],
                                    onSelected: (v) async {
                                      if (v == 'delete') {
                                            final dialogCtx = context;
                                            final ok = await showDialog<bool>(
                                                context: dialogCtx,
                                                builder: (c) => AlertDialog(
                                                  title: const Text('Exam ডিলিট করবেন?'),
                                                  content: Text('"${e['name']}" মুছে ফেলা হবে — undo করা যাবে না।'),
                                                  actions: [
                                                    TextButton(
                                                        onPressed: () => Navigator.pop(c, false),
                                                        child: const Text('বাতিল')),
                                                    FilledButton(
                                                        style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                                        onPressed: () => Navigator.pop(c, true),
                                                        child: const Text('ডিলিট')),
                                                  ],
                                                ));
                                            if (ok == true) {
                                              try {
                                                await Api.delete('/teacher/exams/${e['id']}');
                                                if (!context.mounted) return;
                                                ScaffoldMessenger.of(dialogCtx).showSnackBar(
                                                    const SnackBar(content: Text('Exam ডিলিট হয়েছে')));
                                                _load();
                                              } catch (ex) {
                                                if (!context.mounted) return;
                                                ScaffoldMessenger.of(dialogCtx).showSnackBar(SnackBar(
                                                    content: Text('ডিলিট ব্যর্থ: ${ex.toString().replaceFirst('Exception: ', '')}')));
                                              }
                                            }
                                      }
                                    },
                                  )
                                : const SizedBox.shrink(),
                            onTap: () async {
                              await Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => ExamDetailScreen(examId: e['id'], examName: e['name'])));
                              _load();
                            },
                          ),
                        );
                      },
                    )),
                ]),
    );
  }
}