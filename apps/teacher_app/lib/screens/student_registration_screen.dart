import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';
import 'ocr_capture_screen.dart';

/// চ structural Bengali copy template — key fields + ID is auto / roll is manual.
String _bunkPromptTemplate({required String classLabel}) {
  final section = classLabel.toLowerCase().contains('group')
      ? 'গ্রুপ (Group) ± '
      : 'বিভাগ (Section) ± ';
  return '''CLSS: ${classLabel}
ছাত্র / ছাত্রীর তথ্য অনুসরণ করুন বিশ্লেষণ করে নিচের FORMAT-এ ফেরত পাঠান — JSON row:
{ "name": "...", "roll": "বাস্তব রোল", "dob": "YYYY-MM-DD", "religion": "...",
  "guardian_name": "...", "guardian_phone": "...", "father_name": "...",
  "mother_name": "...", "birth_cert_no": "...", "address": "...",
  "${classLabel.toLowerCase().contains('group') ? 'group' : 'section'}": "..." }

RULES:
- Student কোড (Student Code / Code): সার্ভার স্বয়ংক্রিয়ভাবে তৈরি করবে — লিখবেন না।
- রোল (Roll): শুধু এই ফিল্ডটি ম্যানুয়াল/ইমপোর্ট prompt থেকে আসে — বাধ্যতামূলকভাবে ভরুন যাচাই করে,
  প্লিজ school-এর এই ক্লাসের (${classLabel}) ${section}স্বয়ংক্রিয় Code+Roll থেকে আলাদা ভাবে রেখে দিন।
- নিচের Prompt-এ নামের পাশে থাকা রোলটি পড়ে 'roll' কী-তে ভরুন.''';
}

/// Parser — reads a Bangla/English copy blob and extracts Roll/রোল into the roll input.
void _bunkParsePrompt(String raw, void Function(String?) onRoll) {
  final rg1 = RegExp(r'''[Rr]oll|রোল''');
  final m = rg1.firstMatch(raw);
  if (m != null) {
    final tail = raw.substring(m.end);
    final mv = RegExp(r'[:=]?\s*(\d+)').firstMatch(tail);
    if (mv != null) onRoll(mv.group(1));
  }
}


class StudentRegistrationScreen extends StatefulWidget {
  final dynamic teacher;
  final int classId;
  final String classLabel;
  const StudentRegistrationScreen({
    super.key,
    required this.teacher,
    required this.classId,
    required this.classLabel,
  });
  @override
  State<StudentRegistrationScreen> createState() =>
      _StudentRegistrationScreenState();
}

