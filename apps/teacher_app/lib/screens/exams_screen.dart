import 'package:flutter/material.dart';
import '../api.dart';
import 'exam_detail_screen.dart';
import 'create_exam_screen.dart';

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
  String _filter = 'all';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> reload() => _load();

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await Api.get('/teacher/exams');
      setState(() { _exams = r; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  List get _filtered {
    if (_filter == 'admin') return _exams.where((e) => e['source'] == 'admin').toList();
    if (_filter == 'mine') return _exams.where((e) => e['is_mine'] == 1).toList();
    return _exams;
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
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'all', label: Text('সব')),
                        ButtonSegment(value: 'admin', label: Text('Admin Exam')),
                        ButtonSegment(value: 'mine', label: Text('আমার Test')),
                      ],
                      selected: {_filter},
                      onSelectionChanged: (s) => setState(() => _filter = s.first),
                    )),
                  Expanded(child: _filtered.isEmpty
                    ? Center(child: Padding(padding: const EdgeInsets.all(24),
                        child: Text(_filter == 'admin'
                            ? 'কোনো admin exam নেই।\n\nপ্রশাসনিক (admin-created) exam শুধুমাত্র সেই class-এর designated Class Teacher-ই দেখতে ও মার্কস দিতে পারেন।'
                            : 'কোনো exam নেই।', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, height: 1.5))))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final e = _filtered[i];
                        return Card(
                          child: ListTile(
                            title: Row(children: [
                              Expanded(child: Text(e['name'])),
                              if (e['status'] == 'published')
                                const Chip(backgroundColor: Colors.green, label: Text('Published', style: TextStyle(color: Colors.white, fontSize: 10)))
                            ]),
                            subtitle: Text(
                                '${e['subject_name']} • ${e['class_name']} (${e['section']}) • ${e['exam_type'].toString().replaceAll('_', ' ')}'),
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
                                        final ok = await showDialog<bool>(
                                            context: context,
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
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Exam ডিলিট হয়েছে'))RI
                                            _load();
                                          } catch (ex) {
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                                content: Text('ডিলিট ব্যর্থ: ${ex.toString().replaceFirst('Exception: ', '')}')RI
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