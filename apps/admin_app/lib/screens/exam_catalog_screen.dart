import 'package:flutter/material.dart';
import '../api.dart';

/// NCTB exam catalog + mark-weightage editor (Q1/Q2) and the mandatory-pass
/// subject list (Q7). The weightage shown here is what folds several exam
/// kinds into one session GPA; mandatory-pass subjects can never be rescued
/// by the grace allowance.
class ExamCatalogScreen extends StatefulWidget {
  const ExamCatalogScreen({super.key});
  @override
  State<ExamCatalogScreen> createState() => _ExamCatalogScreenState();
}

class _ExamCatalogScreenState extends State<ExamCatalogScreen> {
  List _catalog = const [];
  List _classes = const [];
  List _subjects = const [];
  Set<int> _mandatory = {};
  int? _classId;
  bool _loading = true;
  String? _error;
  final Map<String, TextEditingController> _pct = {};

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() {
    for (final c in _pct.values) { c.dispose(); }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final cat = await Api.get('/admin/exam-catalog');
      final cls = await Api.get('/admin/classes');
      if (!mounted) return;
      _catalog = (cat['catalog'] as List?) ?? const [];
      _classes = (cls is List) ? cls : ((cls['classes'] as List?) ?? const []);
      _pct.clear();
      for (final r in _catalog) {
        _pct['${r['band']}|${r['exam_kind']}'] =
            TextEditingController(text: '${(num.tryParse('${r['weight_pct']}') ?? 0).toInt()}');
      }
      setState(() => _loading = false);
      if (_classes.isNotEmpty && _classId == null) {
        await _selectClass(_classes.first['id'] as int);
      } else if (_classId != null) {
        await _selectClass(_classId!);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _selectClass(int id) async {
    setState(() => _classId = id);
    try {
      final subs = await Api.get('/admin/subjects');
      final mp = await Api.get('/admin/mandatory-pass?class_id=$id');
      if (!mounted) return;
      final all = (subs is List) ? subs : ((subs['subjects'] as List?) ?? const []);
      _subjects = all.where((s) => s['class_id'] == id).toList();
      _mandatory = (((mp['rules'] as List?) ?? const [])
          .map((r) => r['subject_id'] as int).toSet());
      setState(() {});
    } catch (_) {}
  }

  Future<void> _saveWeightage() async {
    final messenger = ScaffoldMessenger.of(context);
    final rows = <Map<String, dynamic>>[];
    for (final r in _catalog) {
      final key = '${r['band']}|${r['exam_kind']}';
      rows.add({'band': r['band'], 'exam_kind': r['exam_kind'], 'weight_pct': num.tryParse(_pct[key]?.text ?? '') ?? 0});
    }
    try {
      await Api.put('/admin/exam-catalog', {'catalog': rows});
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(backgroundColor: Colors.green, content: Text('Weightage saved ✓')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(backgroundColor: Colors.red,
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _saveMandatory() async {
    if (_classId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Api.put('/admin/mandatory-pass', {'class_id': _classId, 'subject_ids': _mandatory.toList()});
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(backgroundColor: Colors.green, content: Text('Mandatory-pass saved ✓')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(backgroundColor: Colors.red,
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Widget _bandGroup(String band, String label) {
    final rows = _catalog.where((r) => r['band'] == band).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    return Card(margin: const EdgeInsets.symmetric(vertical: 6), child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        ...rows.map((r) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text('${r['exam_kind']}${r['is_promotion_source'] == 1 ? '  ⭐ promotion' : ''}')),
            SizedBox(width: 90, child: TextField(
              controller: _pct['$band|${r['exam_kind']}'],
              keyboardType: TextInputType.number, textAlign: TextAlign.center,
              decoration: const InputDecoration(suffixText: '%', isDense: true, border: OutlineInputBorder()),
            )),
          ]),
        )),
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exam Weightage'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(padding: const EdgeInsets.all(12), children: [
                  _bandGroup('6-9', 'Class 6–9  (CA + Half-Yearly + Annual)'),
                  _bandGroup('10', 'Class 10  (Pre-Test + Test)'),
                  _bandGroup('ssc', 'SSC Batch  (Model Test Series)'),
                  const SizedBox(height: 6),
                  FilledButton.icon(onPressed: _saveWeightage,
                      icon: const Icon(Icons.save), label: const Text('Save Weightage')),
                  const Divider(height: 32),
                  const Text('Mandatory-pass subjects (Q7 — grace cannot rescue these)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: _classId,
                    decoration: const InputDecoration(labelText: 'Class', border: OutlineInputBorder()),
                    items: _classes.map<DropdownMenuItem<int>>((c) =>
                        DropdownMenuItem(value: c['id'] as int, child: Text('${c['name']} ${c['section'] ?? ''}'))).toList(),
                    onChanged: (v) { if (v != null) _selectClass(v); },
                  ),
                  const SizedBox(height: 8),
                  ..._subjects.map((s) => CheckboxListTile(
                    dense: true,
                    value: _mandatory.contains(s['id'] as int),
                    title: Text('${s['name']}'),
                    onChanged: (v) => setState(() {
                      final id = s['id'] as int;
                      if (v == true) { _mandatory.add(id); } else { _mandatory.remove(id); }
                    }),
                  )),
                  const SizedBox(height: 8),
                  FilledButton.icon(onPressed: _saveMandatory,
                      icon: const Icon(Icons.check), label: const Text('Save Mandatory-pass')),
                  const SizedBox(height: 40),
                ]),
    );
  }
}
