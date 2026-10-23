import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../api.dart';
import '../update_check.dart';
import '../config.dart';

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
  String? _logoUrl;
  bool _logoLoading = false;

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
        _logoUrl = r['school_logo_path'];
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

  Future<void> _pickAndUploadLogo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      setState(() { _logoLoading = true; _error = null; _msg = null; });

      final file = result.files.first;
      if (file.bytes == null && file.path == null) {
        setState(() { _logoLoading = false; _error = 'ফাইলটি পড়া যায়নি। PNG/JPG/WebP ছবি আবার বাছুন।'; });
        return;
      }

      // Upload via multipart
      final uri = Uri.parse(Config.api + '/admin/settings/logo');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer ${Api.token}';
      if (file.bytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'logo',
          file.bytes!,
          filename: file.name,
        ));
      } else {
        request.files.add(await http.MultipartFile.fromPath('logo', file.path!, filename: file.name));
      }
      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final resp = await http.Response.fromStream(streamed);

      if (!mounted) return;

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final data = jsonDecode(resp.body);
        if (data['ok'] == true) {
          setState(() {
            _logoUrl = data['logo_url'];
            _logoLoading = false;
            _msg = 'Logo uploaded successfully';
          });
        } else {
          setState(() { _logoLoading = false; _error = data['error'] ?? 'Upload failed'; });
        }
      } else {
        setState(() { _logoLoading = false; _error = 'Upload failed (${resp.statusCode})'; });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _logoLoading = false; _error = friendlyError(e); });
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
                  // School Logo Section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.image, color: Colors.blue),
                              const SizedBox(width: 8),
                              const Text('School Logo',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              const Spacer(),
                              if (_logoLoading)
                                const SizedBox(
                                    width: 20, height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2))
                              else
                                OutlinedButton.icon(
                                  onPressed: _pickAndUploadLogo,
                                  icon: const Icon(Icons.upload, size: 18),
                                  label: const Text('Change Logo'),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'স্বচ্ছ ব্যাকগ্রাউন্ডসহ PNG লোগো দিলে সবচেয়ে ভালো দেখাবে। JPG/PNG/WebP, সর্বোচ্চ ২ MB।',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 12),
                          if (_logoUrl != null && _logoUrl!.isNotEmpty)
                            Center(
                              child: Container(
                                constraints: const BoxConstraints(maxHeight: 120, maxWidth: 240),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    _logoUrl!.startsWith('http://') || _logoUrl!.startsWith('https://')
                                        ? _logoUrl!
                                        : Config.downloadBase + _logoUrl!,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) =>
                                        const Icon(Icons.broken_image, size: 60, color: Colors.grey),
                                  ),
                                ),
                              ),
                          )
                          else
                            const Center(
                                child: Text('No logo uploaded yet',
                                    style: TextStyle(color: Colors.grey))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('ভেরিকাল তথ্য — marksheet/admit card-এ ব্যবহৃত হয়',
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
                    subtitle: FutureBuilder(
                      future: Future.wait([installedVersion(), installedBuild()]),
                      builder: (_, s) {
                        final v = s.data is List ? (s.data as List)[0].toString() : '…';
                        final b = s.data is List ? (s.data as List)[1].toString() : '…';
                        return Text('ফোনে: v$v • build $b — tap করে সার্ভারের সাথে মিলান');
                      },
                    ),
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
