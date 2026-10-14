import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';
import '../student_prompt_parser.dart';
import 'ocr_capture_screen.dart';

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
  final _rollCtl = TextEditingController();
  final _nameCtl = TextEditingController();
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
  // Live roll-check state: null = unchecked/empty, true = taken, false = free.
  bool? _rollTaken;
  Map<String, dynamic>? _rollTakenBy;
  bool _rollChecking = false;
  int _rollCheckSeq = 0;

  @override
  void dispose() {
    _rollCtl.dispose();
    _nameCtl.dispose();
    super.dispose();
  }

  // Debounced live roll lookup — teacher types a roll, we instantly report
  // whether it is already admitted (with that student's info). Clearing the
  // field resets the state so the flow keeps going.
  Future<void> _checkRoll(String raw) async {
    final v = raw.trim();
    final seq = ++_rollCheckSeq;
    if (v.isEmpty) {
      if (mounted) setState(() {
        _rollTaken = null;
        _rollTakenBy = null;
        _rollChecking = false;
      });
      return;
    }
    final n = int.tryParse(v);
    if (n == null || n <= 0) {
      if (mounted) setState(() {
        _rollTaken = null;
        _rollTakenBy = null;
        _rollChecking = false;
      });
      return;
    }
    if (mounted) setState(() => _rollChecking = true);
    await Future.delayed(const Duration(milliseconds: 450));
    if (seq != _rollCheckSeq || !mounted) return;
    try {
      final r = await Api.get('/teacher/classes/${widget.classId}/roll-check?roll=$n');
      if (seq != _rollCheckSeq || !mounted) return;
      setState(() {
        _rollChecking = false;
        _rollTaken = r['taken'] == true;
        _rollTakenBy = r['taken'] == true && r['student'] is Map
            ? Map<String, dynamic>.from(r['student'] as Map)
            : null;
      });
    } catch (_) {
      // Offline or server hiccup: never block the form. The POST endpoint
      // still returns 409 with the existing student on submit (safety net).
      if (seq != _rollCheckSeq || !mounted) return;
      setState(() {
        _rollChecking = false;
        _rollTaken = null;
        _rollTakenBy = null;
      });
    }
  }

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
    await showDialog<void>(
      context: context,
      builder: (_) => _PromptImportDialog(
        classId: widget.classId,
        classLabel: widget.classLabel,
      ),
    );
  }

  bool _fillForm(Map<String, String> data) {
    setState(() {
      _name = data['name'] ?? '';
      _nameCtl.text = _name;
      _religion = data['religion'] ?? '';
      _guardianName = data['guardian_name'] ?? '';
      _guardianPhone = data['guardian_phone'] ?? '';
      _fatherName = data['father_name'] ?? '';
      _motherName = data['mother_name'] ?? '';
      _birthCertNo = data['birth_cert_no'] ?? '';
      _address = data['address'] ?? '';
      // NOTE: class/section/group comes from the teacher's own class —
      // prompt-supplied section is intentionally ignored (default rule).
    });
    return true;
  }

  Future<void> _save() async {
    // Roll-first rule: a taken roll blocks submit (single source of truth is
    // the server 409, but the live banner already warned — this is the guard).
    if (_rollTaken == true) {
      setState(() {
        _error = 'Roll ${_rollCtl.text.trim()} ইতিমধ্যে ${_rollTakenBy?['name'] ?? 'অন্য শিক্ষার্থীর'} — অন্য roll দিন বা নম্বর মুছে নতুন দিন।';
      });
      return;
    }
    _name = _nameCtl.text.trim();
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final rollRaw = _rollCtl.text.trim();
      final r = await Api.post('/teacher/students', {
        'name': _nameCtl.text.trim().isNotEmpty ? _nameCtl.text.trim() : _name.trim(),
        'class_id': widget.classId,
        'roll': rollRaw.isNotEmpty ? int.tryParse(rollRaw) : null,
        'dob': _dob?.toIso8601String().substring(0, 10),
        'religion': _religion.isNotEmpty ? _religion : null,
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
      if (Api.isQueued(r)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            backgroundColor: Colors.orange,
            content: Text('ইন্টারনেট নেই — ভর্তি ফোনে সেভ আছে, online হলেই roll/code সহ register হবে')));
        return;
      }
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
                'Class: ${widget.classLabel} (auto — বদলানো যাবে না)\nStudent Code auto-generated',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),

            // Roll FIRST: the identity of the admission. Live-taken banner
            // appears here the moment a duplicate roll is typed.
            TextFormField(
              controller: _rollCtl,
              decoration: InputDecoration(
                labelText: 'রোল নম্বর *',
                hintText: 'যেমন: 5',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.confirmation_number_outlined),
                suffixIcon: _rollChecking
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : (_rollTaken == true
                        ? const Icon(Icons.error_outline, color: Colors.red)
                        : (_rollTaken == false
                            ? const Icon(Icons.check_circle_outline, color: Colors.green)
                            : null)),
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'রোল আবশ্যক';
                final n = int.tryParse(v.trim());
                if (n == null || n <= 0) return 'সঠিক রোল দিন';
                return null;
              },
              onChanged: _checkRoll,
            ),
            if (_rollTaken == true && _rollTakenBy != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Roll ${_rollTakenBy!['roll']} ইতিমধ্যে "${_rollTakenBy!['name']}"-এর — নম্বর মুছে অন্য roll দিন, নতুন student-এর form তখনই fill করা যাবে।',
                      style: const TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                  ),
                ]),
              ),
            if (_rollTaken == false)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: const Row(children: [
                  Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                  SizedBox(width: 8),
                  Text('এই roll ফাঁকা আছে — form fill করে ভর্তি করুন।',
                      style: TextStyle(fontSize: 13)),
                ]),
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
                      if (r is Map<String, String> && r.isNotEmpty) {
                        _fillForm(r);
                      }
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
              controller: _nameCtl,
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
  final int classId;
  final String classLabel;
  const _PromptImportDialog({required this.classId, required this.classLabel});

  @override
  State<_PromptImportDialog> createState() => _PromptImportDialogState();
}

