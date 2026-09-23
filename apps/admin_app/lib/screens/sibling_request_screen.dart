import 'package:flutter/material.dart';
import '../api.dart';

class SiblingRequestScreen extends StatefulWidget {
  const SiblingRequestScreen({super.key});
  @override
  State<SiblingRequestScreen> createState() => _SiblingRequestScreenState();
}

class _SiblingRequestScreenState extends State<SiblingRequestScreen> {
  int _tab = 0; // 0=pending, 1=approved, 2=rejected
  final _tabs = const ['Pending', 'Approved', 'Rejected'];
  List _rows = [];
  bool _loading = true;
  String? _error;
  String? _msg;
  final _rejectText = TextEditingController();

  static const _statusKeys = ['pending', 'approved', 'rejected'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await Api.get('/admin/sibling-requests?status=${_statusKeys[_tab]}');
      setState(() { _rows = r is List ? r : []; _loading = false; });
    } catch (e) {
      setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _act(Map row, String action) async {
    try {
      await Api.post('/admin/sibling-requests/${row['id']}/$action',
          action == 'reject' ? {'remark': _rejectText.text.trim().isEmpty ? 'Request rejected' : _rejectText.text.trim()} : {});
      if (!mounted) return;
      setState(() => _msg = action == 'approve' ? 'অনুমোদিত হয়েছে — guardian-এর app-এ sibling এখন দেখা যাবে' : 'বাতিল করা হয়েছে');
      _rejectText.clear();
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sibling Requests')),
      body: Column(children: [
        if (_error != null)
          Container(width: double.infinity, color: Colors.red.shade100,
              padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        if (_msg != null)
          Container(width: double.infinity, color: Colors.green.shade100,
              padding: const EdgeInsets.all(8),
              child: Text(_msg!, style: TextStyle(color: Colors.green.shade900))),
        Padding(padding: const EdgeInsets.all(10),
          child: SegmentedButton<int>(
            segments: _tabs.map((t) => ButtonSegment(value: _tabs.indexOf(t), label: Text(t))).toList(),
            selected: {_tab},
            onSelectionChanged: (s) => setState(() { _tab = s.first; _msg = null; _error = null; _load(); }),
          )),
        Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _rows.isEmpty
                ? const Center(child: Text('কোনো request নেই'))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _rows.length,
                    itemBuilder: (_, i) => _card(_rows[i]))),
      ]),
    );
  }

  Widget _card(Map r) {
    final pending = r['status'] == 'pending';
    return Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        CircleAvatar(backgroundColor: Colors.teal.shade100,
            child: Text((r['student_name']?.toString() ?? '?')[0])),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r['student_name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('${r['class_name'] ?? ''} (${r['section'] ?? ''}) • Roll ${r['roll'] ?? ''} • ${r['student_code'] ?? ''}'),
        ])),
      ]),
      const Divider(height: 16),
      Text('Guardian: ${r['guardian_name'] ?? ''} (${r['guardian_phone'] ?? ''})'),
      if (r['requester_name'] != null)
        Text('আবেদনকারী: ${r['requester_name']} (roll ${r['requester_roll']})'),
      Text('DOB: ${(r['dob']?.toString() ?? '').length >= 10 ? r['dob'].toString().substring(0, 10) : '-'}'),
      if (pending) ...[
        const SizedBox(height: 10),
        Row(children: [
          Expanded(flex: 2, child: TextField(
            controller: _rejectText,
            decoration: const InputDecoration(labelText: 'Reject reason (optional)', isDense: true, border: OutlineInputBorder()),
          )),
          const SizedBox(width: 8),
          FilledButton(onPressed: () => _act(r, 'approve'), child: const Text('Approve')),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: () => _act(r, 'reject'), child: const Text('Reject')),
        ]),
      ] else
        Text('Result: ${r['status']}${(r['remark'] ?? '') != '' ? ' — ${r['remark']}' : ''}',
            style: TextStyle(color: r['status'] == 'approved' ? Colors.green : Colors.red)),
    ])));
  }
}