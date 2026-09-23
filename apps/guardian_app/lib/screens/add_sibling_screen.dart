import 'package:flutter/material.dart';
import '../api.dart';

class AddSiblingScreen extends StatefulWidget {
  const AddSiblingScreen({super.key});
  @override
  State<AddSiblingScreen> createState() => _AddSiblingScreenState();
}

class _AddSiblingScreenState extends State<AddSiblingScreen> {
  final _code = TextEditingController();
  final _dob = TextEditingController();
  final _className = TextEditingController();
  final _section = TextEditingController();
  final _roll = TextEditingController();
  final _phone = TextEditingController();
  final _relation = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _success;
  List? _requests;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    try {
      final r = await Api.get('/guardian/sibling-requests');
      if (mounted) setState(() => _requests = r is List ? r : []);
    } catch (_) {}
  }

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; _success = null; });
    try {
      final r = await Api.post('/guardian/sibling-request', {
        'student_code': _code.text.trim(),
        'dob': _dob.text.trim(),
        'class_name': _className.text.trim(),
        'section': _section.text.trim(),
        'roll': num.tryParse(_roll.text.trim()) ?? 0,
        'phone': _phone.text.trim(),
        'relation': _relation.text.trim().isEmpty ? 'sibling' : _relation.text.trim(),
      });
      setState(() { _success = r['message'] ?? 'সফলভাবে জমা হয়েছে'; });
      _loadRequests();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'approved': return 'অনুমোদিত';
      case 'pending': return 'অপেক্ষমাণ (অ্যাডমিন অনুমোদন)';
      case 'rejected': return 'বাতিল';
      default: return s;
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'approved': return Colors.green;
      case 'pending': return Colors.orange;
      case 'rejected': return Colors.red;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('সন্তান যোগ করুন (Sibling)')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('আগে থেকেই আপনার account-এ থাকা সন্তানের তথ্য দিয়ে এই বাচ্চার admission তথ্য দিন। অ্যাডমিন অনুমোদনের পর অন্য সন্তানও দেখা যাবে।',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          TextField(controller: _code, decoration: const InputDecoration(
              labelText: 'Student Unique ID *', hintText: 'S-2026-002', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _dob, readOnly: true, decoration: const InputDecoration(
              labelText: 'Date of Birth *', border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today)),
            onTap: () async {
              final d = await showDatePicker(context: context,
                  initialDate: DateTime(2013), firstDate: DateTime(1995), lastDate: DateTime.now());
              if (d != null) _dob.text = d.toIso8601String().substring(0, 10);
            }),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _className, keyboardType: TextInputType.number, decoration: const InputDecoration(
                labelText: 'Class *', hintText: '7', border: OutlineInputBorder()))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: _section, decoration: const InputDecoration(
                labelText: 'Section/Group *', hintText: 'A', border: OutlineInputBorder()))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _roll, keyboardType: TextInputType.number, decoration: const InputDecoration(
                labelText: 'Roll *', border: OutlineInputBorder()))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(
                labelText: 'Admission Phone *', border: OutlineInputBorder()))),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _relation, decoration: const InputDecoration(
              labelText: 'Relation (ঐচ্ছিক)', hintText: 'sibling', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red))),
          if (_success != null)
            Padding(padding: const EdgeInsets.only(bottom: 12),
                child: Text(_success!, style: const TextStyle(color: Colors.green))),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: Padding(padding: const EdgeInsets.all(14),
                child: _loading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('অনুরোধ পাঠান')),
          ),
          const SizedBox(height: 20),
          if (_requests != null) ...[
            const Text('আবেদনের অবস্থা', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            if (_requests!.isEmpty)
              const Text('কোনো আবেদন নেই', style: TextStyle(color: Colors.grey))
            else
              for (final r in _requests!)
                Card(child: ListTile(
                  leading: const Icon(Icons.person_add_alt_1),
                  title: Text(r['student_name']?.toString() ?? ''),
                  subtitle: Text('${r['class_name'] ?? ''} (${r['section'] ?? ''})'),
                  trailing: Text(_statusLabel(r['status']?.toString() ?? ''),
                      style: TextStyle(color: _statusColor(r['status']?.toString() ?? ''), fontWeight: FontWeight.bold)),
                )),
          ],
        ]),
      ),
    );
  }
}