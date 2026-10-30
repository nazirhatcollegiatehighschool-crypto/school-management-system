import 'package:flutter/material.dart';

import '../api.dart';

String _slotDisplayName(String? raw) {
  final l = (raw ?? '').trim();
  final m = RegExp(r'^CLASS_(\d)$', caseSensitive: false).firstMatch(l);
  if (m != null) {
    const bn = <String, String>{
      '1': '\u09E7\u09AE',
      '2': '\u09E8\u09DF',
      '3': '\u09E9\u09DF',
      '4': '\u09EA\u09F0\u09CD\u09A5',
      '5': '\u09EB\u09AE',
      '6': '\u09EC\u09B7\u09CD\u09A0',
      '7': '\u09ED\u09AE',
    };
    return 'বিষয় ${bn[m.group(1)!] ?? m.group(1)} পিরিয়ড';
  }
  final lw = l.toLowerCase();
  if (lw == 'assembly') return 'সমাবেশ';
  if (lw == 'leisure') return 'অবসর';
  return raw?.toString() ?? '';
}

const _days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday'];

class RoutinesScreen extends StatefulWidget {
  const RoutinesScreen({super.key});
  @override
  State<RoutinesScreen> createState() => _RoutinesScreenState();
}

class _RoutinesScreenState extends State<RoutinesScreen> {
  List _routines = [];
  List _slots = [];
  List _teachers = [];
  List _classes = [];
  List _subjects = [];
  List _deleteRequests = [];
  bool _loading = true;
  String? _error;
  String? _filterTeacher;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        Api.get('/routine/all'),
        Api.get('/admin/classes'),
        Api.get('/admin/subjects'),
        Api.get('/routine/admin/delete-requests'),
      ]);
      final r = results[0];
      if (!mounted) return;
      setState(() {
        _routines = r['routines'] is List ? r['routines'] : [];
        _slots = r['slots'] is List ? r['slots'] : [];
        _teachers = r['teachers'] is List ? r['teachers'] : [];
        _classes = results[1] is List ? results[1] : [];
        _subjects = results[2] is List ? results[2] : [];
        _deleteRequests = results[3] is List ? results[3] : [];
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

  Future<List<String>?> _chooseReligions() async {
    final selected = <String>{};
    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('যে ধর্মের শিক্ষার্থীদের পড়াবেন নির্বাচন করুন'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final religion in const [
                'Islam',
                'Hinduism',
                'Buddhism',
                'Christianity',
              ])
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(religion),
                  value: selected.contains(religion),
                  onChanged: (v) => setDialog(() {
                    if (v == true) {
                      selected.add(religion);
                    } else {
                      selected.remove(religion);
                    }
                  }),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('বাতিল'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(ctx, selected.toList()),
              child: const Text('নিশ্চিত করুন'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createEntry() async {
    int? teacherId;
    String? clsName;
    String? sec;
    int? day;
    int? slotId;
    int? subjectId;

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
              final selRow = rows.cast<dynamic>().isNotEmpty
                  ? rows.firstWhere(
                      (c) =>
                          (isGroup ? c['group_name'] : c['section'])
                              .toString() ==
                          sec,
                      orElse: () => null,
                    )
                  : null;
              final classSubjects = selRow == null
                  ? <dynamic>[]
                  : _subjects
                        .where(
                          (s) =>
                              s['class_id'] == selRow['id'] &&
                              (teacherId == null ||
                                  s['teacher_id'] == teacherId),
                        )
                        .toList();

              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Add Routine Period — Step by Step',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int?>(
                      initialValue: teacherId,
                      decoration: const InputDecoration(
                        labelText: 'Step 1 — Teacher',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final t in _teachers)
                          DropdownMenuItem(
                            value: t['id'] as int,
                            child: Text('${t['name']}'),
                          ),
                      ],
                      onChanged: (v) => setSheet(() {
                        teacherId = v;
                        subjectId = null;
                      }),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String?>(
                      initialValue: clsName,
                      decoration: const InputDecoration(
                        labelText: 'Step 2 — Class',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final n in classNames)
                          DropdownMenuItem(value: n, child: Text(n)),
                      ],
                      onChanged: (v) => setSheet(() {
                        clsName = v;
                        sec = null;
                        subjectId = null;
                      }),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String?>(
                      initialValue: sec,
                      decoration: InputDecoration(
                        labelText: isGroup
                            ? 'Step 3 — Group'
                            : 'Step 3 — Section',
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        for (final s in secOpts)
                          DropdownMenuItem(value: s, child: Text(s)),
                      ],
                      onChanged: (v) => setSheet(() {
                        sec = v;
                        subjectId = null;
                      }),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int?>(
                      initialValue: day,
                      decoration: const InputDecoration(
                        labelText: 'Step 4 — Day',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (var i = 0; i < _days.length; i++)
                          DropdownMenuItem(value: i, child: Text(_days[i])),
                      ],
                      onChanged: (v) => setSheet(() => day = v),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int?>(
                      initialValue: slotId,
                      decoration: const InputDecoration(
                        labelText: 'Step 5 — Period',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final s in _slots)
                          DropdownMenuItem(
                            value: s['id'] as int,
                            child: Text(
                              _slotDisplayName(s['label']?.toString()),
                            ),
                          ),
                      ],
                      onChanged: (v) => setSheet(() => slotId = v),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int?>(
                      initialValue: subjectId,
                      decoration: const InputDecoration(
                        labelText: 'Step 6 — Subject',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final s in classSubjects)
                          DropdownMenuItem(
                            value: s['id'] as int,
                            child: Text(s['name']?.toString() ?? ''),
                          ),
                      ],
                      onChanged: (v) => setSheet(() => subjectId = v),
                    ),
                    if (selRow != null &&
                        teacherId != null &&
                        classSubjects.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'এই teacher-কে এই class-এ কোনো subject assign নেই।',
                          style: TextStyle(fontSize: 12, color: Colors.orange),
                        ),
                      ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed:
                          teacherId == null ||
                              clsName == null ||
                              sec == null ||
                              day == null ||
                              slotId == null ||
                              subjectId == null
                          ? null
                          : () async {
                              final navCtx = sheetCtx;
                              try {
                                final subjectName =
                                    classSubjects
                                        .firstWhere(
                                          (s) => s['id'] == subjectId,
                                        )['name']
                                        ?.toString() ??
                                    '';
                                var religions = <String>[];
                                if (RegExp(
                                  r'religion|islam|hindu|buddh|christian|ধর্ম|ইসলাম|হিন্দু|বৌদ্ধ|খ্রিস্ট',
                                  caseSensitive: false,
                                ).hasMatch(subjectName)) {
                                  final selectedReligions =
                                      await _chooseReligions();
                                  if (selectedReligions == null ||
                                      selectedReligions.isEmpty)
                                    return;
                                  religions = selectedReligions;
                                }
                                final sections = <Map<String, dynamic>>[];
                                final groups = <Map<String, dynamic>>[];
                                if ((selRow['group_name']?.toString() ?? '')
                                    .isNotEmpty) {
                                  groups.add({
                                    'class_id': selRow['id'],
                                    'group_name': selRow['group_name']
                                        .toString(),
                                  });
                                } else {
                                  sections.add({
                                    'class_id': selRow['id'],
                                    'section': selRow['section'].toString(),
                                  });
                                }
                                await Api.post('/routine/admin', {
                                  'teacher_id': teacherId,
                                  'day': day,
                                  'time_slot_id': slotId,
                                  'subject_id': subjectId,
                                  'sections': sections,
                                  'groups': groups,
                                  'religions': religions,
                                });
                                if (!navCtx.mounted) return;
                                Navigator.pop(navCtx);
                                ScaffoldMessenger.of(navCtx).showSnackBar(
                                  const SnackBar(
                                    content: Text('Period added'),
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
                                      e.toString().replaceFirst(
                                        'Exception: ',
                                        '',
                                      ),
                                    ),
                                  ),
                                );
                              }
                            },
                      child: const Text('Add Period'),
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

  Future<void> _deleteEntry(dynamic entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete?'),
        content: Text(
          '${entry['subject']?['name'] ?? ''} (${entry['slot_label'] ?? ''})',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.delete('/routine/admin/${entry['id']}');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Deleted')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _approveRequest(dynamic req) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve delete?'),
        content: Text(
          'Remove "${req['subject_name'] ?? ''}" — ${req['class_details'] ?? ''} (${req['teacher_name'] ?? ''})?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approve & Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.post('/routine/admin/delete-requests/${req['id']}/approve');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request approved; period removed')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _rejectRequest(dynamic req) async {
    try {
      await Api.post('/routine/admin/delete-requests/${req['id']}/reject');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request rejected; period kept')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Widget _buildDeleteRequests() {
    final pending = _deleteRequests
        .where((d) => '${d['status']}' == 'pending')
        .toList();
    if (pending.isEmpty) return const SizedBox.shrink();
    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '🕘 ${pending.length} Period Delete Request(s) — Approval Needed',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.orange.shade900,
              ),
            ),
            const SizedBox(height: 6),
            ...pending.map(
              (req) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${req['subject_name'] ?? '?'} — ${req['class_details'] ?? ''}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${req['teacher_name'] ?? '?'} • ${req['day'] != null ? _days[req['day']] : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => _rejectRequest(req),
                      child: const Text('Reject'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      onPressed: () => _approveRequest(req),
                      child: const Text('Approve'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Routines Matrix'),
        actions: [
          if (_teachers.isNotEmpty)
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                hint: const Text(
                  'All Teachers',
                  style: TextStyle(color: Colors.white),
                ),
                value: _filterTeacher,
                dropdownColor: Theme.of(context).colorScheme.surface,
                items: [null, ..._teachers.map((t) => '${t['id']}')]
                    .map(
                      (id) => DropdownMenuItem(
                        value: id,
                        child: Text(
                          id == null
                              ? 'All Teachers'
                              : (_teachers.firstWhere(
                                      (t) => '${t['id']}' == id,
                                    )['name'] ??
                                    id),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _filterTeacher = v),
              ),
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Error: $_error'))
          : RefreshIndicator(onRefresh: _load, child: _buildMatrix()),
      floatingActionButton: FloatingActionButton(
        onPressed: _loading ? null : _createEntry,
        tooltip: 'Add period',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildMatrix() {
    List list = _routines;
    if (_filterTeacher != null) {
      list = list.where((e) => '${e['teacher_id']}' == _filterTeacher).toList();
    }
    // build map: (day, slotOrder) -> [entry]
    final map = <String, List>{};
    for (final e in list) {
      final key = '${e['day']}_${e['slot_order']}';
      (map[key] = map[key] ?? []).add(e);
    }
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        _buildDeleteRequests(),
        // header row
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              const SizedBox(
                width: 60,
                child: Text(
                  'Slot',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              ..._days.map(
                (d) => Expanded(
                  child: Center(
                    child: Text(
                      d.substring(0, 3),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        ..._slots.map(
          (slot) => Card(
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 60,
                    child: Column(
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _slotDisplayName(slot['slot_label']?.toString()),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (slot['is_escape'] == true ||
                                slot['is_escape'] == 1 ||
                                slot['is_escape'] == '1')
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Text(
                                  '● বাঙ্ক',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        Text(
                          slot['start_time']?.toString().substring(0, 5) ?? '',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ..._days.asMap().entries.map((de) {
                    final key = '${de.key}_${slot['slot_order']}';
                    final entries = map[key] ?? [];
                    return Expanded(
                      child: Container(
                        margin: const EdgeInsets.all(1),
                        constraints: const BoxConstraints(minHeight: 50),
                        decoration: BoxDecoration(
                          color: entries.isEmpty
                              ? Colors.grey.shade50
                              : Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        padding: const EdgeInsets.all(2),
                        child: entries.isEmpty
                            ? const SizedBox(height: 35)
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: entries
                                    .map(
                                      (e) => Padding(
                                        padding: const EdgeInsets.all(1),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    '${e['subject']?['name'] ?? ''}',
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  Text(
                                                    e['teacher_name'] ?? '',
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      color:
                                                          Colors.teal.shade700,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            GestureDetector(
                                              onTap: () => _deleteEntry(e),
                                              child: const Icon(
                                                Icons.close,
                                                size: 12,
                                                color: Colors.red,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // conflict check
        _buildConflictCard(list),
      ],
    );
  }

  Widget _buildConflictCard(List list) {
    final slots = <String, List>{};
    for (final e in list) {
      final key = '${e['teacher_id']}_${e['day']}_${e['time_slot_id']}';
      (slots[key] = slots[key] ?? []).add(e);
    }
    final conflicts = slots.entries.where((e) => e.value.length > 1).toList();
    if (conflicts.isEmpty) return const SizedBox.shrink();
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '⚠️ ${conflicts.length} Conflict(s) Detected',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 8),
            ...conflicts
                .expand((e) => e.value)
                .map(
                  (e) => Text(
                    '${e['teacher_name'] ?? '?'} — ${e['subject']?['name'] ?? ''} — ${_days[e['day']]} ${e['slot_label'] ?? ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
