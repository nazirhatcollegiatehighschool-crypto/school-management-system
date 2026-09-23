import 'package:flutter/material.dart';
import '../api.dart';

class StudentsScreen extends StatefulWidget {
  const StudentsScreen({super.key});
  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  List _rows = [];
  List _classes = [];
  bool _loading = true;
  String? _error;
  String _search = '';
  String? _filterCls;
  String? _filterSec;
  bool _confirmingDelete = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    try {
      final r = await Api.get('/admin/classes');
      if (mounted) setState(() => _classes = r);
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() { _loading = true; });
    try {
      final r = await Api.get('/admin/students');
      setState(() { _rows = r; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  List get _filtered {
    var list = _rows;
    final q = _search.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((s) {
        final name = (s['name'] ?? '').toString().toLowerCase();
        final code = (s['student_code'] ?? '').toString().toLowerCase();
        final guardian = (s['guardian_name'] ?? '').toString().toLowerCase();
        return name.contains(q) || code.contains(q) ||
            s['roll'].toString().contains(q) || guardian.contains(q);
      }).toList();
    }
    if (_filterCls != null) {
      list = list.where((s) => s['class_name'] == _filterCls).toList();
      if (_filterSec != null) {
        list = list.where((s) => s['section'] == _filterSec).toList();
      }
    }
    return list;
  }

  List get _classNames => _classes.map((c) => c['name'] as String).toSet().toList();

  List<String> _sectionOptions(String? cls) {
    final sel = _classes.where((c) => c['name'] == cls).toList();
    final isGroup = sel.any((c) => c['group_name'] != null);
    return (isGroup
            ? sel.map((c) => c['group_name']).where((x) => x != null)
            : sel.map((c) => c['section']).where((x) => x != null))
        .map((x) => x.toString())
        .toSet()
        .toList();
  }

  Future<void> _delete(dynamic s) async {
    setState(() { _confirmingDelete = true; });
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete student?'),
        content: Text('Delete ${s['name']} (Roll ${s['roll']})? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ));
    if (!mounted) return;
    setState(() { _confirmingDelete = false; });
    if (ok != true) return;
    try {
      await Api.delete('/admin/students/${s['id']}');
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  void _showForm([dynamic s]) {
    final code = TextEditingController(text: s?['student_code'] ?? '');
    final name = TextEditingController(text: s?['name'] ?? '');
    final roll = TextEditingController(text: s?['roll']?.toString() ?? '');
    final dobStr = (s?['dob'] ?? '').toString();
    final dob = TextEditingController(text: dobStr.length >= 10 ? dobStr.substring(0, 10) : '');
    final gname = TextEditingController(text: s?['guardian_name'] ?? '');
    final phone = TextEditingController(text: s?['guardian_phone'] ?? '');
    int? classId = s?['class_id'];
    String? cls = s?['class_name'];
    String? sec = s?['section'];

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (_, setSheet) {
          final classNames = _classes.map((c) => c['name']).toSet().toList();
          final selectedClasses = _classes.where((c) => c['name'] == cls).toList();
          final isGroup = selectedClasses.any((c) => c['group_name'] != null);
          final sectionOpts = (isGroup
              ? selectedClasses.map((c) => c['group_name']).where((x) => x != null)
              : selectedClasses.map((c) => c['section']).where((x) => x != null))
              .toSet().toList();

          String? dupErr;
          String? dupError(List st, String? cls, String? sec, String? rollText) {
            final rn = num.tryParse(rollText ?? '');
            if (cls == null || sec == null || rn == null) return null;
            final dup = st.any((r) =>
                r['class_name'] == cls && r['section'] == sec &&
                num.tryParse(r['roll'].toString()) == rn &&
                r['id'] != s?['id']);
            return dup ? "Student with Roll $rn already exists in this Class & $sec!" : null;
          }

          void checkDup() {
            dupErr = dupError(_rows, cls, sec, roll.text.trim());
            setSheet(() {});
          }

          Future<void> pickClass(String? name) async {
            setSheet(() {
              cls = name;
              sec = null;
              classId = null;
              if (_classes.any((c) => c['name'] == name)) {
                final group = _classes.any((c) => c['name'] == name && c['group_name'] != null);
                final first = _classes.firstWhere((c) => c['name'] == name);
                sec = group ? first['group_name'] : first['section'];
                final match = _classes.firstWhere((c) => c['name'] == name &&
                    (group ? c['group_name'] == sec : c['section'] == sec));
                classId = (match['id'] as num).toInt();
              }
            });
            checkDup();
          }

          Future<void> pickSection(String? v) async {
            setSheet(() {
              sec = v;
              final group = _classes.any((c) => c['name'] == cls && c['group_name'] != null);
              final match = _classes.firstWhere((c) => c['name'] == cls &&
                  (group ? c['group_name'] == sec : c['section'] == sec));
              classId = (match['id'] as num).toInt();
            });
            checkDup();
          }

          return Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Padding(padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(s == null ? 'Add Student' : 'Edit Student', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            TextField(controller: code,
              readOnly: true,
              decoration: const InputDecoration(
                  labelText: 'Student Code (Auto-generated)',
                  hintText: 'Auto-generated on save',
                  border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name *', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: roll, keyboardType: TextInputType.number,
                  onChanged: (_) => checkDup(),
                  decoration: InputDecoration(
                      labelText: 'Roll *', border: const OutlineInputBorder(),
                      errorText: dupErr,
                      errorBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.red)),
                      focusedErrorBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.red, width: 2)),
                  ))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: dob, readOnly: true,
                onTap: () async {
                  final d = await showDatePicker(context: context, initialDate: DateTime(2013),
                      firstDate: DateTime(1995), lastDate: DateTime.now());
                  if (d != null) dob.text = d.toIso8601String().substring(0, 10);
                },
                decoration: const InputDecoration(labelText: 'DOB', border: OutlineInputBorder()))),
            ]),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: cls,
              hint: const Text('Select Class'),
              decoration: const InputDecoration(labelText: 'Class *', border: OutlineInputBorder()),
              items: classNames.map<DropdownMenuItem<String>>((n) =>
                  DropdownMenuItem(value: n, child: Text(n))).toList(),
              onChanged: pickClass,
            ),
            const SizedBox(height: 10),
            if (cls != null)
              DropdownButtonFormField<String>(
                key: ValueKey('sec-$cls'),
                initialValue: sec,
                hint: Text(isGroup ? 'Select Group' : 'Select Section'),
                decoration: InputDecoration(
                    labelText: isGroup ? 'Group *' : 'Section *',
                    border: const OutlineInputBorder()),
                items: sectionOpts.map<DropdownMenuItem<String>>((v) =>
                    DropdownMenuItem(value: v, child: Text(v.toString()))).toList(),
                onChanged: pickSection,
              ),
            const SizedBox(height: 10),
          TextField(controller: gname, decoration: const InputDecoration(labelText: 'Guardian Name', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: phone, keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Guardian Phone (admission main)', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          FilledButton(onPressed: dupErr != null ? null : () async {
            try {
              final body = {
                'student_code': code.text.trim(), 'name': name.text.trim(),
                'roll': num.tryParse(roll.text) ?? 0, 'dob': dob.text.isEmpty ? null : dob.text,
                'class_id': classId, 'guardian_name': gname.text.trim(), 'guardian_phone': phone.text.trim(),
              };
              if (s == null) {
                await Api.post('/admin/students', body);
              } else {
                await Api.put('/admin/students/${s['id']}', body);
              }
              if (!mounted) return;
              Navigator.pop(context);
              _load();
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  backgroundColor: Colors.red,
                  content: Text(e.toString().replaceFirst('Exception: ', ''))));
            }
}, child: const Text('Save')),
          ]),
        ),
      ),
    );
      },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      appBar: AppBar(title: const Text('Students')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(), child: const Icon(Icons.add)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Column(children: [
                  Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: TextField(
                      onChanged: (v) => setState(() => _search = v),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: 'Search by name, code, roll, guardian',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                        suffixIcon: _search.isNotEmpty
                            ? IconButton(icon: const Icon(Icons.clear, size: 18),
                                onPressed: () => setState(() => _search = ''))
                            : null,
                      ),
                    )),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(children: [
                      Expanded(child: DropdownButtonFormField<String>(
                        initialValue: _filterCls,
                        hint: const Text('সব Class'),
                        isDense: true,
                        decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), isDense: true),
                        items: _classNames.map<DropdownMenuItem<String>>((n) =>
                            DropdownMenuItem(value: n, child: Text(n, overflow: TextOverflow.ellipsis))).toList(),
                        onChanged: (v) => setState(() { _filterCls = v; _filterSec = null; }),
                      )),
                      const SizedBox(width: 8),
                      if (_filterCls != null)
                        Expanded(child: DropdownButtonFormField<String>(
                          initialValue: _filterSec,
                          hint: const Text('সব Section'),
                          isDense: true,
                          decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), isDense: true),
                          items: _sectionOptions(_filterCls).map<DropdownMenuItem<String>>((v) =>
                              DropdownMenuItem(value: v, child: Text(v))).toList(),
                          onChanged: (v) => setState(() => _filterSec = v),
                        )),
                    ])),
                  Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Row(children: [
                      Text('${filtered.length}${filtered.length != _rows.length ? ' / ${_rows.length}' : ''} students',
                          style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ])),
                  Expanded(child: RefreshIndicator(
                      onRefresh: _load,
                      child: filtered.isEmpty
                          ? ListView(children: const [SizedBox(height: 120), Center(child: Text('No students found'))])
                          : ListView.builder(
                              padding: const EdgeInsets.only(bottom: 90),
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final s = filtered[i];
                                return Card(child: ListTile(
                                  leading: CircleAvatar(child: Text('${s['roll']}')),
                                  title: Text(s['name']),
                                  subtitle: Text('${s['class_name']} (${s['section']}) • ${s['student_code']}\nGuardian: ${s['guardian_name'] ?? '-'} • ${s['guardian_phone'] ?? '-'}'),
                                  isThreeLine: true,
                                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                    IconButton(icon: const Icon(Icons.edit), onPressed: () => _showForm(s)),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                                      onPressed: _confirmingDelete ? null : () => _delete(s),
                                    ),
                                  ]),
                                ));
                              }))),
                ]),
    );
  }
}