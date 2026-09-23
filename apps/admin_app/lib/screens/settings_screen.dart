import 'package:flutter/material.dart';
import '../api.dart';
import '../update_check.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<_Field> _fields = [];
  List _holidays = [];
  bool _loading = true;
  String? _error;
  String? _msg;
  final _hDate = TextEditingController();
  final _hTitle = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.get('/admin/settings');
      final holidays = await Api.get('/admin/holidays');
      setState(() {
        _fields = [
          _Field('school_name', 'School Name', r['school_name'] ?? ''),
          _Field('school_address', 'Address', r['school_address'] ?? ''),
          _Field('school_eiin', 'EIIN', r['school_eiin'] ?? ''),
          _Field('headmaster', 'Headmaster Name', r['headmaster'] ?? ''),
          _Field('exam_term_name', 'Default Exam Term Name', r['exam_term_name'] ?? ''),
        ];
        _holidays = holidays is List ? holidays : [];
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _save() async {
    final body = <String, String>{};
    for (final f in _fields) { body[f.key] = f.controller.text.trim(); }
    try {
      await Api.put('/admin/settings', body);
      if (!mounted) return;
      setState(() => _msg = 'Settings saved — documents এখন এই তথ্য ব্যবহার করবে');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _addHoliday() async {
    if (_hDate.text.isEmpty || _hTitle.text.isEmpty) return;
    try {
      await Api.post('/admin/holidays', {'date': _hDate.text, 'title': _hTitle.text});
      _hDate.clear(); _hTitle.clear();
      final holidays = await Api.get('/admin/holidays');
      if (!mounted) return;
      setState(() => _holidays = holidays is List ? holidays : []);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _delHoliday(String date) async {
    try {
      await Api.delete('/admin/holidays/${date.substring(0, 10)}');
      final holidays = await Api.get('/admin/holidays');
      if (!mounted) return;
      setState(() => _holidays = holidays is List ? holidays : []);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings & Holidays')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _fields.isEmpty
              ? Center(child: Text(_error!))
              : ListView(padding: const EdgeInsets.all(16), children: [
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  if (_msg != null)
                    Text(_msg!, style: TextStyle(color: Colors.green.shade800)),
                  const Text('ভেরিকাল 정보 — marksheet/admit card-এ ব্যবহৃত হয়',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 10),
                  for (final f in _fields) Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: f.controller,
                      decoration: InputDecoration(labelText: f.label, border: const OutlineInputBorder()),
                    ),
                  ),
                  FilledButton(onPressed: _save, child: const Text('Save Settings')),
                  const SizedBox(height: 22),
                  Card(child: ListTile(
                    leading: const Icon(Icons.system_update_alt, color: Colors.blue),
                    title: const Text('অ্যাপ আপডেট'),
                    subtitle: Text('বর্তমান version: v$appVersion — নতুন update চেক করুন'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => checkForUpdate(context, 'admin', manual: true),
                  )),
                  const SizedBox(height: 10),
                  const Text('Holidays — ছুটির দিন (attendance-তে বাদ যাবে)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: TextField(
                      controller: _hDate,
                      readOnly: true,
                      decoration: const InputDecoration(labelText: 'Date', border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today)),
                      onTap: () async {
                        final d = await showDatePicker(context: context,
                            initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040));
                        if (d != null) _hDate.text = d.toIso8601String().substring(0, 10);
                      },
                    )),
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: TextField(
                      controller: _hTitle,
                      decoration: const InputDecoration(labelText: 'কী ছুটি?', border: OutlineInputBorder()),
                    )),
                  ]),
                  const SizedBox(height: 8),
                  FilledButton.tonal(onPressed: _addHoliday, child: const Text('+ Add Holiday')),
                  const SizedBox(height: 10),
                  if (_holidays.isEmpty)
                    const Text('No holidays added.', style: TextStyle(color: Colors.grey))
                  else
                    for (final h in _holidays)
                      Card(child: ListTile(
                        dense: true,
                        title: Text(h['title']?.toString() ?? ''),
                        subtitle: Text((h['date']?.toString() ?? '').substring(0, 10)),
                        trailing: TextButton(onPressed: () =>
                            _delHoliday(h['date'].toString()), child: const Text('Delete', style: TextStyle(color: Colors.red))),
                      )),
                ]),
    );
  }
}

class _Field {
  final String key;
  final String label;
  final TextEditingController controller;
  _Field(this.key, this.label, String value) : controller = TextEditingController(text: value);
}