import 'package:flutter/material.dart';

import '../api.dart';

class GuardianStudentProfileScreen extends StatefulWidget {
  final int studentId;
  const GuardianStudentProfileScreen({super.key, required this.studentId});
  @override
  State<GuardianStudentProfileScreen> createState() =>
      _GuardianStudentProfileScreenState();
}

class _GuardianStudentProfileScreenState
    extends State<GuardianStudentProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _guardian = TextEditingController();
  final _father = TextEditingController();
  final _mother = TextEditingController();
  final _address = TextEditingController();
  final _dob = TextEditingController();
  final _birthCert = TextEditingController();
  final _reason = TextEditingController();
  final _changes = TextEditingController();
  Map<String, dynamic> _student = {};
  List<String> _religions = [];
  List _requests = [];
  String? _religion;
  String _gender = '';
  String? _bloodGroup;
  String? _optionalSubject;
  String? _compulsorySubject;
  bool _scholarship = false, _loading = true, _busy = false;
  bool get _locked => _student['guardian_profile_locked_at'] != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _guardian.dispose();
    _father.dispose();
    _mother.dispose();
    _address.dispose();
    _dob.dispose();
    _birthCert.dispose();
    _reason.dispose();
    _changes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = Map<String, dynamic>.from(
        await Api.get('/guardian/student/${widget.studentId}/profile'),
      );
      final s = Map<String, dynamic>.from(data['student'] as Map);
      if (!mounted) return;
      setState(() {
        _student = s;
        _religions = List<String>.from(data['religions'] ?? []);
        _requests = List.from(data['requests'] ?? []);
        _name.text = '${s['name'] ?? ''}';
        _phone.text = '${s['guardian_phone'] ?? ''}';
        _guardian.text = '${s['guardian_name'] ?? ''}';
        _father.text = '${s['father_name'] ?? ''}';
        _mother.text = '${s['mother_name'] ?? ''}';
        _address.text = '${s['address'] ?? ''}';
        _dob.text = '${s['dob'] ?? ''}'.split('T').first;
        _birthCert.text = '${s['birth_cert_no'] ?? ''}';
        _religion = s['religion']?.toString();
        _gender = '${s['gender'] ?? ''}';
        _optionalSubject = s['optional_subject']?.toString();
        _compulsorySubject = s['compulsory_subject']?.toString();
        final className = '${s['class_name'] ?? ''}';
        final levelMatch = RegExp(r'\d+').firstMatch(className);
        final level = levelMatch == null
            ? 0
            : int.tryParse(levelMatch.group(0) ?? '') ?? 0;
        final group = '${s['group_name'] ?? s['section'] ?? ''}'.toLowerCase();
        if (level == 9 || level == 10) {
          final isArts = group.contains('arts') || group.contains('humanit');
          final isCommerce =
              group.contains('commerce') || group.contains('business');
          final isScience = group.contains('science');
          final genderLower = _gender.toLowerCase();
          if (_compulsorySubject == null && isArts) {
            _compulsorySubject = 'Economics';
          }
          if (_optionalSubject == null) {
            if (isArts || isCommerce) {
              _optionalSubject = genderLower == 'male'
                  ? 'Agriculture'
                  : genderLower == 'female'
                  ? 'Home Science'
                  : null;
            } else if (isScience &&
                (genderLower == 'male' || genderLower == 'female')) {
              _optionalSubject = 'Higher Mathematics';
            }
          }
        }
        _bloodGroup = s['blood_group']?.toString();
        _scholarship =
            s['receives_scholarship'] == true || s['receives_scholarship'] == 1;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _complete() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final result = await Api.post(
        '/guardian/student/${widget.studentId}/profile/complete',
        {
          'name': _name.text.trim(),
          'religion': _religion,
          'receives_scholarship': _scholarship,
          'guardian_name': _guardian.text.trim(),
          'guardian_phone': _phone.text.trim(),
          'father_name': _father.text.trim(),
          'mother_name': _mother.text.trim(),
          'address': _address.text.trim(),
          'dob': _dob.text.trim(),
          'birth_cert_no': _birthCert.text.trim(),
          'gender': _gender,
          'optional_subject': _optionalSubject,
          'compulsory_subject': _compulsorySubject,
          'blood_group': _bloodGroup,
        },
      );
      if (Api.isQueued(result)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'ইন্টারনেট না থাকায় তথ্য ফোনে রাখা হয়েছে; সংযোগ ফিরলে আবার জমা দিন।',
              ),
            ),
          );
        }
        return;
      }
      if (result is Map && result['locked'] == true && mounted) {
        setState(
          () => _student['guardian_profile_locked_at'] = DateTime.now()
              .toIso8601String(),
        );
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('শিক্ষার্থীর প্রোফাইল সফলভাবে জমা হয়েছে।'),
          ),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _request() async {
    if (_reason.text.trim().length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'অনুরোধ পাঠানোর আগে আপনার সমস্যাটি অন্তত ৫ অক্ষরে লিখুন।',
          ),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await Api.post(
        '/guardian/student/${widget.studentId}/profile-edit-requests',
        {
          'reason': _reason.text.trim(),
          'proposed_changes': {'details': _changes.text.trim()},
        },
      );
      if (Api.isQueued(result)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'ইন্টারনেট না থাকায় অনুরোধটি পাঠানো যায়নি। সংযোগ করে আবার চেষ্টা করুন।',
              ),
            ),
          );
        }
        return;
      }
      _reason.clear();
      _changes.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('সংশোধনের অনুরোধ অ্যাডমিনের কাছে পাঠানো হয়েছে।'),
          ),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final className = '${_student['class_name'] ?? ''}';
    final levelMatch = RegExp(r'\d+').firstMatch(className);
    final level = levelMatch == null
        ? 0
        : int.tryParse(levelMatch.group(0) ?? '') ?? 0;
    final group = '${_student['group_name'] ?? _student['section'] ?? ''}'
        .toLowerCase();
    final isSenior = level == 9 || level == 10;
    final isArts = group.contains('arts') || group.contains('humanit');
    final isCommerce = group.contains('commerce') || group.contains('business');
    final isScience = group.contains('science');
    final fields = <Widget>[
      TextFormField(
        controller: _name,
        decoration: const InputDecoration(labelText: 'শিক্ষার্থীর নাম'),
        validator: (v) => v == null || v.trim().isEmpty ? 'নাম আবশ্যক' : null,
      ),
      TextFormField(
        controller: _dob,
        readOnly: true,
        decoration: const InputDecoration(labelText: 'জন্মতারিখ *'),
        validator: (v) =>
            v == null || v.trim().isEmpty ? 'জন্মতারিখ বাছুন' : null,
        onTap: _locked
            ? null
            : () async {
                final now = DateTime.now();
                final parsed = DateTime.tryParse(_dob.text);
                final d = await showDatePicker(
                  context: context,
                  initialDate: parsed ?? DateTime(now.year - 10),
                  firstDate: DateTime(1990),
                  lastDate: now,
                );
                if (d != null) _dob.text = d.toIso8601String().substring(0, 10);
              },
      ),
      TextFormField(
        controller: _birthCert,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'জন্মনিবন্ধন নম্বর *'),
        validator: (v) =>
            v == null || v.trim().isEmpty ? 'জন্মনিবন্ধন নম্বর আবশ্যক' : null,
      ),
      DropdownButtonFormField<String>(
        value: _religions.contains(_religion) ? _religion : null,
        decoration: const InputDecoration(labelText: 'ধর্ম'),
        items: _religions
            .map((r) => DropdownMenuItem(value: r, child: Text(r)))
            .toList(),
        validator: (v) => v == null || v.isEmpty ? 'ধর্ম বেছে নিন' : null,
        onChanged: _locked ? null : (v) => setState(() => _religion = v),
      ),
      TextFormField(
        controller: _phone,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(labelText: 'অভিভাবকের ফোন'),
        validator: (v) =>
            v == null || v.replaceAll(RegExp(r'\D'), '').length < 10
            ? 'সঠিক ফোন নম্বর দিন'
            : null,
      ),
      TextFormField(
        controller: _guardian,
        decoration: const InputDecoration(labelText: 'অভিভাবকের নাম *'),
        validator: (v) =>
            v == null || v.trim().isEmpty ? 'অভিভাবকের নাম আবশ্যক' : null,
      ),
      TextFormField(
        controller: _father,
        decoration: const InputDecoration(labelText: 'পিতার নাম *'),
        validator: (v) =>
            v == null || v.trim().isEmpty ? 'পিতার নাম আবশ্যক' : null,
      ),
      TextFormField(
        controller: _mother,
        decoration: const InputDecoration(labelText: 'মাতার নাম *'),
        validator: (v) =>
            v == null || v.trim().isEmpty ? 'মাতার নাম আবশ্যক' : null,
      ),
      TextFormField(
        controller: _address,
        maxLines: 2,
        decoration: const InputDecoration(labelText: 'ঠিকানা *'),
        validator: (v) =>
            v == null || v.trim().isEmpty ? 'ঠিকানা আবশ্যক' : null,
      ),
      DropdownButtonFormField<String>(
        value: _gender.isNotEmpty ? _gender : null,
        decoration: const InputDecoration(labelText: 'লিঙ্গ'),
        items: const [
          DropdownMenuItem(value: 'Male', child: Text('ছেলে')),
          DropdownMenuItem(value: 'Female', child: Text('মেয়ে')),
          DropdownMenuItem(value: 'Other', child: Text('অন্য')),
        ],
        validator: (v) => v == null ? 'লিঙ্গ বেছে নিন' : null,
        onChanged: _locked
            ? null
            : (v) => setState(() {
                _gender = v ?? '';
                final genderLower = _gender.toLowerCase();
                if (isSenior && isArts && _compulsorySubject == null) {
                  _compulsorySubject = 'Economics';
                }
                if (isSenior && (isArts || isCommerce)) {
                  _optionalSubject = genderLower == 'male'
                      ? 'Agriculture'
                      : genderLower == 'female'
                      ? 'Home Science'
                      : null;
                } else if (isSenior &&
                    isScience &&
                    (genderLower == 'male' || genderLower == 'female')) {
                  _optionalSubject = 'Higher Mathematics';
                }
              }),
      ),
      if (isSenior && isArts)
        DropdownButtonFormField<String>(
          value: _compulsorySubject,
          decoration: const InputDecoration(labelText: 'আবশ্যিক বিষয় *'),
          items: const [
            'Economics',
            'Civics',
          ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          onChanged: _locked
              ? null
              : (v) => setState(() => _compulsorySubject = v),
          validator: (v) => v == null ? 'আবশ্যিক বিষয় বাছুন' : null,
        ),
      if (isSenior)
        DropdownButtonFormField<String>(
          value: _optionalSubject,
          decoration: const InputDecoration(labelText: 'ঐচ্ছিক বিষয় *'),
          items:
              (isScience
                      ? const [
                          'Higher Mathematics',
                          'Agriculture',
                          'Home Science',
                        ]
                      : const ['Agriculture', 'Home Science'])
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
          onChanged: _locked
              ? null
              : (v) => setState(() => _optionalSubject = v),
          validator: (v) => v == null ? 'ঐচ্ছিক বিষয় বাছুন' : null,
        ),
      DropdownButtonFormField<String>(
        value: _bloodGroup,
        decoration: const InputDecoration(labelText: 'রক্তের গ্রুপ *'),
        items: const [
          'A+',
          'A-',
          'B+',
          'B-',
          'O+',
          'O-',
          'AB+',
          'AB-',
          'জানা নেই',
        ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
        validator: (v) =>
            v == null || v.isEmpty ? 'রক্তের গ্রুপ বেছে নিন' : null,
        onChanged: _locked ? null : (v) => setState(() => _bloodGroup = v),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('উপবৃত্তি পায়'),
        value: _scholarship,
        onChanged: _locked ? null : (v) => setState(() => _scholarship = v),
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(_locked ? 'প্রোফাইল সংশোধন' : 'শিক্ষার্থীর তথ্য'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _locked
                    ? const [Color(0xFF167A60), Color(0xFF249B78)]
                    : const [Color(0xFF4547B8), Color(0xFF6B62D9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4547B8).withValues(alpha: .16),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.white.withValues(alpha: .16),
                  child: Icon(
                    _locked ? Icons.verified_rounded : Icons.edit_note_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _locked
                            ? 'প্রোফাইল জমা সম্পন্ন'
                            : 'শিক্ষার্থীর প্রোফাইল সম্পূর্ণ করুন',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _locked
                            ? 'সংশোধনের প্রয়োজন হলে অ্যাডমিনের অনুমোদনের জন্য অনুরোধ পাঠান।'
                            : 'সব তথ্য যাচাই করে একবারে জমা দিন। জমার পর তথ্যগুলো লক থাকবে।',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_student['name']} · Roll ${_student['roll']} · ${_student['class_name']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (_student['is_irregular'] == true ||
                      _student['is_irregular'] == 1)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Chip(label: Text('অনিয়মিত শিক্ষার্থী')),
                    ),
                ],
              ),
            ),
          ),
          AbsorbPointer(
            absorbing: _locked,
            child: Form(
              key: _form,
              child: Column(
                children: [
                  ...fields.map(
                    (w) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: w,
                    ),
                  ),
                  if (!_locked)
                    FilledButton(
                      onPressed: _busy ? null : _complete,
                      child: Text(
                        _busy ? 'সংরক্ষণ হচ্ছে…' : 'একবারের জন্য জমা দিন',
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_locked) ...[
            Card(
              margin: const EdgeInsets.only(top: 14),
              elevation: 0,
              color: const Color(0xFFF5F6FF),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFE2E5FA)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.admin_panel_settings_outlined,
                          color: Color(0xFF5148C8),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'অ্যাডমিনের অনুমোদন নিন',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'প্রোফাইলের তথ্য সংশোধন করতে হলে আপনার সমস্যাটি জানিয়ে অ্যাডমিনের কাছে অনুমোদনের অনুরোধ পাঠান। অনুমোদনের আগে জমা দেওয়া তথ্য পরিবর্তন করা যাবে না।',
                      style: TextStyle(
                        color: Colors.blueGrey.shade700,
                        height: 1.45,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _reason,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'আপনার সমস্যাটি লিখুন *',
                        hintText: 'কেন প্রোফাইল সংশোধন করতে চান তা জানান',
                        helperText: 'এই কারণটি অ্যাডমিন পর্যালোচনা করবেন',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _changes,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'কোন তথ্যটি কীভাবে সংশোধন হবে',
                        hintText: 'যেমন: ঠিকানার বানান সংশোধন করতে চাই',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _request,
                        icon: const Icon(Icons.send_rounded),
                        label: const Text(
                          'অ্যাডমিনের অনুমোদনের জন্য অনুরোধ পাঠান',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ..._requests.map(
              (r) => ListTile(
                leading: const Icon(Icons.history),
                title: Text('${r['reason']}'),
                subtitle: Text('${r['status']} · ${r['created_at']}'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
