import 'package:flutter/material.dart';

import '../api.dart';

class StudentProfileScreen extends StatefulWidget {
  final int studentId;
  final String studentName;
  const StudentProfileScreen({
    super.key,
    required this.studentId,
    required this.studentName,
  });
  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen> {
  Map? _data;
  String? _error;
  bool _savingProfile = false;
  List<String> _genders = ['Male', 'Female', 'Other'];
  List<String> _bloodGroups = [
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-',
    'Unknown',
  ];
  @override
  void initState() {
    super.initState();
    _load();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    try {
      final r = await Api.get('/teacher/meta/options');
      if (!mounted) return;
      if (r is Map) {
        setState(() {
          if (r['genders'] is List && (r['genders'] as List).isNotEmpty) {
            _genders = (r['genders'] as List)
                .where((e) => e != null)
                .map((e) => e.toString())
                .toList();
          }
          if (r['bloodGroups'] is List &&
              (r['bloodGroups'] as List).isNotEmpty) {
            _bloodGroups = (r['bloodGroups'] as List)
                .where((e) => e != null)
                .map((e) => e.toString())
                .toList();
          }
        });
      }
    } catch (_) {
      // keep defaults on failure
    }
  }

  Future<void> _load() async {
    if (mounted) setState(() => _error = null);
    try {
      final r = await Api.get(
        '/teacher/students/${widget.studentId}/profile-history',
      );
      if (mounted) setState(() => _data = r is Map ? r : {});
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Future<void> _editIdentityAndSubjects(Map<String, dynamic> student) async {
    final birth = TextEditingController(
      text: '${student['birth_cert_no'] ?? ''}',
    );
    final group = '${student['group_name'] ?? student['section'] ?? ''}'
        .toLowerCase();
    final arts = group.contains('arts') || group.contains('humanit');
    final science = group.contains('science');
    final level =
        int.tryParse(
          RegExp(r'\d+')
                  .firstMatch('${student['class_name'] ?? ''}')
                  ?.group(0) ??
              '0',
        ) ??
        0;
    final senior = level == 9 || level == 10;
    String? compulsory = student['compulsory_subject']?.toString();
    String? optional = student['optional_subject']?.toString();
    final optionalOptions = science
        ? const ['Higher Mathematics', 'Agriculture', 'Home Science']
        : const ['Agriculture', 'Home Science'];
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('শিক্ষার্থীর profile update'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: birth,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'জন্মনিবন্ধন নম্বর *',
                    helperText:
                        student['birth_cert_placeholder'] == true ||
                            student['birth_cert_placeholder'] == 1
                        ? 'এটি অস্থায়ী নম্বর—আসল নম্বর দিয়ে বদলান'
                        : null,
                  ),
                ),
                if (senior && arts) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: compulsory,
                    decoration: const InputDecoration(
                      labelText: 'Compulsory: Civics/Economics *',
                    ),
                    items: const ['Civics', 'Economics']
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: (v) => setDialog(() => compulsory = v),
                  ),
                ],
                if (senior) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: optional,
                    decoration: const InputDecoration(
                      labelText: 'Optional subject *',
                    ),
                    items: optionalOptions
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: (v) => setDialog(() => optional = v),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('বাতিল'),
            ),
            FilledButton(
              onPressed: () {
                if (birth.text.trim().isEmpty ||
                    (senior && optional == null) ||
                    (senior && arts && compulsory == null)) {
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('সংরক্ষণ'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    if (mounted) {
      setState(() => _savingProfile = true);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            duration: Duration(minutes: 1),
            content: Text('শিক্ষার্থীর তথ্য আপডেট হচ্ছে…'),
          ),
        );
    }
    try {
      final result = await Api.put('/teacher/students/${widget.studentId}', {
        'birth_cert_no': birth.text.trim(),
        if (senior) 'optional_subject': optional,
        if (senior && arts) 'compulsory_subject': compulsory,
      });
      await _load();
      if (mounted) {
        final offlineQueued = result is Map && result['offline_queued'] == true;
        final auditWarning = result is Map && result['audit_logged'] == false;
        final message = offlineQueued
            ? 'ইন্টারনেট নেই—তথ্য ফোনে রাখা হয়েছে; সংযোগ এলে পাঠানো হবে।'
            : auditWarning
            ? 'তথ্য সংরক্ষিত হয়েছে, তবে audit history সংরক্ষণ হয়নি। Admin-কে জানান।'
            : 'Student profile সংরক্ষণ হয়েছে';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      await _load();
      if (mounted) {
        final detail = e.toString().replaceFirst('Exception: ', '');
        final message = detail == 'Server error'
            ? 'Server update ব্যর্থ। আবার চেষ্টা করার আগে profile refresh করে দেখুন—তথ্য সংরক্ষিত হয়ে থাকতে পারে।'
            : detail;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _editFullProfile(Map<String, dynamic> student) async {
    final fields = <String, TextEditingController>{
      'name': TextEditingController(text: '${student['name'] ?? ''}'),
      'dob': TextEditingController(
        text: '${student['dob'] ?? ''}'.split('T').first,
      ),
      'gender': TextEditingController(text: '${student['gender'] ?? ''}'),
      'religion': TextEditingController(text: '${student['religion'] ?? ''}'),
      'blood_group': TextEditingController(
        text: '${student['blood_group'] ?? ''}',
      ),
      'phone': TextEditingController(text: '${student['phone'] ?? ''}'),
      'email': TextEditingController(text: '${student['email'] ?? ''}'),
      'father_name': TextEditingController(
        text: '${student['father_name'] ?? ''}',
      ),
      'mother_name': TextEditingController(
        text: '${student['mother_name'] ?? ''}',
      ),
      'guardian_name': TextEditingController(
        text: '${student['guardian_name'] ?? ''}',
      ),
      'guardian_phone': TextEditingController(
        text: '${student['guardian_phone'] ?? ''}',
      ),
      'guardian_email': TextEditingController(
        text: '${student['guardian_email'] ?? ''}',
      ),
      'birth_cert_no': TextEditingController(
        text: '${student['birth_cert_no'] ?? ''}',
      ),
      'address': TextEditingController(text: '${student['address'] ?? ''}'),
    };
    bool scholarship =
        student['receives_scholarship'] == true ||
        student['receives_scholarship'] == 1;

    // ensure current values exist in dropdown lists
    final genderList = List<String>.from(_genders);
    final currentGender = fields['gender']!.text.trim();
    if (currentGender.isNotEmpty && !genderList.contains(currentGender)) {
      genderList.add(currentGender);
    }

    final bloodList = List<String>.from(_bloodGroups);
    final currentBlood = fields['blood_group']!.text.trim();
    if (currentBlood.isNotEmpty && !bloodList.contains(currentBlood)) {
      bloodList.add(currentBlood);
    }

    String? selectedGender = currentGender.isEmpty ? null : currentGender;
    String? selectedBlood = currentBlood.isEmpty ? null : currentBlood;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('শিক্ষার্থীর সম্পূর্ণ তথ্য সম্পাদনা'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'কোড: ${student['student_code'] ?? '—'} · '
                      'শ্রেণি: ${student['class_name'] ?? '—'} '
                      '${student['section'] ?? ''} · '
                      'রোল: ${student['roll'] ?? '—'} · '
                      'শিক্ষাবর্ষ: ${student['session_name'] ?? '—'}\n'
                      'শ্রেণি, রোল ও শিক্ষাবর্ষ এখানে read-only।',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  _editField(fields['name']!, 'শিক্ষার্থীর নাম *'),
                  _editField(fields['dob']!, 'জন্ম তারিখ (YYYY-MM-DD)'),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 11),
                    child: DropdownButtonFormField<String>(
                      initialValue: selectedGender,
                      decoration: const InputDecoration(
                        labelText: 'লিঙ্গ',
                        border: OutlineInputBorder(),
                      ),
                      items: genderList
                          .map(
                            (e) => DropdownMenuItem<String>(
                              value: e,
                              child: Text(e),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        setDialog(() {
                          selectedGender = v;
                          fields['gender']!.text = v ?? '';
                        });
                      },
                    ),
                  ),
                  _editField(fields['religion']!, 'ধর্ম'),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 11),
                    child: DropdownButtonFormField<String>(
                      initialValue: selectedBlood,
                      decoration: const InputDecoration(
                        labelText: 'রক্তের গ্রুপ',
                        border: OutlineInputBorder(),
                      ),
                      items: bloodList
                          .map(
                            (e) => DropdownMenuItem<String>(
                              value: e,
                              child: Text(e),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        setDialog(() {
                          selectedBlood = v;
                          fields['blood_group']!.text = v ?? '';
                        });
                      },
                    ),
                  ),
                  _editField(fields['father_name']!, 'পিতার নাম'),
                  _editField(fields['mother_name']!, 'মাতার নাম'),
                  _editField(fields['guardian_name']!, 'অভিভাবকের নাম'),
                  _editField(
                    fields['guardian_phone']!,
                    'অভিভাবকের ফোন',
                    type: TextInputType.phone,
                  ),
                  _editField(
                    fields['guardian_email']!,
                    'অভিভাবকের ইমেইল',
                    type: TextInputType.emailAddress,
                  ),
                  _editField(
                    fields['phone']!,
                    'শিক্ষার্থীর ফোন',
                    type: TextInputType.phone,
                  ),
                  _editField(
                    fields['email']!,
                    'শিক্ষার্থীর ইমেইল',
                    type: TextInputType.emailAddress,
                  ),
                  _editField(
                    fields['birth_cert_no']!,
                    'জন্মনিবন্ধন নম্বর *',
                    type: TextInputType.number,
                  ),
                  _editField(fields['address']!, 'ঠিকানা', maxLines: 2),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('উপবৃত্তি পায়'),
                    value: scholarship,
                    onChanged: (value) => setDialog(() => scholarship = value),
                  ),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'রোল ও শ্রেণি পরিবর্তন এই ফর্মে করা যাবে না।',
                      style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('বাতিল'),
            ),
            FilledButton(
              onPressed: () {
                if (fields['name']!.text.trim().isEmpty ||
                    fields['birth_cert_no']!.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('সব তথ্য সংরক্ষণ'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      final payload = <String, dynamic>{
        for (final entry in fields.entries) entry.key: entry.value.text.trim(),
        'receives_scholarship': scholarship,
      };
      await _saveProfileChanges(payload);
    }
    for (final controller in fields.values) {
      controller.dispose();
    }
  }

  Widget _editField(
    TextEditingController controller,
    String label, {
    TextInputType? type,
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: TextField(
      controller: controller,
      keyboardType: type,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  Future<void> _saveProfileChanges(Map<String, dynamic> payload) async {
    setState(() => _savingProfile = true);
    try {
      final result = await Api.put(
        '/teacher/students/${widget.studentId}',
        payload,
      );
      await _load();
      if (!mounted) return;
      final offlineQueued = result is Map && result['offline_queued'] == true;
      final auditWarning = result is Map && result['audit_logged'] == false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            offlineQueued
                ? 'ইন্টারনেট নেই—তথ্য ফোনে রাখা হয়েছে; সংযোগ এলে পাঠানো হবে।'
                : auditWarning
                ? 'তথ্য সংরক্ষিত হয়েছে, তবে audit history সংরক্ষণ হয়নি। Admin-কে জানান।'
                : 'শিক্ষার্থীর সব তথ্য সংরক্ষণ হয়েছে',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.studentName),
      actions: [
        if (_data?['student'] is Map)
          IconButton(
            tooltip: 'শিক্ষার্থীর সম্পূর্ণ profile সম্পাদনা',
            icon: _savingProfile
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.edit_outlined),
            onPressed: _savingProfile
                ? null
                : () => _editFullProfile(
                    Map<String, dynamic>.from(_data!['student'] as Map),
                  ),
          ),
      ],
    ),
    body: _data == null
        ? Center(
            child: _error == null
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
                      FilledButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('আবার চেষ্টা করুন'),
                      ),
                    ],
                  ),
          )
        : RefreshIndicator(onRefresh: _load, child: _body()),
  );

  Widget _body() {
    final data = _data!;
    final student = Map<String, dynamic>.from(data['student'] as Map? ?? {});
    final attendance = Map<String, dynamic>.from(
      data['attendance'] as Map? ?? {},
    );
    final reports = data['daily_reports'] as List? ?? [];
    final uniformReports = data['uniform_reports'] as List? ?? [];
    final complaints = data['complaints'] as List? ?? [];
    final repeats = data['repeated_classes'] as List? ?? [];
    final scholarship =
        student['receives_scholarship'] == true ||
        student['receives_scholarship'] == 1;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF27396F), Color(0xFF6657D9)],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${student['name'] ?? widget.studentName}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${student['class_name'] ?? ''} (${student['section'] ?? ''})  ·  Roll ${student['roll'] ?? '—'}',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _pill('উপস্থিত ${attendance['attended_days'] ?? 0} দিন'),
                  _pill('অনুপস্থিত ${attendance['absent_days'] ?? 0} দিন'),
                  if (data['irregular'] == true) _pill('অনিয়মিত শিক্ষার্থী'),
                  _pill(
                    'Uniform আনেনি ${data['uniform_missing_reports'] ?? 0} বার',
                  ),
                  if (scholarship) _pill('উপবৃত্তি পায়'),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _savingProfile
                      ? null
                      : () => _editIdentityAndSubjects(student),
                  icon: const Icon(
                    Icons.menu_book_outlined,
                    color: Colors.white,
                  ),
                  label: const Text(
                    'জন্মনিবন্ধন ও বিষয়ের পছন্দ সম্পাদনা করুন',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _profileDetails(student),
        const SizedBox(height: 12),
        if (repeats.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'একই শ্রেণিতে থাকার ইতিহাস',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  for (final r in repeats)
                    if (r is Map)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.history,
                          color: Colors.orange,
                        ),
                        title: Text(
                          '${r['from_class'] ?? 'শ্রেণি'} → ${r['to_class'] ?? 'একই শ্রেণি'}',
                        ),
                        subtitle: Text(
                          '${r['decision'] ?? ''}  ·  ${r['passing_year'] ?? ''}',
                        ),
                      ),
                ],
              ),
            ),
          ),
        _section(
          'তারিখভিত্তিক পড়া ও performance',
          reports,
          (r) =>
              '${r['report_date']} · ${r['subject_name']}\nপড়া: ${r['homework_status'] == 'done' ? 'করেছে' : 'করেনি'}  ·  শেখা: ${r['learning_status']}  ·  performance: ${r['performance']}${(r['note'] ?? '').toString().isEmpty ? '' : '\nনোট: ${r['note']}'}',
        ),
        _section(
          'Uniform report — মোট ${data['uniform_missing_reports'] ?? 0} দিন আনেনি',
          uniformReports,
          (r) => '${r['report_date']} · ${r['uniform_brought'] == true || r['uniform_brought'] == 1 ? 'Uniform এনেছে' : 'Uniform আনেনি'}${(r['note'] ?? '').toString().trim().isEmpty ? '' : '\n${r['note']}'}',
        ),
        _section(
          'শিক্ষকদের অভিযোগ',
          complaints,
          (r) =>
              '${r['title']}\n${r['teacher_name'] ?? ''}  ·  ${r['created_at'] ?? ''}\n${r['body'] ?? ''}',
        ),
      ],
    );
  }

  Widget _profileDetails(Map<String, dynamic> student) {
    String display(dynamic value) {
      if (value == null || value.toString().trim().isEmpty) {
        return 'তথ্য যোগ করা হয়নি';
      }
      return value is DateTime
          ? value.toIso8601String().split('T').first
          : value.toString().split('T').first;
    }

    String yesNo(dynamic value) => value == true || value == 1 ? 'হ্যাঁ' : 'না';
    final temporaryBirthNumber =
        student['birth_cert_placeholder'] == true ||
        student['birth_cert_placeholder'] == 1;
    final details = <(String, String)>[
      ('শিক্ষার্থী কোড', display(student['student_code'])),
      (
        'শ্রেণি ও শাখা',
        '${display(student['class_name'])} · ${display(student['section'])}',
      ),
      ('রোল', display(student['roll'])),
      ('শিক্ষাবর্ষ', display(student['session_name'])),
      ('অবস্থা', display(student['status'])),
      (
        'ছবি',
        student['photo'] == null || student['photo'].toString().isEmpty
            ? 'ছবি যোগ করা হয়নি'
            : 'ছবি সংরক্ষিত আছে · admin থেকে আপডেটযোগ্য',
      ),
      ('জন্ম তারিখ', display(student['dob'])),
      ('লিঙ্গ', display(student['gender'])),
      ('ধর্ম', display(student['religion'])),
      ('রক্তের গ্রুপ', display(student['blood_group'])),
      ('পিতার নাম', display(student['father_name'])),
      ('মাতার নাম', display(student['mother_name'])),
      ('অভিভাবকের নাম', display(student['guardian_name'])),
      ('অভিভাবকের ফোন', display(student['guardian_phone'])),
      ('অভিভাবকের ইমেইল', display(student['guardian_email'])),
      ('শিক্ষার্থীর ফোন', display(student['phone'])),
      ('শিক্ষার্থীর ইমেইল', display(student['email'])),
      (
        'জন্মনিবন্ধন নম্বর',
        '${display(student['birth_cert_no'])}${temporaryBirthNumber ? ' · অস্থায়ী' : ''}',
      ),
      ('ঠিকানা', display(student['address'])),
      ('ঐচ্ছিক বিষয়', display(student['optional_subject'])),
      ('আবশ্যিক বিষয়', display(student['compulsory_subject'])),
      ('উপবৃত্তি পায়', yesNo(student['receives_scholarship'])),
    ];
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.badge_outlined),
        title: const Text('ডাটাবেজে সংরক্ষিত শিক্ষার্থীর তথ্য'),
        subtitle: const Text('ফাঁকা তথ্য যোগ বা সংশোধন করতে Edit চাপুন'),
        children: [
          for (final (label, value) in details)
            ListTile(
              dense: true,
              title: Text(
                label,
                style: const TextStyle(color: Colors.blueGrey),
              ),
              subtitle: SelectableText(value),
            ),
        ],
      ),
    );
  }

  Widget _pill(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .15),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
    ),
  );

  Widget _section(String title, List rows, String Function(Map) body) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'এখনো কোনো record নেই',
                style: TextStyle(color: Colors.blueGrey),
              ),
            ),
          for (final raw in rows)
            if (raw is Map)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_note_outlined),
                title: Text(body(Map.from(raw))),
                isThreeLine: true,
              ),
        ],
      ),
    ),
  );
}