class _StudentRegistrationScreenState extends State<StudentRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  String _name = '';
  DateTime? _dob;
  String _religion = '';
  String _guardianName = '';
  String _guardianPhone = '';
  String _fatherName = '';
  String _motherName = '';
  String _birthCertNo = '';
  String _address = '';
  bool _saving = false;
  String? _error;
  String _sectionGroup = '';
  final bool _classHasGroup = false;
  final _rollCtl = TextEditingController();
  final _sectionGroupCtl = TextEditingController();

  static const _religions = [
    'Islam',
    'Hindu',
    'Christian',
    'Buddhist',
    'Other',
  ];

  Future<void> _pickDob() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(2015, 1, 1),
      firstDate: DateTime(2005),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _dob = d);
  }

  Future<void> _showPromptImport() async {
    final f = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => _PromptImportDialog(classLabel: widget.classLabel),
    );
    if (f != null && f.isNotEmpty) _fillForm(f);
  }

  bool _fillForm(Map<String, String> data) {
    setState(() {
      _name = data['name'] ?? '';
      _religion = data['religion'] ?? '';
      _guardianName = data['guardian_name'] ?? '';
      _guardianPhone = data['guardian_phone'] ?? '';
      _fatherName = data['father_name'] ?? '';
      _motherName = data['mother_name'] ?? '';
      _birthCertNo = data['birth_cert_no'] ?? '';
      _address = data['address'] ?? '';
      _sectionGroup = data['section'] ?? data['group'] ?? '';
    });
    return true;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final r = await Api.post('/teacher/students', {
        'name': _name.trim(),
        'class_id': widget.classId,
        'dob': _dob?.toIso8601String().substring(0, 10),
        'religion': _religion.isNotEmpty ? _religion : null,
        'section': _sectionGroup.isNotEmpty ? _sectionGroup.trim() : null,
        'guardian_name': _guardianName.isNotEmpty ? _guardianName.trim() : null,
        'guardian_phone': _guardianPhone.isNotEmpty
            ? _guardianPhone.trim()
            : null,
        'father_name': _fatherName.isNotEmpty ? _fatherName.trim() : null,
        'mother_name': _motherName.isNotEmpty ? _motherName.trim() : null,
        'birth_cert_no': _birthCertNo.isNotEmpty ? _birthCertNo.trim() : null,
        'address': _address.isNotEmpty ? _address.trim() : null,
      });
      if (!mounted) return;
      final code = r['student_code'] ?? '';
      final roll = r['roll'] ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green,
          content: Text(
            '✓ ${_name.trim()} registered — Roll: $roll, Code: $code',
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _saving = false;
      });
    }
  }

  /// চ structural Bengali copy template — key fields + ID is auto/roll is manual.
  String _promptTemplate() {
    final section = widget.classLabel.toLowerCase().contains('group')
        ? 'গ্রুপ (Group) ± '
        : 'বিভাগ (Section) ± ';
    return '''CLSS: ${widget.classLabel}
ছাত্র / ছাত্রীর তথ্য অনুসরণ করুন বিশ্লেষণ করে নীচের FORMAT-এ ফেরত পাঠান — JSON row:
{ "name": "...", "roll": "বাস্তব রোল", "dob": "YYYY-MM-DD", "religion": "...",
  "guardian_name": "...", "guardian_phone": "...", "father_name": "...",
  "mother_name": "...", "birth_cert_no": "...", "address": "...",
  "${widget.classLabel.contains('group') ? 'group' : 'section'}": "..." }

RULES:
- Student কোড (Student Code / Code): সার্ভার স্বয়ংক্রিয়ভাবে তৈরি করবে — লিখবেন না।
- রোল (Roll): শুধু এই ফিল্ডটি ম্যানুয়াল/ইমপোর্ট prompt থেকে আসে — বাধ্যতামূলকভাবে ভরুন যাচাই করে,
  প্লিজ school-এর এই ক্লাসের (${widget.classLabel}) ${section}স্বয়ংক্রিয় Code+Roll থেকে আলাদা ভাবে রেখে দিন।
- নিচের Prompt-এ নামের পাশে থাকা রোলটি পড়ে 'roll' কী-তে ভরুন।''';
  }

  /// Parser — reads a Bangla/English prompt blob and extracts 'Roll'/'রোল' into the roll input.
  void _parsePromptText(String raw) {
    // extract manually stated roll: রোল: 12 / Roll: 12 / রোল ১২ / roll=12
    final rg1 = RegExp(r'''[Rr]oll|রোল''');
    final m = rg1.firstMatch(raw);
    if (m != null) {
      final tail = raw.substring(m.end);
      final mv = RegExp(r'[:=]?\s*(\d+)').firstMatch(tail);
      if (mv != null) setState(() => _rollCtl.text = mv.group(1) ?? '');
    }
    // auto-fill other section/group if present with section label
    final sec = RegExp(
      r'(?:section|group|গ্রুপ|বিভাগ)\s*[:=]?\s*([শালা-হা-zA-Z0-9]+)',
    ).firstMatch(raw.toLowerCase());
    if (sec != null && _sectionGroupCtl.text.isEmpty) {
      setState(() => _sectionGroupCtl.text = sec.group(1) ?? '');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('নতুন ছাত্র ভর্তি')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Class: ${widget.classLabel}\nStudent Code auto-generated → Roll entered manually\n${widget.classLabel}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),

            // Data-fill entry points (OCR scan / prompt import)
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      final r = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OcrCaptureScreen(
                            classId: widget.classId,
                            classLabel: widget.classLabel,
                          ),
                        ),
                      );
                      if (r is Map<String, String> && r.isNotEmpty)
                        _fillForm(r);
                    },
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('OCR স্ক্যান'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showPromptImport,
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('Prompt ইমপোর্ট'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Name
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'ছাত্র/ছাত্রীর নাম *',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'নাম আবশ্যক' : null,
              onSaved: (v) => _name = v ?? '',
            ),
            const SizedBox(height: 12),

            // DOB
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _dob != null
                    ? 'জন্ম তারিখ: ${_dob!.toIso8601String().substring(0, 10)}'
                    : 'জন্ম তারিখ (ঐচ্ছিক)',
              ),
              leading: const Icon(Icons.cake_outlined),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickDob,
            ),
            const Divider(),

            // Religion dropdown
            DropdownButtonFormField<String>(
              initialValue: _religion.isNotEmpty ? _religion : null,
              decoration: const InputDecoration(
                labelText: 'ধর্ম (ঐচ্ছিক)',
                border: OutlineInputBorder(),
              ),
              items: _religions
                  .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                  .toList(),
              onChanged: (v) => setState(() => _religion = v ?? ''),
            ),
            const SizedBox(height: 12),

            // Section/Group — dynamic label per class config (Phase B).
            TextFormField(
              key: const Key('student_section_group'),
              initialValue: _sectionGroup,
              decoration: InputDecoration(
                labelText: _classHasGroup ? 'গ্রুপ (Group)' : 'বিভাগ (Section)',
                hintText: /* c */ _classHasGroup
                    ? 'যেমন: Science / Commerce / Arts'
                    : 'যেমন: ক / খ / গ',
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => _sectionGroup = v.trim(),
            ),
            const SizedBox(height: 12),

            // Father
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'পিতার নাম',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              onSaved: (v) => _fatherName = v ?? '',
            ),
            const SizedBox(height: 12),

            // Mother
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'মাতার নাম',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              onSaved: (v) => _motherName = v ?? '',
            ),
            const SizedBox(height: 12),

            // Birth cert
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'জন্মনিবন্ধন নং',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onSaved: (v) => _birthCertNo = v ?? '',
            ),
            const SizedBox(height: 12),

            // Guardian name
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'অভিভাবকের নাম',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              onSaved: (v) => _guardianName = v ?? '',
            ),
            const SizedBox(height: 12),

            // Guardian phone
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'অভিভাবকের ফোন',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
              onSaved: (v) => _guardianPhone = v ?? '',
            ),
            const SizedBox(height: 12),

            // Address
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'ঠিকানা',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              onSaved: (v) => _address = v ?? '',
            ),
            const SizedBox(height: 18),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ),

            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.person_add),
              label: Text(_saving ? 'Saving...' : 'ভর্তি করুন'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromptImportDialog extends StatefulWidget {
  final String classLabel;
  const _PromptImportDialog({required this.classLabel});

  @override
  State<_PromptImportDialog> createState() => _PromptImportDialogState();
}

class _PromptImportDialogState extends State<_PromptImportDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtl = TextEditingController();
  final _rollCtl = TextEditingController();
  final _dobCtl = TextEditingController();
  final _religionCtl = TextEditingController();
  final _guardianNameCtl = TextEditingController();
  final _guardianPhoneCtl = TextEditingController();
  final _fatherNameCtl = TextEditingController();
  final _motherNameCtl = TextEditingController();
  final _birthCertNoCtl = TextEditingController();
  final _addressCtl = TextEditingController();
  final _sectionGroupCtl = TextEditingController();

  @override
  void dispose() {
    _nameCtl.dispose();
    _rollCtl.dispose();
    _dobCtl.dispose();
    _religionCtl.dispose();
    _guardianNameCtl.dispose();
    _guardianPhoneCtl.dispose();
    _fatherNameCtl.dispose();
    _motherNameCtl.dispose();
    _birthCertNoCtl.dispose();
    _addressCtl.dispose();
    _sectionGroupCtl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, {
      'name': _nameCtl.text.trim(),
      'roll': _rollCtl.text.trim(),
      'dob': _dobCtl.text.trim(),
      'religion': _religionCtl.text.trim(),
      'guardian_name': _guardianNameCtl.text.trim(),
      'guardian_phone': _guardianPhoneCtl.text.trim(),
      'father_name': _fatherNameCtl.text.trim(),
      'mother_name': _motherNameCtl.text.trim(),
      'birth_cert_no': _birthCertNoCtl.text.trim(),
      'address': _addressCtl.text.trim(),
      'section': _sectionGroupCtl.text.trim(),
      'group': _sectionGroupCtl.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Prompt ইমপোর্ট — ${widget.classLabel}'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Student কোড স্বয়ংক্রিয় + রোল ম্যানুয়াল ইনপুট'),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    final b = ScaffoldMessenger.of(context);
                    await Clipboard.setData(
                      ClipboardData(text: _bunkPromptTemplate(classLabel: widget.classLabel)),
                    );
                    if (!mounted) return;
                    b.showSnackBar(
                      const SnackBar(
                        backgroundColor: Colors.teal,
                        content: Text('✓ AI প্রম্পট টেমপ্লেট কপি হয়েছে'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_all, size: 18),
                  label: const Text('Copy AI Prompt Template'),
                ),
              ),
              const SizedBox(height: 4),
              TextFormField(
                controller: _nameCtl,
                decoration: const InputDecoration(
                  labelText: 'নাম',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'নাম আবশ্যক' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _rollCtl,
                decoration: const InputDecoration(
                  labelText: 'রোল',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _dobCtl,
                decoration: const InputDecoration(
                  labelText: 'জন্ম তারিখ (YYYY-MM-DD)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _religionCtl,
                decoration: const InputDecoration(
                  labelText: 'ধর্ম',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _guardianNameCtl,
                decoration: const InputDecoration(
                  labelText: 'অভিভাবকের নাম',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _guardianPhoneCtl,
                decoration: const InputDecoration(
                  labelText: 'অভিভাবকের ফোন',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _fatherNameCtl,
                decoration: const InputDecoration(
                  labelText: 'পিতার নাম',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _motherNameCtl,
                decoration: const InputDecoration(
                  labelText: 'মাতার নাম',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _birthCertNoCtl,
                decoration: const InputDecoration(
                  labelText: 'জন্ম নিবন্ধন নং',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _addressCtl,
                decoration: const InputDecoration(
                  labelText: 'ঠিকানা',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _sectionGroupCtl,
                decoration: InputDecoration(
                  labelText: widget.classLabel.toLowerCase().contains('group')
                      ? 'গ্রুপ (Group)'
                      : 'বিভাগ (Section)',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('বাতিল'),
        ),
        FilledButton(onPressed: _submit, child: const Text('ইমপোর্ট করুন')),
      ],
    );
  }
}