class _PromptImportDialogState extends State<_PromptImportDialog> {
  final _promptCtl = TextEditingController();
  final _nameCtl = TextEditingController();
  final _rollCtl = TextEditingController();
  final _genderCtl = TextEditingController();
  final _dobCtl = TextEditingController();
  final _religionCtl = TextEditingController();
  final _bloodCtl = TextEditingController();
  final _emailCtl = TextEditingController();
  final _phoneCtl = TextEditingController();
  final _guardianNameCtl = TextEditingController();
  final _guardianPhoneCtl = TextEditingController();
  final _fatherNameCtl = TextEditingController();
  final _motherNameCtl = TextEditingController();
  final _birthCertCtl = TextEditingController();
  final _addressCtl = TextEditingController();
  final _optionalCtl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _promptCtl.dispose();
    _nameCtl.dispose();
    _rollCtl.dispose();
    _genderCtl.dispose();
    _dobCtl.dispose();
    _religionCtl.dispose();
    _bloodCtl.dispose();
    _emailCtl.dispose();
    _phoneCtl.dispose();
    _guardianNameCtl.dispose();
    _guardianPhoneCtl.dispose();
    _fatherNameCtl.dispose();
    _motherNameCtl.dispose();
    _birthCertCtl.dispose();
    _addressCtl.dispose();
    _optionalCtl.dispose();
    super.dispose();
  }

  // The copyable AI prompt: every label EXACTLY matches a parser key
  // (student_prompt_parser.dart §LABEL_ALIASES), each line carries its own
  // example + format rule, and nothing outside the parser's vocabulary is
  // asked. Copy → paste to AI → paste answer back → Parse → all fields fill.
  String _template() {
    return '''আপনি একজন school admission assistant। নিচের ছাত্র/ছাত্রীর তথ্য থেকে প্রতিটি field বের করে STRICT "Label: Value" ফরম্যাটে দিন — প্রতি লাইনে ঠিক একটি field, label হুবহু নিচের মতো (বানান/কোলন বদলাবেন না):

Name: [পুরো নাম]
Roll: [শুধু সংখ্যা, যেমন 12]
Father's Name: [পিতার নাম]
Mother's Name: [মাতার নাম]
Guardian Name: [অভিভাবকের নাম]
Guardian Phone: [11 সংখ্যার মোবাইল, যেমন 01712345678]
Phone: [শিক্ষার্থীর মোবাইল, থাকলে]
Email: [ইমেইল, থাকলে]
Date of Birth: [শুধু YYYY-MM-DD, যেমন 2011-05-15]
Gender: [Male / Female / Other-এর একটি]
Religion: [Islam / Hindu / Christian / Buddhist / Other-এর একটি]
Blood Group: [A+ / A- / B+ / B- / O+ / O- / AB+ / AB- এর একটি]
Birth Certificate No: [শুধু ১৭ সংখ্যা]
Optional Subject: [ঐচ্ছিক বিষয়, থাকলে]
Address: [ঠিকানা]

কঠোর নিয়ম (একটিও ভাঙা যাবে না):
1. "Date of Birth"-এ শুধু YYYY-MM-DD তারিখ — জন্ম নিবন্ধন নম্বর কখনোই এখানে নয়।
2. "Birth Certificate No"-তে শুধু ১৭ সংখ্যার নম্বর, নিজের লাইনে।
3. "Gender"-এ আসল লিঙ্গ — অনুমান করে বদলাবেন না।
4. "Roll"-এ শুধু সংখ্যা — "Roll No 5"-এর মতো extra শব্দ নয়।
5. Class / Group / Section লিখবেন না — ${widget.classLabel} স্বয়ংক্রিয়ভাবে বসবে।
6. জানা নেই এমন field-এর লাইন বাদ দিন — খালি বা "N/A" লিখবেন না।''';
  }

  void _copyTemplate() async {
    final b = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: _template()));
    if (!mounted) return;
    b.showSnackBar(
      const SnackBar(
        backgroundColor: Colors.teal,
        content: Text('✓ AI প্রম্পট টেমপ্লেট কপি হয়েছে — AI-তে paste করে উত্তর এখানে paste করুন'),
      ),
    );
  }

  void _parseAndFill() {
    final res = parseStudentPrompt(_promptCtl.text);
    if (res.isEmpty) {
      setState(() => _error = 'Prompt-এ কোনো তথ্য পাওয়া যায়নি। টেমপ্লেট অনুযায়ী লিখে আবার চেষ্টা করুন।');
      return;
    }
    setState(() {
      if (res['name'] != null) _nameCtl.text = res['name']!;
      if (res['roll'] != null) _rollCtl.text = res['roll']!;
      if (res['gender'] != null) _genderCtl.text = res['gender']!;
      if (res['dob'] != null) _dobCtl.text = res['dob']!;
      if (res['religion'] != null) _religionCtl.text = res['religion']!;
      if (res['blood_group'] != null) _bloodCtl.text = res['blood_group']!;
      if (res['email'] != null) _emailCtl.text = res['email']!;
      if (res['phone'] != null) _phoneCtl.text = res['phone']!;
      if (res['guardian_name'] != null) _guardianNameCtl.text = res['guardian_name']!;
      if (res['guardian_phone'] != null) _guardianPhoneCtl.text = res['guardian_phone']!;
      if (res['father_name'] != null) _fatherNameCtl.text = res['father_name']!;
      if (res['mother_name'] != null) _motherNameCtl.text = res['mother_name']!;
      if (res['birth_cert_no'] != null) _birthCertCtl.text = res['birth_cert_no']!;
      if (res['address'] != null) _addressCtl.text = res['address']!;
      if (res['optional_subject'] != null) _optionalCtl.text = res['optional_subject']!;
      _error = null;
    });
    // Map parser's canonical religion labels to the school's dropdown labels.
    if (_religionCtl.text == 'Hinduism') {
      _religionCtl.text = 'Hindu';
    }
    if (_religionCtl.text == 'Christianity') {
      _religionCtl.text = 'Christian';
    }
    if (_religionCtl.text == 'Buddhism') {
      _religionCtl.text = 'Buddhist';
    }
  }

  Future<void> _submit() async {
    if (_nameCtl.text.trim().isEmpty) {
      setState(() => _error = 'নাম আবশ্যক');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rollRaw = _rollCtl.text.trim();
      final r = await Api.post('/teacher/students', {
        'name': _nameCtl.text.trim(),
        'class_id': widget.classId,
        'roll': rollRaw.isNotEmpty ? int.tryParse(rollRaw) : null,
        'dob': _dobCtl.text.trim().isNotEmpty ? _dobCtl.text.trim() : null,
        'religion': _religionCtl.text.trim().isNotEmpty ? _religionCtl.text.trim() : null,
        'guardian_name': _guardianNameCtl.text.trim().isNotEmpty ? _guardianNameCtl.text.trim() : null,
        'guardian_phone': _guardianPhoneCtl.text.trim().isNotEmpty ? _guardianPhoneCtl.text.trim() : null,
        'father_name': _fatherNameCtl.text.trim().isNotEmpty ? _fatherNameCtl.text.trim() : null,
        'mother_name': _motherNameCtl.text.trim().isNotEmpty ? _motherNameCtl.text.trim() : null,
        'birth_cert_no': _birthCertCtl.text.trim().isNotEmpty ? _birthCertCtl.text.trim() : null,
        'address': _addressCtl.text.trim().isNotEmpty ? _addressCtl.text.trim() : null,
        'gender': _genderCtl.text.trim().isNotEmpty ? _genderCtl.text.trim() : null,
        'blood_group': _bloodCtl.text.trim().isNotEmpty ? _bloodCtl.text.trim() : null,
        'optional_subject': _optionalCtl.text.trim().isNotEmpty ? _optionalCtl.text.trim() : null,
        'phone': _phoneCtl.text.trim().isNotEmpty ? _phoneCtl.text.trim() : null,
        'email': _emailCtl.text.trim().isNotEmpty ? _emailCtl.text.trim() : null,
      });
      if (!mounted) return;
      if (Api.isQueued(r)) {
        setState(() { _busy = false; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            backgroundColor: Colors.orange,
            content: Text('ইন্টারনেট নেই — prompt ফোনে সেভ আছে, online হলেই register হবে')));
        return;
      }
      final roll = r['roll'] ?? rollRaw;
      final code = r['student_code'] ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green,
          content: Text('✓ ${_nameCtl.text.trim()} — Roll: $roll, Code: $code'),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Widget _input(String label, TextEditingController ctl, {TextInputType? type}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: ctl,
        keyboardType: type,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasGroup = widget.classLabel.toLowerCase().contains('group');
    return AlertDialog(
      title: Text('Prompt ইমপোর্ট — ${widget.classLabel}'),
      content: SingleChildScrollView(
        child: Form(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Class: ${widget.classLabel}\n${hasGroup ? 'গ্রুপ' : 'শাখা'} সবসময় এই ক্লাসটিই default হবে — prompt-এ class/group/section দিলেও তা বাতিল হয়ে যাবে।\nStudent কোড স্বয়ংক্রিয়; রোল prompt থেকে এলে auto-fill হবে।',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _promptCtl,
                maxLines: 4,
                minLines: 3,
                decoration: const InputDecoration(
                  labelText: 'AI Prompt (বাংলা/English)',
                  hintText: 'যেমন: Name: Rahim Uddin\nRoll: 5\nFather\'s Name: ...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _copyTemplate,
                      icon: const Icon(Icons.copy_all, size: 18),
                      label: const Text('Copy AI Prompt Template'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _parseAndFill,
                      icon: const Icon(Icons.auto_fix_high, size: 18),
                      label: const Text('বিশ্লেষণ → ফিল'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _input('ছাত্র/ছাত্রীর নাম *', _nameCtl),
              _input('রোল', _rollCtl, type: TextInputType.number),
              _input('লিঙ্গ (Male/Female/Other)', _genderCtl),
              _input('জন্ম তারিখ (YYYY-MM-DD)', _dobCtl),
              _input('ধর্ম', _religionCtl),
              _input('রক্তের গ্রুপ', _bloodCtl),
              _input('ইমেইল', _emailCtl, type: TextInputType.emailAddress),
              _input('মোবাইল', _phoneCtl, type: TextInputType.phone),
              _input('অভিভাবকের নাম', _guardianNameCtl),
              _input('অভিভাবকের ফোন', _guardianPhoneCtl, type: TextInputType.phone),
              _input('পিতার নাম', _fatherNameCtl),
              _input('মাতার নাম', _motherNameCtl),
              _input('জন্ম নিবন্ধন নং', _birthCertCtl, type: TextInputType.number),
              _input('ঐচ্ছিক বিষয়', _optionalCtl),
              _input('ঠিকানা', _addressCtl),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
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
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.person_add, size: 18),
          label: Text(_busy ? 'Saving...' : 'ভর্তি করুন'),
        ),
      ],
    );
  }
}
