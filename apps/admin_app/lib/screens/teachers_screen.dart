import 'package:flutter/material.dart';

import '../api.dart';
import '../pdf/admin_pdfs.dart';
import '../pdf/app_pdf.dart';

class TeachersScreen extends StatefulWidget {
  const TeachersScreen({super.key});
  @override
  State<TeachersScreen> createState() => _TeachersScreenState();
}

class _TeachersScreenState extends State<TeachersScreen> {
  List _rows = [];
  List _subjects = [];
  List _classes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    try {
      final results = await Future.wait([
        Api.get('/admin/teachers'),
        Api.get('/admin/subjects'),
        Api.get('/admin/classes'),
      ]);
      setState(() {
        _rows = results[0] ?? [];
        _subjects = results[1] ?? [];
        _classes = results[2] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _toggleActive(dynamic t, bool active) async {
    try {
      await Api.put('/admin/teachers/${t['id']}/active', {'active': active});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            active
                ? '${t['name']}-কে সক্রিয় করা হলো'
                : '${t['name']}-কে নিষ্ক্রিয় করা হলো',
          ),
          backgroundColor: Colors.green,
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _printTeacherRoster() async {
    try {
      final settings = await Api.get('/admin/settings');
      final rows = _rows.whereType<Map>().map((row) => Map.from(row)).toList();
      final bytes = await AdminPdfs.teacherRoster(
        rows,
        settings: settings is Map ? settings : const {},
      );
      await AppPdf.preview(bytes);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _manageDesignations() async {
    final teachers = _rows
        .where((t) => t['active'] == 1 || t['active'] == true)
        .toList();
    final senior = <int>{
      for (final t in teachers.where(
        (t) => '${t['designation']}'.trim().toLowerCase() == 'senior teacher',
      ))
        int.parse('${t['id']}'),
    };
    final assistants = <int>{
      for (final t in teachers.where(
        (t) =>
            '${t['designation']}'.trim().toLowerCase() == 'assistant teacher',
      ))
        int.parse('${t['id']}'),
    };
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final usedIds = <int>{
            for (final t in teachers.where((t) {
              final role = '${t['designation']}'.trim().toLowerCase();
              return ['head teacher', 'headmaster', 'principal', 'assistant head teacher', 'assistant headmaster', 'vice principal'].contains(role);
            }))
              int.parse('${t['id']}'),
            ...senior,
            ...assistants,
          };
          Widget multiRole(String label, Set<int> selected, String key) =>
              ExpansionTile(
                title: Text('$label (${selected.length})'),
                initiallyExpanded: true,
                children: teachers.map((t) {
                  final id = int.parse('${t['id']}');
                  final isSelected = selected.contains(id);
                  final heldElsewhere = usedIds.contains(id) && !isSelected;
                  return CheckboxListTile(
                    dense: true,
                    value: isSelected,
                    title: Text('${t['name']}'),
                    subtitle: heldElsewhere
                        ? Text('${t['designation']} পদে আছেন')
                        : null,
                    onChanged: heldElsewhere
                        ? null
                        : (v) => setDialog(() {
                            if (v == true)
                              selected.add(id);
                            else
                              selected.remove(id);
                          }),
                  );
                }).toList(),
              );
          return AlertDialog(
            title: const Text('শিক্ষক পদবি নির্ধারণ'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    multiRole('Senior Teacher — একাধিক', senior, 'senior'),
                    multiRole(
                      'Assistant Teacher — একাধিক',
                      assistants,
                      'assistant',
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('বাতিল'),
              ),
              FilledButton(
                onPressed: () async {
                  try {
                    await Api.put('/admin/leadership-assignments', {
                      'senior_teacher_ids': senior.toList(),
                      'assistant_teacher_ids': assistants.toList(),
                    });
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    await _load();
                    if (mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('শিক্ষকদের পদবি সংরক্ষণ হয়েছে'),
                        ),
                      );
                  } catch (e) {
                    if (ctx.mounted)
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: Text(
                            e.toString().replaceFirst('Exception: ', ''),
                          ),
                        ),
                      );
                  }
                },
                child: const Text('সংরক্ষণ'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _assignSubjects(dynamic t) async {
    final picked = <int>{
      for (final s in _subjects.where((s) => s['teacher_id'] == t['id']))
        s['id'] as int,
    };
    String? clsName;
    String? sec;

    final sheetCtx = context;
    await showModalBottomSheet(
      context: sheetCtx,
      isScrollControlled: true,
      isDismissible: false,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: StatefulBuilder(
            builder: (context, setSheet) {
              final classNames = _subjects
                  .map((s) => '${s['class_name']}')
                  .toSet()
                  .toList();
              final subsRows = _subjects
                  .where((s) => '${s['class_name']}' == clsName)
                  .toList();
              final isGroup = subsRows.any(
                (s) => (s['group_name']?.toString() ?? '').isNotEmpty,
              );
              final secOpts = isGroup
                  ? subsRows
                        .map((s) => s['group_name']?.toString() ?? '')
                        .where((v) => v.isNotEmpty)
                        .toSet()
                        .toList()
                  : subsRows
                        .map((s) => s['section']?.toString() ?? '')
                        .where((v) => v.isNotEmpty)
                        .toSet()
                        .toList();
              final classSubjects = subsRows
                  .where(
                    (s) =>
                        (isGroup
                            ? s['group_name']?.toString()
                            : s['section']?.toString()) ==
                        sec,
                  )
                  .toList();

              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${t['name']} — subject assign করুন',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      initialValue: clsName,
                      decoration: const InputDecoration(
                        labelText: 'Step 1 — Class',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final n in classNames)
                          DropdownMenuItem(value: n, child: Text(n)),
                      ],
                      onChanged: (v) => setSheet(() {
                        clsName = v;
                        sec = null;
                      }),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String?>(
                      initialValue: sec,
                      decoration: InputDecoration(
                        labelText: isGroup
                            ? 'Step 2 — Group'
                            : 'Step 2 — Section',
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        for (final s in secOpts)
                          DropdownMenuItem(value: s, child: Text(s)),
                      ],
                      onChanged: (v) => setSheet(() => sec = v),
                    ),
                    if (clsName != null && sec != null && classSubjects.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'এই class/section-এ কোনো subject নেই।',
                          style: TextStyle(fontSize: 12, color: Colors.orange),
                        ),
                      ),
                    ...classSubjects.map((s) {
                      final checked = picked.contains(s['id']);
                      final otherTeacher =
                          s['teacher_name'] != null &&
                          s['teacher_id'] != t['id'];
                      return CheckboxListTile(
                        dense: true,
                        title: Text('${s['name']}'),
                        subtitle: otherTeacher
                            ? Text(
                                '→ ${s['teacher_name']}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.orange,
                                ),
                              )
                            : null,
                        value: checked,
                        onChanged: (v) => setSheet(() {
                          if (v == true) {
                            picked.add(s['id'] as int);
                          } else {
                            picked.remove(s['id'] as int);
                          }
                        }),
                      );
                    }),
                    const SizedBox(height: 12),
                    Text(
                      'Selected: ${picked.length} subjects',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: () async {
                        final navCtx = sheetCtx;
                        try {
                          for (final s in _subjects) {
                            final should = picked.contains(s['id']);
                            final isAssigned = s['teacher_id'] == t['id'];
                            if (should == isAssigned) continue;
                            await Api.put('/admin/subjects/${s['id']}', {
                              'name': s['name'],
                              'class_id': s['class_id'],
                              'teacher_id': should ? t['id'] : null,
                              'full_marks': s['full_marks'] ?? 100,
                              'group_name': s['group_name'] ?? 'Compulsory',
                              'is_optional': s['is_optional'],
                              'excluded_from_gpa': s['excluded_from_gpa'],
                              'cq_full': s['cq_full'],
                              'mcq_full': s['mcq_full'],
                              'practical_full': s['practical_full'],
                              'subject_code': s['subject_code'],
                              'is_fourth_subject': s['is_fourth_subject'],
                              'is_elective': s['is_elective'],
                              'sort_order': s['sort_order'],
                            });
                          }
                          if (!navCtx.mounted) return;
                          Navigator.pop(navCtx);
                          ScaffoldMessenger.of(navCtx).showSnackBar(
                            const SnackBar(
                              content: Text('Subject assignment updated'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          _load();
                        } catch (e) {
                          if (!navCtx.mounted) return;
                          ScaffoldMessenger.of(navCtx).showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.red,
                              content: Text(
                                e.toString().replaceFirst('Exception: ', ''),
                              ),
                            ),
                          );
                        }
                      },
                      child: const Text('Save Assignment'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _assignClassTeacher(dynamic t) async {
    final picked = Set<int>.from(
      (t['class_teacher_ids'] ?? []).map((e) => (e as num).toInt()),
    );
    String? clsName;
    String? sec;

    final ctCtx = context;
    await showModalBottomSheet(
      context: ctCtx,
      isScrollControlled: true,
      isDismissible: false,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctCtx).viewInsets.bottom,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: StatefulBuilder(
            builder: (context, setSheet) {
              final classNames = _classes
                  .map((c) => '${c['name']}')
                  .toSet()
                  .toList();
              final rows = _classes.where((c) => c['name'] == clsName).toList();
              final isGroup = rows.any(
                (c) => (c['group_name']?.toString() ?? '').isNotEmpty,
              );
              final secOpts = isGroup
                  ? rows
                        .map((c) => c['group_name'].toString())
                        .where((v) => v.isNotEmpty)
                        .toSet()
                        .toList()
                  : rows.map((c) => c['section'].toString()).toSet().toList();
              final selRow = rows.isEmpty
                  ? null
                  : rows.firstWhere(
                      (c) =>
                          (isGroup ? c['group_name'] : c['section'])
                              .toString() ==
                          sec,
                      orElse: () => null,
                    );
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${t['name']} — class teacher assign করুন',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      initialValue: clsName,
                      decoration: const InputDecoration(
                        labelText: 'Step 1 — Class',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final n in classNames)
                          DropdownMenuItem(value: n, child: Text(n)),
                      ],
                      onChanged: (v) => setSheet(() {
                        clsName = v;
                        sec = null;
                      }),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String?>(
                      initialValue: sec,
                      decoration: InputDecoration(
                        labelText: isGroup
                            ? 'Step 2 — Group'
                            : 'Step 2 — Section',
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        for (final s in secOpts)
                          DropdownMenuItem(value: s, child: Text(s)),
                      ],
                      onChanged: (v) => setSheet(() => sec = v),
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: selRow == null
                          ? null
                          : () => setSheet(() {
                              final id = selRow['id'] as int;
                              if (!picked.contains(id)) picked.add(id);
                              sec = null;
                            }),
                      child: const Text('+ Assign'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'নির্বাচিত (${picked.length}):',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: picked.map((id) {
                        final c = _classes
                            .cast<dynamic>()
                            .where((x) => x['id'] == id)
                            .toList();
                        final label = c.isEmpty
                            ? '#$id'
                            : '${c.first['name']} (${(c.first['group_name']?.toString() ?? '') == '' ? c.first['section'] : c.first['group_name']})';
                        return Chip(
                          label: Text(
                            label,
                            style: const TextStyle(fontSize: 12),
                          ),
                          backgroundColor: Colors.green.shade50,
                          visualDensity: VisualDensity.compact,
                          onDeleted: () => setSheet(() => picked.remove(id)),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () async {
                        final navCtx2 = ctCtx;
                        try {
                          await Api.put('/admin/teachers/${t['id']}', {
                            'name': t['name'],
                            'username': t['username'],
                            'class_teacher': picked.toList(),
                          });
                          if (!navCtx2.mounted) return;
                          Navigator.pop(navCtx2);
                          ScaffoldMessenger.of(navCtx2).showSnackBar(
                            const SnackBar(
                              content: Text('Class teacher assignment updated'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          _load();
                        } catch (e) {
                          if (!navCtx2.mounted) return;
                          ScaffoldMessenger.of(navCtx2).showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.red,
                              content: Text(
                                e.toString().replaceFirst('Exception: ', ''),
                              ),
                            ),
                          );
                        }
                      },
                      child: const Text('Save Class Assignment'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _showForm([dynamic t]) {
    final name = TextEditingController(text: t?['name'] ?? '');
    final username = TextEditingController(text: t?['username'] ?? '');
    final password = TextEditingController();
    final phone = TextEditingController(text: t?['phone'] ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t == null ? 'Add Teacher (creates login)' : 'Edit Teacher',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: name,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: username,
                decoration: const InputDecoration(
                  labelText: 'Login ID *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: t == null
                      ? 'Password *'
                      : 'New Password (blank = keep)',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  try {
                    if (t == null) {
                      await Api.post('/admin/teachers', {
                        'name': name.text.trim(),
                        'username': username.text.trim(),
                        'password': password.text,
                        'phone': phone.text.trim(),
                      });
                    } else {
                      final body = <String, dynamic>{
                        'name': name.text.trim(),
                        'username': username.text.trim(),
                        'phone': phone.text.trim(),
                      };
                      if (password.text.isNotEmpty)
                        body['password'] = password.text;
                      await Api.put('/admin/teachers/${t['id']}', body);
                    }
                    if (!mounted) return;
                    Navigator.pop(context);
                    _load();
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: Colors.red,
                        content: Text(
                          e.toString().replaceFirst('Exception: ', ''),
                        ),
                      ),
                    );
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teachers'),
        actions: [
          IconButton(
            onPressed: _rows.isEmpty ? null : _printTeacherRoster,
            tooltip: 'শিক্ষক স্বাক্ষর তালিকা PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
          IconButton(
            onPressed: _manageDesignations,
            tooltip: 'পদবি নির্ধারণ',
            icon: const Icon(Icons.assignment_ind_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _rows.length,
                itemBuilder: (_, i) {
                  final t = _rows[i];
                  final subjectCount = _subjects
                      .where((s) => s['teacher_id'] == t['id'])
                      .length;
                  final ctIds = Set<int>.from(
                    (t['class_teacher_ids'] ?? []).map(
                      (e) => (e as num).toInt(),
                    ),
                  );
                  final ctCount = ctIds.length;
                  return Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.person),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  t['name'],
                                  style: TextStyle(
                                    color: t['active'] == 1
                                        ? null
                                        : Colors.grey,
                                    decoration: t['active'] == 1
                                        ? null
                                        : TextDecoration.lineThrough,
                                  ),
                                ),
                              ),
                              if (t['active'] != 1)
                                Chip(
                                  label: const Text(
                                    'Inactive',
                                    style: TextStyle(fontSize: 10),
                                  ),
                                  backgroundColor: Colors.red.shade100,
                                ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ID: ${t['username']} • ${t['phone'] ?? '-'}',
                              ),
                              if ('${t['designation'] ?? ''}'.trim().isNotEmpty)
                                Text(
                                  'পদবি: ${t['designation']}',
                                  style: TextStyle(
                                    color: Colors.indigo.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              Text(
                                'Subjects: $subjectCount • Class Teacher: $ctCount classes',
                              ),
                              if (ctCount > 0)
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 2,
                                  children: (t['class_teacher'] ?? []).map<Widget>((
                                    ct,
                                  ) {
                                    return Chip(
                                      label: Text(
                                        '${ct['class'] ?? ''} ${ct['group'] ?? ct['section'] ?? ''}',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      backgroundColor: Colors.green.shade50,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                    );
                                  }).toList(),
                                ),
                            ],
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _showForm(t),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.menu_book, size: 18),
                                  label: const Text('Assign Subjects'),
                                  onPressed: () => _assignSubjects(t),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.school, size: 18),
                                  label: const Text('Assign Class'),
                                  onPressed: () => _assignClassTeacher(t),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              const Spacer(),
                              Switch(
                                value: t['active'] == 1,
                                activeThumbColor: Colors.green,
                                onChanged: (v) => _toggleActive(t, v),
                              ),
                              Text(t['active'] == 1 ? 'Active' : 'Inactive'),
                            ],
                          ),
                        ),
                        const Divider(),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}
