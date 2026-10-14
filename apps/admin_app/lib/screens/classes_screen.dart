import 'package:flutter/material.dart';
import '../api.dart';

class ClassesScreen extends StatefulWidget {
  const ClassesScreen({super.key});
  @override
  State<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends State<ClassesScreen> {
  List _rows = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; });
    try {
      final r = await Api.get('/admin/classes');
      setState(() { _rows = r; _loading = false; });
    } catch (e) {
      setState(() { _loading = false; });
    }
  }

  void _showForm([dynamic c]) {
    final name = TextEditingController(text: c?['name'] ?? '');
    final section = TextEditingController(text: c?['section'] ?? '');
    int? teacherId = c?['teacher_id'];

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      builder: (_) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(c == null ? 'Add Class' : 'Edit Class', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Class Name *', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: section, decoration: const InputDecoration(labelText: 'Section/Group *', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          FutureBuilder<dynamic>(
            future: Api.get('/admin/teachers'),
            builder: (_, snap) {
              if (!snap.hasData) return const SizedBox();
              return DropdownButtonFormField<int>(
                initialValue: teacherId,
                decoration: const InputDecoration(labelText: 'Class Teacher (attendance + marksheet)', border: OutlineInputBorder()),
                items: [const DropdownMenuItem(value: null, child: Text('— None —')),
                  ...snap.data!.map<DropdownMenuItem<int>>((t) =>
                      DropdownMenuItem(value: t['id'], child: Text(t['name']))).toList()],
                onChanged: (v) => teacherId = v,
              );
            },
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: () async {
            try {
              final body = {'name': name.text.trim(), 'section': section.text.trim(), 'teacher_id': teacherId};
              if (c == null) {
                await Api.post('/admin/classes', body);
              } else {
                await Api.put('/admin/classes/${c['id']}', body);
              }
              if (!mounted) return;
              Navigator.pop(context);
              _load();
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  backgroundColor: Colors.red,
                  content: Text(e.toString().replaceFirst('Exception: ', ''))));
            }
          }, child: const Text('Save')),
        ]))),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Classes & Subjects')),
      floatingActionButton: FloatingActionButton(onPressed: () => _showForm(), child: const Icon(Icons.add)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _rows.length,
                itemBuilder: (_, i) {
                  final c = _rows[i];
                  return Card(child: ListTile(
                    title: Text('${c['name']} (${c['section']})'),
                    subtitle: Text('Class Teacher: ${c['teacher_name'] ?? 'Not assigned'} • ${c['student_count']} students'),
                    trailing: IconButton(icon: const Icon(Icons.edit), onPressed: () => _showForm(c)),
                  ));
                })));
  }
}

