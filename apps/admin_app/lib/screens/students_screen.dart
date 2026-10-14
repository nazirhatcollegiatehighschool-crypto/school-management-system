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
      if (mounted) setState(() { _rows = r; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
            SizedBox(width: 8),
            Text('Delete Student?'),
          ],
        ),
        content: Text('Delete ${s['name']} (Roll ${s['roll']})? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() { _confirmingDelete = false; });
    if (ok != true) return;
    try {
      await Api.delete('/admin/students/${s['id']}');
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
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
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) {
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

          void pickClass(String? name) {
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

          void pickSection(String? v) {
            setSheet(() {
              sec = v;
              final group = _classes.any((c) => c['name'] == cls && c['group_name'] != null);
              final match = _classes.firstWhere((c) => c['name'] == cls &&
                  (group ? c['group_name'] == sec : c['section'] == sec));
              classId = (match['id'] as num).toInt();
            });
            checkDup();
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Drag Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    s == null ? 'Add New Student' : 'Edit Student Details',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 16),

                  if (s != null) ...[
                    TextField(
                      controller: code,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Student Code',
                        prefixIcon: Icon(Icons.qr_code_rounded, size: 20),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  TextField(
                    controller: name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Student Full Name *',
                      prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: roll,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => checkDup(),
                          decoration: InputDecoration(
                            labelText: 'Roll Number *',
                            prefixIcon: const Icon(Icons.tag_rounded, size: 20),
                            errorText: dupErr,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: dob,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Date of Birth',
                            prefixIcon: Icon(Icons.calendar_today_rounded, size: 18),
                          ),
                          onTap: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: DateTime(2013),
                              firstDate: DateTime(1995),
                              lastDate: DateTime.now(),
                            );
                            if (d != null) {
                              dob.text = d.toIso8601String().substring(0, 10);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: cls,
                          decoration: const InputDecoration(
                            labelText: 'Class *',
                            prefixIcon: Icon(Icons.school_outlined, size: 20),
                          ),
                          items: _classNames.map<DropdownMenuItem<String>>((c) =>
                              DropdownMenuItem(value: c.toString(), child: Text(c.toString()))).toList(),
                          onChanged: pickClass,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: sec,
                          decoration: InputDecoration(
                            labelText: isGroup ? 'Group *' : 'Section *',
                            prefixIcon: const Icon(Icons.meeting_room_outlined, size: 20),
                          ),
                          items: sectionOpts.map<DropdownMenuItem<String>>((v) =>
                              DropdownMenuItem(value: v.toString(), child: Text(v.toString()))).toList(),
                          onChanged: pickSection,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: gname,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Guardian Name',
                      prefixIcon: Icon(Icons.family_restroom_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Guardian Phone',
                      prefixIcon: Icon(Icons.phone_outlined, size: 20),
                    ),
                  ),
                  const SizedBox(height: 20),

                  FilledButton(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () async {
                      if (name.text.trim().isEmpty || roll.text.trim().isEmpty || classId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please fill required fields (Name, Roll, Class)')),
                        );
                        return;
                      }
                      if (dupErr != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(backgroundColor: Colors.redAccent, content: Text(dupErr!)),
                        );
                        return;
                      }

                      final body = {
                        'name': name.text.trim(),
                        'roll': int.tryParse(roll.text.trim()) ?? 0,
                        'class_id': classId,
                        'dob': dob.text.trim().isEmpty ? null : dob.text.trim(),
                        'guardian_name': gname.text.trim().isEmpty ? null : gname.text.trim(),
                        'guardian_phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
                      };

                      try {
                        if (s == null) {
                          await Api.post('/admin/students', body);
                        } else {
                          await Api.put('/admin/students/${s['id']}', body);
                        }
                        if (!mounted) return;
                        Navigator.pop(context);
                        _load();
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: Colors.redAccent,
                            content: Text(e.toString().replaceFirst('Exception: ', '')),
                          ),
                        );
                      }
                    },
                    child: Text(s == null ? 'Save Student' : 'Update Student', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
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
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Students Directory'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Student', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Column(
                  children: [
                    // Search & Filters Header Container
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.15))),
                      ),
                      child: Column(
                        children: [
                          TextField(
                            onChanged: (v) => setState(() => _search = v),
                            decoration: InputDecoration(
                              prefixIcon: Icon(Icons.search_rounded, color: primary, size: 20),
                              hintText: 'Search by name, roll, code, guardian...',
                              hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              suffixIcon: _search.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded, size: 18),
                                      onPressed: () => setState(() => _search = ''),
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: _filterCls,
                                  isExpanded: true,
                                  hint: const Text('All Classes', style: TextStyle(fontSize: 13)),
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  items: [
                                    const DropdownMenuItem<String>(value: null, child: Text('All Classes')),
                                    ..._classNames.map<DropdownMenuItem<String>>((n) =>
                                        DropdownMenuItem(value: n.toString(), child: Text(n.toString(), overflow: TextOverflow.ellipsis))),
                                  ],
                                  onChanged: (v) => setState(() { _filterCls = v; _filterSec = null; }),
                                ),
                              ),
                              if (_filterCls != null) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _filterSec,
                                    isExpanded: true,
                                    hint: const Text('All Sections', style: TextStyle(fontSize: 13)),
                                    decoration: InputDecoration(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    items: [
                                      const DropdownMenuItem<String>(value: null, child: Text('All Sections')),
                                      ..._sectionOptions(_filterCls).map<DropdownMenuItem<String>>((v) =>
                                          DropdownMenuItem(value: v, child: Text(v))),
                                    ],
                                    onChanged: (v) => setState(() => _filterSec = v),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Results Count Bar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Showing ${filtered.length} of ${_rows.length} students',
                            style: TextStyle(
                              color: Colors.blueGrey.shade700,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (_filterCls != null || _search.isNotEmpty)
                            InkWell(
                              onTap: () => setState(() {
                                _search = '';
                                _filterCls = null;
                                _filterSec = null;
                              }),
                              child: Text(
                                'Reset Filters',
                                style: TextStyle(color: primary, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Students List
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: filtered.isEmpty
                            ? ListView(
                                children: [
                                  const SizedBox(height: 80),
                                  Icon(Icons.person_search_rounded, size: 56, color: Colors.grey.shade300),
                                  const SizedBox(height: 12),
                                  const Center(
                                    child: Text(
                                      'No students found',
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey),
                                    ),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(14, 4, 14, 84),
                                itemCount: filtered.length,
                                itemBuilder: (_, i) {
                                  final s = filtered[i];
                                  final rollNum = s['roll']?.toString() ?? '-';
                                  final guardian = s['guardian_name']?.toString() ?? '';
                                  final phone = s['guardian_phone']?.toString() ?? '';

                                  return Container(
                                    margin: const EdgeInsets.symmetric(vertical: 5),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.02),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Roll Badge Avatar
                                          Container(
                                            width: 44,
                                            height: 44,
                                            decoration: BoxDecoration(
                                              color: primary.withValues(alpha: 0.10),
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: primary.withValues(alpha: 0.20)),
                                            ),
                                            child: Center(
                                              child: Text(
                                                rollNum,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  color: primary,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),

                                          // Info Section
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        s['name'] ?? '',
                                                        style: const TextStyle(
                                                          fontSize: 15,
                                                          fontWeight: FontWeight.w700,
                                                          color: Color(0xFF0F172A),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                // Badges Row
                                                Wrap(
                                                  spacing: 6,
                                                  runSpacing: 4,
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFFEFF6FF),
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(color: const Color(0xFFBFDBFE)),
                                                      ),
                                                      child: Text(
                                                        'Class ${s['class_name']} (${s['section']})',
                                                        style: const TextStyle(
                                                          color: Color(0xFF1D4ED8),
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                    if ((s['student_code'] ?? '').toString().isNotEmpty)
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: Colors.grey.shade100,
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Text(
                                                          s['student_code'].toString(),
                                                          style: TextStyle(
                                                            color: Colors.grey.shade700,
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w500,
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                                if (guardian.isNotEmpty || phone.isNotEmpty) ...[
                                                  const SizedBox(height: 6),
                                                  Row(
                                                    children: [
                                                      Icon(Icons.family_restroom_rounded, size: 14, color: Colors.grey.shade500),
                                                      const SizedBox(width: 4),
                                                      Expanded(
                                                        child: Text(
                                                          [if (guardian.isNotEmpty) guardian, if (phone.isNotEmpty) phone].join(' • '),
                                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),

                                          // Actions
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.edit_outlined, size: 20),
                                                color: Colors.blueGrey.shade600,
                                                onPressed: () => _showForm(s),
                                                tooltip: 'Edit',
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent),
                                                onPressed: _confirmingDelete ? null : () => _delete(s),
                                                tooltip: 'Delete',
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
    );
  }
}