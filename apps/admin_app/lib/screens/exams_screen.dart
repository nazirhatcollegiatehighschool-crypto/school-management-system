import 'package:flutter/material.dart';
import '../api.dart';

class ExamsScreen extends StatefulWidget {
  const ExamsScreen({super.key});
  @override
  State<ExamsScreen> createState() => _ExamsScreenState();
}

class _ExamsScreenState extends State<ExamsScreen> {
  List _rows = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; });
    try {
      final r = await Api.get('/admin/exams');
      setState(() { _rows = r; _loading = false; });
    } catch (e) {
      setState(() { _loading = false; });
    }
  }

void _showCreate() {
    final name = TextEditingController();
    String type = 'class_test';
    int? classId;
    int? subjectId;
    String? clsName;
    String? sec;

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      builder: (_) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Create Exam', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Exam Name *', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: type,
            decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'class_test', child: Text('Class Test')),
              DropdownMenuItem(value: 'midterm', child: Text('Midterm')),
              DropdownMenuItem(value: 'final', child: Text('Final')),
            ],
            onChanged: (v) => type = v!,
          ),
          const SizedBox(height: 10),
          StatefulBuilder(builder: (_, setSheet) {
            return Column(children: [
              FutureBuilder<dynamic>(
                future: Api.get('/admin/classes'),
                builder: (_, snap) {
                  if (!snap.hasData) return const SizedBox();
                  final all = snap.data! as List;
                  final classNames = all.map((c) => '${c['name']}').toSet().toList();
                  final rows = all.where((c) => c['name'] == clsName).toList();
                  final isGroup = rows.any((c) => (c['group_name']?.toString() ?? '').isNotEmpty);
                  final secOpts = isGroup
                      ? rows.map((c) => c['group_name'].toString()).where((v) => v.isNotEmpty).toSet().toList()
                      : rows.map((c) => c['section'].toString()).toSet().toList();
                  return Column(children: [
                    DropdownButtonFormField<String?>(
                      value: clsName,
                      decoration: const InputDecoration(labelText: 'Step 1 — Class *', border: OutlineInputBorder()),
                      items: [for (final n in classNames) DropdownMenuItem(value: n, child: Text(n))],
                      onChanged: (v) => setSheet(() { clsName = v; sec = null; classId = null; subjectId = null; }),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String?>(
                      value: sec,
                      decoration: InputDecoration(labelText: isGroup ? 'Step 2 — Group *' : 'Step 2 — Section *', border: const OutlineInputBorder()),
                      items: [for (final s in secOpts) DropdownMenuItem(value: s, child: Text(s))],
                      onChanged: (v) {
                        setSheet(() {
                          sec = v;
                          subjectId = null;
                          classId = rows.isNotEmpty
                              ? rows.firstWhere((c) => (isGroup ? c['group_name'] : c['section']).toString() == v)['id'] as int
                              : null;
                        });
                      },
                    ),
                  ]);
                }),
              const SizedBox(height: 10),
              if (classId != null)
                FutureBuilder<dynamic>(
                  future: Api.get('/admin/subjects'),
                  builder: (_, snap) {
                    if (!snap.hasData) return const SizedBox();
                    final subs = snap.data!.where((s) => s['class_id'] == classId).toList();
                    return DropdownButtonFormField<int>(
                      value: subjectId,
                      decoration: const InputDecoration(labelText: 'Subject *', border: OutlineInputBorder()),
                      items: subs.map<DropdownMenuItem<int>>((s) =>
                          DropdownMenuItem(value: s['id'] as int, child: Text(s['name']?.toString() ?? ''))).toList(),
                      onChanged: (v) => setSheet(() => subjectId = v),
                    );
                  }),
            ]);
          }),
          const SizedBox(height: 16),
          FilledButton(onPressed: () async {
            try {
              await Api.post('/admin/exams', {
                'name': name.text.trim(), 'exam_type': type,
                'class_id': classId, 'subject_id': subjectId,
              });
              if (!mounted) return;
              Navigator.pop(context);
              _load();
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  backgroundColor: Colors.red,
                  content: Text(e.toString().replaceFirst('Exception: ', ''))));
            }
          }, child: const Text('Create')),
        ]))),
      );
  }

  void _viewMarks(int examId, String examName) async {
    try {
      final marks = await Api.get('/admin/exams/$examId/marks');
      if (!mounted) return;
      showModalBottomSheet(
        context: context, isScrollControlled: true,
        builder: (_) => DraggableScrollableSheet(
          initialChildSize: 0.7, maxChildSize: 0.95,
          builder: (_, scroll) => Container(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Text(examName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const Text('Locked mark "Unlock" করলে teacher আবার ১০ মিনিট edit পাবে',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              Expanded(child: ListView(controller: scroll, children: [
                for (final m in marks)
                  ListTile(
                    leading: CircleAvatar(child: Text('${m['roll']}')),
                    title: Text(m['student_name']),
                    subtitle: Text('${m['marks']}/${m['total']}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text((m['editable'] == 1 || m['editable'] == true) ? 'Editable' : '🔒 Locked',
                          style: TextStyle(fontSize: 11,
                              color: (m['editable'] == 1 || m['editable'] == true) ? Colors.green : Colors.red)),
                      const SizedBox(width: 6),
                      if (!(m['editable'] == 1 || m['editable'] == true))
                        TextButton(onPressed: () async {
                          await Api.put('/admin/marks/${m['id']}/unlock');
                          Navigator.pop(context);
                          _viewMarks(examId, examName);
                        }, child: const Text('Unlock')),
                    ]),
                  ),
                if (marks.isEmpty) const Center(child: Text('No marks yet')),
              ])),
            ])),
          ));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

