import 'package:flutter/material.dart';

import '../api.dart';

class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  List _pending = const [];
  List _reentryRequests = const [];
  List _profileRequests = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final responses = await Future.wait([
        Api.get('/admin/approvals/pending'),
        Api.get('/admin/mark-edit-requests?status=pending'),
        Api.get('/admin/student-profile-edit-requests?status=pending'),
      ]);
      if (!mounted) return;
      final exams = responses[0] as Map;
      setState(() {
        _pending = (exams['pending'] as List?) ?? const [];
        _reentryRequests = responses[1] as List? ?? const [];
        _profileRequests = responses[2] as List? ?? const [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _reviewProfile(int id, String status) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          status == 'resolved' ? 'সংশোধন সম্পন্ন?' : 'অনুরোধ প্রত্যাখ্যান?',
        ),
        content: TextField(
          controller: note,
          decoration: const InputDecoration(
            labelText: 'নোট / কী সংশোধন করা হয়েছে',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('সংরক্ষণ'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.post('/admin/student-profile-edit-requests/$id/review', {
        'status': status,
        'note': note.text.trim(),
      });
      _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _profileQueue() => _profileRequests.isEmpty
      ? const Center(child: Text('কোনো pending profile request নেই'))
      : ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _profileRequests.length,
          itemBuilder: (_, i) {
            final r = _profileRequests[i];
            final id = int.tryParse('${r['id']}');
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${r['student_name']} · Roll ${r['roll']} · ${r['class_name']} ${r['section'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'অভিভাবক: ${r['guardian_name'] ?? '—'} · ${r['guardian_phone'] ?? '—'}',
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('কারণ: ${r['reason']}'),
                    ),
                    if (r['proposed_changes'] != null)
                      Text('প্রস্তাবিত তথ্য: ${r['proposed_changes']}'),
                    const Text(
                      'শিক্ষার্থীর রেকর্ডে হাতে সংশোধন করার পরই Resolved করুন।',
                      style: TextStyle(color: Colors.blueGrey),
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: id == null
                              ? null
                              : () => _reviewProfile(id, 'rejected'),
                          child: const Text('Reject'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: id == null
                              ? null
                              : () => _reviewProfile(id, 'resolved'),
                          child: const Text('Resolved'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );

  Future<void> _act(int examId, String action, {String? reason}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = action == 'approve'
          ? '/admin/exams/$examId/approve'
          : '/admin/exams/$examId/reject';
      await Api.post(path, {'reason': reason});
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: action == 'approve' ? Colors.green : Colors.orange,
          content: Text(action == 'approve' ? 'Approved' : 'Rejected'),
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _reject(int examId) async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject করবেন?'),
        content: TextField(
          controller: ctl,
          decoration: const InputDecoration(
            hintText: 'কারণ',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final reason = ctl.text.trim();
      if (reason.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reject করার কারণ লিখুন।')),
        );
        return;
      }
      _act(examId, 'reject', reason: reason);
    }
  }

  Future<void> _actReentry(int requestId, String action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Api.post('/admin/mark-edit-requests/$requestId/$action', {});
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: action == 'approve' ? Colors.green : Colors.orange,
          content: Text(
            action == 'approve'
                ? 'Re-entry অনুমোদিত — teacher submit না করা পর্যন্ত edit করতে পারবেন।'
                : 'Re-entry request বাতিল করা হয়েছে।',
          ),
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Widget _examApprovals() {
    if (_pending.isEmpty) {
      return const Center(child: Text('কোনো pending exam approval নেই'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _pending.length,
      itemBuilder: (_, i) {
        final p = _pending[i];
        return Card(
          child: ListTile(
            title: Text(
              '${p['subject_name']} — ${p['class_name']} ${p['class_section'] ?? ''}',
            ),
            subtitle: Text(
              '${p['event_name'] ?? ''} • submitted by ${p['submitted_by_name'] ?? '—'}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check, color: Colors.green),
                  tooltip: 'Approve',
                  onPressed: () => _act(p['id'] as int, 'approve'),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  tooltip: 'Reject',
                  onPressed: () => _reject(p['id'] as int),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _reentryQueue() {
    if (_reentryRequests.isEmpty) {
      return const Center(child: Text('কোনো pending re-entry আবেদন নেই'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _reentryRequests.length,
      itemBuilder: (_, i) {
        final request = _reentryRequests[i];
        final id = int.tryParse('${request['id']}');
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${request['teacher_name'] ?? 'Teacher'} — ${request['subject_name'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  '${request['exam_name'] ?? ''} • ${request['class_name'] ?? ''} '
                  '${request['section'] ?? ''} • ${request['student_name'] ?? ''}',
                  style: TextStyle(
                    color: Colors.blueGrey.shade700,
                    fontSize: 13,
                  ),
                ),
                if ('${request['reason'] ?? ''}'.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('কারণ: ${request['reason']}'),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: id == null
                            ? null
                            : () => _actReentry(id, 'reject'),
                        child: const Text('Reject'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: id == null
                            ? null
                            : () => _actReentry(id, 'approve'),
                        icon: const Icon(Icons.lock_open_rounded),
                        label: const Text('Re-entry approve'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Exam Approvals'),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Exam approvals'),
              Tab(text: 'Re-entry requests'),
              Tab(text: 'Profile requests'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text(_error!))
            : TabBarView(
                children: [_examApprovals(), _reentryQueue(), _profileQueue()],
              ),
      ),
    );
  }
}
