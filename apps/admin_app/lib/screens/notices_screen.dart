import 'package:flutter/material.dart';
import '../api.dart';

class NoticesScreen extends StatefulWidget {
  const NoticesScreen({super.key});
  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends State<NoticesScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  int? _classId;
  List _rows = [];
  bool _sending = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final r = await Api.get('/admin/notifications');
      setState(() => _rows = r);
    } catch (_) {}
  }

  Future<void> _send() async {
    if (_title.text.trim().isEmpty) return;
    setState(() { _sending = true; });
    try {
      await Api.post('/admin/notices', {
        'title': _title.text.trim(), 'body': _body.text.trim(), 'class_id': _classId,
      });
      _title.clear(); _body.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notice sent to guardian apps!')));
      _load();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
    setState(() { _sending = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notices')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: Card(child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title *', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: _body, maxLines: 2, decoration: const InputDecoration(labelText: 'Message', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: FutureBuilder<dynamic>(
                future: Api.get('/admin/classes'),
                builder: (_, snap) {
                  if (!snap.hasData) return const SizedBox();
                  return DropdownButtonFormField<int>(
                    value: _classId,
                    decoration: const InputDecoration(labelText: 'Target', border: OutlineInputBorder()),
                    items: [const DropdownMenuItem(value: null, child: Text('All guardians')),
                      ...snap.data!.map<DropdownMenuItem<int>>((c) =>
                          DropdownMenuItem(value: c['id'], child: Text('${c['name']} (${c['section']})'))).toList()],
                    onChanged: (v) => setState(() => _classId = v),
                  );
                })),
              const SizedBox(width: 10),
              FilledButton(onPressed: _sending ? null : _send, child: const Text('Send')),
            ]),
          ])))),
        Expanded(child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: _rows.length,
          itemBuilder: (_, i) {
            final n = _rows[i];
            return ListTile(
              leading: Icon(n['type'] == 'notice' ? Icons.campaign : Icons.notifications,
                  color: n['type'] == 'attendance' ? Colors.red : Colors.blue),
              title: Text(n['title'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text('${n['student_name'] ?? n['class_name'] ?? 'All'} • ${n['sender_name'] ?? '-'}',
                  style: const TextStyle(fontSize: 12)),
            );
          })),
      ]),
    );
  }
}