void _setStatus(int id, String status) async {
    try {
      await Api.post('/admin/exams/$id/${status == 'published' ? 'publish-admin' : 'unpublish'}');
      if (!mounted) return;
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  void _share(int examId, String examName) async {
    final teacherSel = ValueNotifier<String?>(null);
    List? teachers;
    List shares = [];
    try {
      final r = await Api.get('/admin/exams/$examId/shares');
      shares = r is List ? r : [];
    } catch (_) {}
    try {
      final r = await Api.get('/admin/teachers');
      teachers = r is List ? r : [];
    } catch (_) {}
    if (!mounted) return;
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      builder: (ctx) => ValueListenableBuilder<String?>(
        valueListenable: teacherSel,
        builder: (_, sel, _) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Padding(padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Share Exam — $examName', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              StatefulBuilder(builder: (_, setSheet) {
                return DropdownButtonFormField<String>(
                  value: sel,
                  decoration: const InputDecoration(labelText: 'Teacher', border: OutlineInputBorder()),
                  items: [for (final t in teachers ?? []) DropdownMenuItem(value: '${t['id']}', child: Text(t['name']?.toString() ?? ''))],
                  onChanged: (v) => teacherSel.value = v,
                );
              }),
              const SizedBox(height: 10),
              FilledButton(onPressed: sel == null ? null : () async {
                try {
                  await Api.post('/admin/exams/$examId/shares', {'teacher_id': int.tryParse(sel) ?? 0});
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  _share(examId, examName);
                } catch (e) {
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
                }
              }, child: const Text('Share')),
              const SizedBox(height: 10),
              const Text('Shared with:', style: TextStyle(fontWeight: FontWeight.bold)),
              for (final s in shares)
                ListTile(
                  dense: true,
                  title: Text(s['teacher_name']?.toString() ?? ''),
                  trailing: TextButton(
                    onPressed: () async {
                      await Api.delete('/admin/exams/$examId/shares/${s['teacher_id']}');
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      _share(examId, examName);
                    },
                    child: const Text('Remove', style: TextStyle(color: Colors.red))),
                ),
              if (shares.isEmpty) const Text('কোনো teacher-কে share করা নেই', style: TextStyle(color: Colors.grey)),
            ])),
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exams & Marks')),
      floatingActionButton: FloatingActionButton(onPressed: _showCreate, child: const Icon(Icons.add)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _rows.length,
                itemBuilder: (_, i) {
                  final e = _rows[i];
                  final published = e['status'] == 'published';
                  return Card(child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: ListTile(
                      title: Row(children: [
                        Expanded(child: Text(e['name'],
                            style: TextStyle(fontWeight: FontWeight.w600,
                                color: published ? Colors.green.shade800 : null))),
                        if (published)
                          const Padding(padding: EdgeInsets.only(left: 6),
                              child: Text('● Published', style: TextStyle(fontSize: 10, color: Colors.green))),
                      ]),
                      subtitle: Text('${e['subject_name']} • ${e['class_name']} (${e['section']}) • by ${e['created_by_name']}'),
                      trailing: Wrap(spacing: 2, children: [
                        IconButton(icon: const Icon(Icons.ios_share), tooltip: 'Share',
                            onPressed: () => _share(e['id'], e['name'])),
                        IconButton(
                            icon: Icon(published ? Icons.visibility_off : Icons.check_circle_outline,
                                color: published ? Colors.orange : Colors.green),
                            tooltip: published ? 'Unpublish' : 'Publish',
                            onPressed: () => _setStatus(e['id'], published ? 'unpublished' : 'published')),
                        const Icon(Icons.chevron_right),
                      ]),
                      onTap: () => _viewMarks(e['id'], e['name']),
                    ),
                  ));
                })));
  }
}

