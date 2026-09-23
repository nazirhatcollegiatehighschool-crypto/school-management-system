import 'package:flutter/material.dart';
import '../api.dart';
import '../class_alerts.dart';

const _days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday'];

class RoutineScreen extends StatefulWidget {
  final dynamic teacher;
  const RoutineScreen({super.key, required this.teacher});
  @override
  State<RoutineScreen> createState() => _RoutineScreenState();
}

class _RoutineScreenState extends State<RoutineScreen> {
  List _entries = [];
  List _subjects = [];
  List _slots = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final entries = await Api.get('/routine/teacher/mine');
      final subjects = await Api.get('/routine/teacher/subjects');
      final slots = await Api.get('/routine/slots');
      if (!mounted) return;
      setState(() {
        _entries = entries is List ? entries : [];
        _subjects = subjects is List ? subjects : [];
        _slots = slots is List ? slots : [];
        _loading = false;
      });
      // keep the "next class" alert engine + weekly notification schedule in sync
      ClassAlertService.instance.updateRoutines(entries is List ? entries : []);
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _addEntry([dynamic existing]) async {
    if (_subjects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No subjects configured for any class yet.')));
      return;
    }
    if (_slots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No time slots configured yet.')));
      return;
    }

    int dayNum;
    String? slotId;
    dynamic existingEntry = existing;

    if (existingEntry == null) {
      // Step 1 — Day
      final day = await _pick1('Select Day', _days);
      if (day == null) return;
      dayNum = _days.indexOf(day);

      // Step 2 — Period
      slotId = await _pickSlot();
      if (slotId == null) return;
      if (!mounted) return;

      // Step 3 — already scheduled at this day + period?
      final ex = _entries.where((e) => e['day'] == dayNum && e['time_slot_id'].toString() == slotId).toList();
      if (ex.isNotEmpty) {
        existingEntry = ex[0];
        final action = await showModalBottomSheet<String>(
          context: context,
          builder: (ctx) => _EntryActionSheet(entry: existingEntry, classSummary: _classSummary(existingEntry)),
        );
        if (action == 'edit') {
          // fall through to the editor with day/period fixed
        } else if (action == 'delete') {
          await _deleteEntry(existingEntry);
          return;
        } else {
          return; // close
        }
      }
    } else {
      dayNum = existingEntry['day'] is int ? existingEntry['day'] : 0;
      slotId = existingEntry['time_slot_id'].toString();
    }

    // ---- editor (class -> section/group (multi) -> subject -> notes) ----
    // force the class name when editing an existing entry
    String? forcedClassName;
    if (existingEntry != null) {
      final sid = existingEntry['subject']?['id'];
      final match = _subjects.where((s) => s['id'] == sid).toList();
      if (match.isNotEmpty) {
        forcedClassName = match.first['class_name'];
      } else {
        final secs = (existingEntry['sections'] as List?) ?? [];
        final grps = (existingEntry['groups'] as List?) ?? [];
        forcedClassName = (secs.isNotEmpty ? secs.first['class_name'] : null) ??
            (grps.isNotEmpty ? grps.first['class_name'] : null)?.toString();
      }
    }

    final classNames = _subjects.map((s) => s['class_name'].toString()).toSet().toList();
    final className = forcedClassName ?? await _pick1('Select Class', classNames);
    if (className == null) return;

    final clsSubjects = _subjects.where((s) => s['class_name'].toString() == className).toList();
    final hasGroup = clsSubjects.any((s) => (s['class_group']?.toString() ?? '').isNotEmpty);
    final optionField = hasGroup ? 'class_group' : 'section';
    final options = clsSubjects
        .map((s) => s[optionField]?.toString() ?? '')
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList();

    // preselected options when editing
    final preSelected = <String>{};
    if (existingEntry != null) {
      for (final s in ((existingEntry['sections'] as List?) ?? [])) {
        if ('${s['class_name']}' == className && (s['section']?.toString() ?? '').isNotEmpty) {
          preSelected.add(s['section'].toString());
        }
      }
      for (final g in ((existingEntry['groups'] as List?) ?? [])) {
        if ('${g['class_name']}' == className && (g['group_name']?.toString() ?? '').isNotEmpty) {
          preSelected.add(g['group_name'].toString());
        }
      }
    }

    final selected = await _pickMulti(
      hasGroup ? 'Select Group(s) — one or more' : 'Select Section(s) — one or more',
      options,
      initial: preSelected.toList(),
    );
    if (selected == null || selected.isEmpty) return;

    // subject candidates: names present in EVERY selected section/group
    final optLists = selected
        .map((o) => clsSubjects.where((s) => s[optionField]?.toString() == o).toList())
        .toList();
    var sharedNames = optLists.first.map((s) => s['name'].toString()).toSet();
    for (final l in optLists) {
      sharedNames = sharedNames.intersection(l.map((s) => s['name'].toString()).toSet());
    }
    final candidateSubjects =
        optLists.first.where((s) => sharedNames.contains(s['name'].toString())).toList();
    if (candidateSubjects.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No common subject found for the selected sections/groups.')));
      return;
    }

    final subjectId = await _pick1(
      'Select Subject',
      candidateSubjects.map((s) => s['name'].toString()).toList(),
      values: candidateSubjects.map((s) => s['id'].toString()).toList(),
    );
    if (subjectId == null) return;
    final subjectName = candidateSubjects.firstWhere((s) => s['id'].toString() == subjectId)['name'];

    // class rows for the selected sections/groups
    final sections = <Map<String, dynamic>>[];
    final groups = <Map<String, dynamic>>[];
    final seenRows = <String>{};
    for (final o in selected) {
      final row = clsSubjects.firstWhere((s) => s[optionField]?.toString() == o);
      final key = row['class_id'].toString();
      if (!seenRows.add(key)) continue;
      if (hasGroup) {
        groups.add({'class_id': row['class_id'], 'group_name': o});
      } else {
        sections.add({'class_id': row['class_id'], 'section': o});
      }
    }

    final notesCtl = TextEditingController(text: existingEntry?['notes'] ?? '');
    final roomCtl = TextEditingController(text: existingEntry?['room']?.toString() ?? '');
    final slotLabel = _slots.where((s) => s['id'].toString() == slotId).isNotEmpty
        ? _slots.firstWhere((s) => s['id'].toString() == slotId)['label']
        : '';
    if (!mounted) return;
    final confirmed = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existingEntry == null ? 'Add Routine' : 'Edit Routine'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_days[dayNum]} | $slotLabel', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('$className — $subjectName', style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 3),
            Text(
              hasGroup ? 'Groups: ${selected.join(', ')}' : 'Sections: ${selected.join(', ')}',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(controller: notesCtl, decoration: const InputDecoration(labelText: 'Notes (optional)', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: roomCtl, decoration: const InputDecoration(labelText: 'Room (optional)', border: OutlineInputBorder(), hintText: 'e.g. Room 302')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Cancel')),
          if (existingEntry != null)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, 'delete'),
              child: const Text('Delete'),
            ),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(existingEntry == null ? 'Add' : 'Save')),
        ],
      ),
    );
    if (confirmed != 'save') {
      if (confirmed == 'delete') await _deleteEntry(existingEntry);
      return;
    }

    final body = {
      'day': _days[dayNum],
      'time_slot_id': int.tryParse(slotId) ?? 0,
      'subject_id': int.tryParse(subjectId) ?? 0,
      'notes': notesCtl.text.trim(),
      'room': roomCtl.text.trim(),
      'sections': sections,
      'groups': groups,
    };

    try {
      if (existingEntry == null) {
        await Api.post('/routine/teacher', body);
      } else {
        await Api.put('/routine/teacher/${existingEntry['id']}', body);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(existingEntry == null ? 'Period added' : 'Period updated')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  String _classSummary(dynamic entry) {
    final parts = <String>{};
    for (final s in (entry?['sections'] as List?) ?? []) {
      parts.add('${s['class_name']} ${s['section']}');
    }
    for (final g in (entry?['groups'] as List?) ?? []) {
      parts.add('${g['class_name']} ${g['group_name']}');
    }
    return parts.join(', ');
  }

  Future<String?> _pickSlot() {
    return showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => _ListSheet(
        title: 'Select Period',
        items: _slots.map((s) => '${s['label']} (${s['start_time']}–${s['end_time']})').toList(),
        values: _slots.map((s) => s['id'].toString()).toList(),
      ),
    );
  }

  Future<List<String>?> _pickMulti(String title, List<String> options, {List<String> initial = const []}) {
    return showModalBottomSheet<List<String>>(
      context: context,
      builder: (ctx) => _MultiSelectSheet(title: title, options: options, initial: initial),
    );
  }

  Future<String?> _pick1(String title, List<String> items, {List<String>? values}) {
    return showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => _ListSheet(title: title, items: items, values: values ?? items),
    );
  }

  Future<void> _deleteEntry(dynamic entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete period?'),
        content: Text('${entry['subject']?['name'] ?? ''} — ${entry['slot_label'] ?? ''} ${entry['day_name'] ?? ''}\n\nRemoval needs admin approval. This period will stay visible until an admin approves the request.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('Request Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.delete('/routine/teacher/${entry['id']}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delete request sent to admin for approval.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Routine'), actions: [
        IconButton(icon: const Icon(Icons.add), tooltip: 'Add period', onPressed: _loading ? null : () => _addEntry()),
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _entries.isEmpty
                  ? const Center(child: Text('No routine periods yet.\nTap + to add one.'))
                  : _buildList(),
    );
  }

  Widget _buildList() {
    final byDay = <String, List>{};
    for (final e in _entries) {
      final d = e['day_name'] ?? '';
      (byDay[d] = byDay[d] ?? []).add(e);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: _days.map((day) {
          final list = byDay[day] ?? [];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Text(day, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
              ),
              if (list.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('—', style: TextStyle(color: Colors.grey)))
              else
                ...list.map((e) => Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                      child: ListTile(
                        dense: true,
                        leading: CircleAvatar(radius: 16, child: Text('${e['slot_order'] ?? ''}')),
                        title: Text('${e['subject']?['name'] ?? ''}'),
                        subtitle: Text('${_classSummary(e).isNotEmpty ? '${_classSummary(e)} | ' : ''}'
                            '${e['slot_label'] ?? ''} (${e['start_time']?.toString().substring(0, 5) ?? ''}–${e['end_time']?.toString().substring(0, 5) ?? ''})'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _addEntry(e)),
                          IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), onPressed: () => _deleteEntry(e)),
                        ]),
                      ),
                    )),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _ListSheet extends StatelessWidget {
  final String title;
  final List<String> items;
  final List<String> values;
  const _ListSheet({required this.title, required this.items, required this.values});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.all(12), child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: items.length,
            itemBuilder: (ctx, i) => ListTile(
              title: Text(items[i]),
              onTap: () => Navigator.pop(ctx, values[i]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _MultiSelectSheet extends StatefulWidget {
  final String title;
  final List<String> options;
  final List<String> initial;
  const _MultiSelectSheet({required this.title, required this.options, required this.initial});
  @override
  State<_MultiSelectSheet> createState() => _MultiSelectSheetState();
}

class _MultiSelectSheetState extends State<_MultiSelectSheet> {
  late final Set<String> _sel = widget.initial.toSet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 6), child: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(spacing: 8, runSpacing: 8, children: widget.options.map((o) {
              final on = _sel.contains(o);
              return FilterChip(
                label: Text(o),
                selected: on,
                onSelected: (v) => setState(() { v ? _sel.add(o) : _sel.remove(o); }),
              );
            }).toList()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: _sel.isEmpty ? null : () => Navigator.pop(context, _sel.toList()),
              child: const Text('OK'),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _EntryActionSheet extends StatelessWidget {
  final dynamic entry;
  final String classSummary;
  const _EntryActionSheet({required this.entry, required this.classSummary});

  @override
  Widget build(BuildContext context) {
    final sub = entry?['subject']?['name'] ?? '';
    final slot = entry?['slot_label'] ?? '';
    final day = entry?['day_name'] ?? '';
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Period already scheduled — $day | $slot', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 6),
            Text('$sub — $classSummary', style: const TextStyle(fontSize: 14)),
          ]),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: const Text('Edit this period'),
          onTap: () => Navigator.pop(context, 'edit'),
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline, color: Colors.red),
          title: const Text('Delete this period', style: TextStyle(color: Colors.red)),
          onTap: () => Navigator.pop(context, 'delete'),
        ),
        ListTile(
          leading: const Icon(Icons.close),
          title: const Text('Close'),
          onTap: () => Navigator.pop(context, 'close'),
        ),
      ]),
    );
  }
}