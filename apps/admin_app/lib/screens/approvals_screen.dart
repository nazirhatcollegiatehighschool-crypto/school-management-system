import 'package:flutter/material.dart';
import '../api.dart';

/// Exam approval queue (Q3). Class teachers approve their own class's
/// subject-exams; the admin MONITORS that queue and can override (approve
/// or reject) anything, then publishes the event when every subject of
/// every class is approved.
class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});
  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  List _pending = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await Api.get('/admin/approvals/pending');
      if (!mounted) return;
      setState(() { _pending = (r['pending'] as List?) ?? const []; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _act(int examId, String action, {String? reason}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = action == 'approve' ? '/admin/exams/$examId/approve' : '/admin/exams/$examId/reject';
      await Api.post(path, {'reason': reason});
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        backgroundColor: action == 'approve' ? Colors.green : Colors.orange,
        content: Text(action == 'approve' ? 'Approved' : 'Rejected')));
      _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(backgroundColor: Colors.red,
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _reject(int examId) async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Reject করবেন?'),
      content: TextField(controller: ctl, decoration: const InputDecoration(hintText: 'কারণ', border: OutlineInputBorder())),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('বাতিল')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reject')),
      ]));
    if (ok == true) _act(examId, 'reject', reason: ctl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exam Approvals'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _pending.isEmpty
                  ? const Center(child: Text('কোনো pending approval নেই 🎉'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _pending.length,
                      itemBuilder: (_, i) {
                        final p = _pending[i];
                        return Card(child: ListTile(
                          title: Text('${p['subject_name']} — ${p['class_name']} ${p['class_section'] ?? ''}'),
                          subtitle: Text('${p['event_name'] ?? ''} • submitted by ${p['submitted_by_name'] ?? '—'}'),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(icon: const Icon(Icons.check, color: Colors.green),
                                tooltip: 'Approve', onPressed: () => _act(p['id'], 'approve')),
                            IconButton(icon: const Icon(Icons.close, color: Colors.red),
                                tooltip: 'Reject', onPressed: () => _reject(p['id'])),
                          ]),
                        ));
                      }),
    );
  }
}
