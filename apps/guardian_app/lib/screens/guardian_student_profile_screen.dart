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
  final _reason = TextEditingController();
  final _changes = TextEditingController();
  Map<String, dynamic> _student = {};
  List<String> _religions = [];
  List _requests = [];
  String? _religion;
  String _gender = '';
  String? _bloodGroup;
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
        _religion = s['religion']?.toString();
        _gender = '${s['gender'] ?? ''}';
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
      await Api.post('/guardian/student/${widget.studentId}/profile/complete', {
        'name': _name.text.trim(),
        'religion': _religion,
        'receives_scholarship': _scholarship,
        'guardian_name': _guardian.text.trim(),
        'guardian_phone': _phone.text.trim(),
        'father_name': _father.text.trim(),
        'mother_name': _mother.text.trim(),
        'address': _address.text.trim(),
        'gender': _gender,
        'blood_group': _bloodGroup,
      });
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _request() async {
    if (_reason.text.trim().length < 5) return;
    setState(() => _busy = true);
    try {
      await Api.post(
        '/guardian/student/${widget.studentId}/profile-edit-requests',
        {
          'reason': _reason.text.trim(),
          'proposed_changes': {'details': _changes.text.trim()},
        },
      );
      _reason.clear();
      _changes.clear();
      await _load();
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
    final fields = <Widget>[
      TextFormField(
        controller: _name,
        decoration: const InputDecoration(labelText: 'শিক্ষার্থীর নাম'),
        validator: (v) => v == null || v.trim().isEmpty ? 'নাম আবশ্যক' : null,
      ),
      DropdownButtonFormField<String>(
        value: _religions.contains(_religion) ? _religion : null,
        decoration: const InputDecoration(labelText: 'ধর্ম'),
        items: _religions
            .map((r) => DropdownMenuItem(value: r, child: Text(r)))
            .toList(),
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
            : (v) => setState(() => _gender = v ?? ''),
      ),
      DropdownButtonFormField<String>(
        value: _bloodGroup,
        decoration: const InputDecoration(labelText: 'রক্তের গ্রুপ'),
        items: const ['A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-']
            .map((v) => DropdownMenuItem(value: v, child: Text(v)))
            .toList(),
        onChanged: _locked
            ? null
            : (v) => setState(() => _bloodGroup = v),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('উপবৃত্তি পায়'),
        value: _scholarship,
        onChanged: _locked ? null : (v) => setState(() => _scholarship = v),
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('শিক্ষার্থী প্রোফাইল')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
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
            const Divider(height: 32),
            const Text(
              'প্রোফাইল জমা হয়েছে। পরিবর্তন দরকার হলে অনুরোধ পাঠান।',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            TextField(
              controller: _reason,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'সংশোধনের কারণ'),
            ),
            TextField(
              controller: _changes,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'কোন তথ্য কীভাবে সংশোধন হবে',
              ),
            ),
            FilledButton(
              onPressed: _busy ? null : _request,
              child: const Text('সংশোধনের অনুরোধ পাঠান'),
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
