import 'package:flutter/material.dart';

import '../api.dart';

class ClassesScreen extends StatefulWidget {
  const ClassesScreen({super.key});

  @override
  State<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends State<ClassesScreen> {
  List _rows = [];
  List _teachers = [];
  bool _loading = true;
  bool _teachersLoading = true;
  String? _error;
  String? _teacherError;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    _loadTeachers();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final response = await Api.get('/admin/classes');
      if (!mounted) return;
      if (response is! List) throw Exception('Class list response is invalid.');
      setState(() {
        _rows = response;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _loadTeachers() async {
    if (mounted) {
      setState(() {
        _teachersLoading = true;
        _teacherError = null;
      });
    }
    try {
      final response = await Api.get('/admin/teachers');
      if (!mounted) return;
      if (response is! List) {
        throw Exception('Teacher list response is invalid.');
      }
      setState(() {
        _teachers = response;
        _teachersLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _teacherError = e.toString().replaceFirst('Exception: ', '');
        _teachersLoading = false;
      });
    }
  }

  int _classLevel(String value) =>
      int.tryParse(RegExp(r'\d+').firstMatch(value)?.group(0) ?? '') ?? 0;

  bool _validGroup(String value) {
    final group = value.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    return const {
      'arts',
      'humanities',
      'humanity',
      'science',
      'commerce',
      'business',
      'businessstudies',
    }.contains(group);
  }

  Future<void> _showForm([dynamic existing]) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = TextEditingController(text: existing?['name'] ?? '');
    final section = TextEditingController(text: existing?['section'] ?? '');
    final group = TextEditingController(text: existing?['group_name'] ?? '');
    int? teacherId = int.tryParse('${existing?['teacher_id'] ?? ''}');
    bool saving = false;

    final response = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) {
          final seniorClass = [9, 10].contains(_classLevel(name.text));
          final knownTeacherIds = _teachers
              .map((teacher) => int.tryParse('${teacher['id']}'))
              .whereType<int>()
              .toSet();
          final teacherItems = <DropdownMenuItem<int?>>[
            const DropdownMenuItem<int?>(value: null, child: Text('— None —')),
            if (teacherId != null && !knownTeacherIds.contains(teacherId))
              DropdownMenuItem<int?>(
                value: teacherId,
                child: Text('Current teacher #$teacherId (not in list)'),
              ),
            ..._teachers
                .map((teacher) {
                  final id = int.tryParse('${teacher['id']}');
                  return DropdownMenuItem<int?>(
                    value: id,
                    child: Text('${teacher['name'] ?? 'Unnamed teacher'}'),
                  );
                })
                .where((item) => item.value != null),
          ];

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      existing == null ? 'Add Class' : 'Edit Class',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: name,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => setSheet(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Class Name *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: section,
                      decoration: const InputDecoration(
                        labelText: 'Section *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: group,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: seniorClass
                            ? 'Academic Group *'
                            : 'Academic Group',
                        helperText: seniorClass
                            ? 'Use Arts/Humanities, Science, or Commerce/Business.'
                            : 'Keeps any existing stream/group information.',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_teachersLoading)
                      const LinearProgressIndicator()
                    else if (_teacherError != null) ...[
                      Text(
                        'Teacher list could not load. An existing assignment will be preserved unless changed.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _loadTeachers,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry teacher list'),
                      ),
                    ] else
                      DropdownButtonFormField<int?>(
                        initialValue: teacherId,
                        decoration: const InputDecoration(
                          labelText: 'Class Teacher (attendance and marksheet)',
                          border: OutlineInputBorder(),
                        ),
                        items: teacherItems,
                        onChanged: saving
                            ? null
                            : (value) => setSheet(() => teacherId = value),
                      ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: saving
                          ? null
                          : () async {
                              final className = name.text.trim();
                              final sectionName = section.text.trim();
                              final groupName = group.text.trim();
                              final level = _classLevel(className);
                              if (className.isEmpty || sectionName.isEmpty) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Class name and section are required.',
                                    ),
                                  ),
                                );
                                return;
                              }
                              if ([9, 10].contains(level) &&
                                  !_validGroup(groupName)) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Class 9–10 needs a valid Arts, Science, or Commerce group.',
                                    ),
                                  ),
                                );
                                return;
                              }
                              setSheet(() => saving = true);
                              try {
                                final body = {
                                  'name': className,
                                  'section': sectionName,
                                  'group_name': groupName.isEmpty
                                      ? null
                                      : groupName,
                                  'teacher_id': teacherId,
                                };
                                final result = existing == null
                                    ? await Api.post('/admin/classes', body)
                                    : await Api.put(
                                        '/admin/classes/${existing['id']}',
                                        body,
                                      );
                                if (!sheetContext.mounted || !mounted) {
                                  return;
                                }
                                Navigator.pop(sheetContext, result);
                              } catch (e) {
                                if (sheetContext.mounted) {
                                  setSheet(() => saving = false);
                                }
                                if (!mounted) return;
                                await _load();
                                if (!mounted) return;
                                final detail = e.toString().replaceFirst(
                                  'Exception: ',
                                  '',
                                );
                                final message = detail == 'Server error'
                                    ? 'Server reported an error. The class list was refreshed; check it before retrying.'
                                    : detail;
                                messenger.showSnackBar(
                                  SnackBar(
                                    backgroundColor: Colors.red,
                                    content: Text(message),
                                  ),
                                );
                              }
                            },
                      child: saving
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text('Saving class…'),
                              ],
                            )
                          : const Text('Save Class'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    name.dispose();
    section.dispose();
    group.dispose();
    if (response == null || !mounted) return;
    await _load();
    if (!mounted) return;
    final offlineQueued = response is Map && response['offline_queued'] == true;
    final eventWarning =
        response is Map && response['event_sync_warning'] == true;
    final teacherWarning =
        response is Map && response['teacher_sync_warning'] == true;
    final message = offlineQueued
        ? 'No internet—class change is queued on this phone.'
        : eventWarning || teacherWarning
        ? 'Class saved; a linked exam/teacher sync needs review.'
        : existing == null
        ? 'Class added.'
        : 'Class updated.';
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final visible = _rows.where((row) {
      final text =
          '${row['name']} ${row['section']} ${row['group_name'] ?? ''} ${row['teacher_name'] ?? ''}'
              .toLowerCase();
      return text.contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Classes & Sections')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add Class'),
      ),
      body: _loading && _rows.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _rows.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 42),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                children: [
                  TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search class, section, group, or teacher',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_error != null)
                    MaterialBanner(
                      content: Text('Refresh failed: $_error'),
                      actions: [
                        TextButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  if (visible.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 56),
                      child: Center(
                        child: Text(
                          'No classes found. Add a class to get started.',
                        ),
                      ),
                    ),
                  for (final row in visible)
                    Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.meeting_room_outlined),
                        ),
                        title: Text(
                          '${row['name'] ?? 'Unnamed class'} · ${row['section'] ?? 'No section'}',
                        ),
                        subtitle: Text(
                          [
                            if ((row['group_name'] ?? '')
                                .toString()
                                .trim()
                                .isNotEmpty)
                              'Group: ${row['group_name']}',
                            'Class Teacher: ${row['teacher_name'] ?? 'Not assigned'}',
                            'Students: ${row['student_count'] ?? 0}',
                          ].join('  •  '),
                        ),
                        trailing: IconButton(
                          tooltip: 'Edit class',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _showForm(row),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
