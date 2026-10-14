import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key});
  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List _events = [];
  bool _loading = true;
  String? _error;
  // Drill state: event -> class -> students -> open student subjects.
  Map? _drill;
  List _drillClasses = [];
  int? _drillClass;
  List _drillStudents = [];
  List _drillSubjects = [];
  int? _drillOpenStudent;
  bool _drillBusy = false;
  // Entry-permission sheet state.
  Map? _entryFor;
  bool _entryOpen = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Api.get('/results/events');
      setState(() { _events = r is List ? r : []; _loading = false; _error = null; });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  List get _running => _events.where((e) => e['is_published'] != 1).toList();
  List get _published => _events.where((e) => e['is_published'] == 1).toList();

  String _fmtD(dynamic d) => d == null ? '—' : '$d'.substring(0, 10);

  // ---- Teacher entry permission (one click, all groups at once) ----
  Future<void> _doEntryToggle() async {
    if (_entryFor == null) return;
    final id = _entryFor!['id'];
    final name = '${_entryFor!['name']}';
    try {
      final r = await Api.post('/admin/events/$id/entry', {'entry_open': _entryOpen ? 1 : 0});
      if (!mounted) return;
      setState(() => _entryFor = null);
      _load();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.green,
          content: Text('"$name": teacher entry ${_entryOpen ? 'খোলা' : 'বন্ধ'} (${r['exams']} exam)।')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  // ---- Publish beside the running event: one tap moves it to Published tab
  // ---- and (optionally) notifies ONLY the linked guardians. ----
  Future<void> _publish(Map ev, bool notify) async {
    final id = ev['id'];
    try {
      final r = await Api.post('/results/events/$id/publish', {'notify_guardians': notify});
      if (!mounted) return;
      _load();
      final already = r['already_notified'] == true;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.green,
          content: Text(already
              ? '"${ev['name']}" Published-এ গেছে (আগেই notify পাঠানো ছিল — duplicate যায়নি)।'
              : '"${ev['name']}" Published-এ গেছে।${notify ? ' Guardian-কে পাঠানো হয়েছে (${r['notified']} জন — শুধু linked সন্তানের result)।' : ''}')));
      _tabs.animateTo(1);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      // Coverage gate (422): show WHAT is missing, per class.
      if (msg.contains('422') || msg.contains('শেষ না হওয়া')) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.orange, duration: const Duration(seconds: 6),
            content: Text(msg)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: Colors.red, content: Text(msg)));
      }
    }
  }

  void _askPublish(Map ev) {
    var notify = true;
    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, setD) => AlertDialog(
        title: Text('Publish "${ev['name']}"?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Publish করলে event Published-এ চলে যাবে, সব entry একসাথে বন্ধ হবে, result auto-compute হবে।'),
          const SizedBox(height: 10),
          Row(children: [
            Checkbox(value: notify, onChanged: (v) => setD(() => notify = v ?? true)),
            const Expanded(child: Text('Guardian-দের notify করুন (শুধু linked সন্তানের PDF+marksheet)')),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('বাতিল')),
          FilledButton(
            onPressed: () { Navigator.pop(c); _publish(ev, notify); },
            child: const Text('Publish ✓'),
          ),
        ],
      )),
    );
  }

  // ---- Drill: event -> Class 10 -> group -> students -> subjects ----
  Future<void> _openDrill(Map ev) async {
    setState(() { _drill = ev; _drillBusy = true; _drillClass = null; _drillStudents = []; });
    try {
      final r = await Api.get('/results/events/${ev['id']}/coverage');
      if (!mounted) return;
      setState(() { _drillClasses = (r['classes'] as List?) ?? []; _drillBusy = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _drillBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _openDrillClass(int classId) async {
    if (_drill == null) return;
    setState(() { _drillBusy = true; _drillClass = classId; _drillOpenStudent = null; });
    try {
      final r = await Api.get('/results/tabulation?event_id=${_drill!['id']}&class_id=$classId');
      if (!mounted) return;
      setState(() {
        _drillStudents = (r['rows'] as List?) ?? [];
        _drillSubjects = (r['subjects'] as List?) ?? [];
        _drillBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _drillBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _pdfAll() async {
    if (_drill == null || _drillClass == null) return;
    final url = '${Api.downloadBase}/results/class-pdf?event_id=${_drill!['id']}&class_id=$_drillClass';
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF খোলা যায়নি: $e')));
    }
  }

  Future<void> _pdfOne(int studentId) async {
    if (_drill == null) return;
    final url = '${Api.downloadBase}/guardian/student/$studentId/result-card.pdf?event_id=${_drill!['id']}';
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF খোলা যায়নি: $e')));
    }
  }

  Widget _eventCard(Map ev, {required bool running}) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${ev['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            if ((ev['entry_open_count'] ?? 0) > 0)
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(99)),
                  child: Text('✏️ entry open (${ev['entry_open_count']})',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.blue.shade800))),
          ]),
          const SizedBox(height: 4),
          Text('📅 Exam: ${_fmtD(ev['exam_date'])}   🎯 Result: ${_fmtD(ev['result_date'])}',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          Text('📚 ${ev['exam_count'] ?? 0} subject-exam • 👥 ${ev['students_with_marks'] ?? 0} student-এর marks',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.search, size: 16),
              label: const Text('খুলুন', style: TextStyle(fontSize: 12)),
              onPressed: () => _openDrill(ev),
            ),
            if (running) ...[
              OutlinedButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Entry', style: TextStyle(fontSize: 12)),
                onPressed: () => setState(() { _entryFor = ev; _entryOpen = true; }),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.publish_rounded, size: 16),
                label: const Text('Publish ✓', style: TextStyle(fontSize: 12)),
                onPressed: () => _askPublish(ev),
              ),
            ] else
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(99)),
                  child: Text('✓ Published${ev['notify_guardians'] == 1 ? ' • 🔔 notified' : ''}',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.green.shade800))),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Results — Running / Published'),
        bottom: TabBar(controller: _tabs, tabs: [
          Tab(text: '▶ Running (${_running.length})'),
          Tab(text: '✓ Published (${_published.length})'),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _events.isEmpty
              ? Center(child: Text(_error!))
              : Column(children: [
                  Expanded(
                    child: TabBarView(controller: _tabs, children: [
                      RefreshIndicator(
                        onRefresh: _load,
                        child: _running.isEmpty
                            ? ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('কোনো running exam নেই। Results → New Event থেকে তৈরি করুন।')))])
                            : ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: _running.length,
                                itemBuilder: (_, i) => _eventCard(_running[i], running: true),
                              ),
                      ),
                      RefreshIndicator(
                        onRefresh: _load,
                        child: _published.isEmpty
                            ? ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('এখনো কিছু publish হয়নি। Running থেকে Publish চাপুন।')))])
                            : ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: _published.length,
                                itemBuilder: (_, i) => _eventCard(_published[i], running: false),
                              ),
                      ),
                    ]),
                  ),
                  // ---- Drill sheet (persistent bottom panel) ----
                  if (_drill != null)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(top: BorderSide(color: Colors.grey.shade300)),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, -3))],
                      ),
                      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.55),
                      child: Column(children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
                          child: Row(children: [
                            Expanded(child: Text('🔍 ${_drill!['name']} — Class 10 → Group → Student',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5))),
                            IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _drill = null)),
                          ]),
                        ),
                        Expanded(
                          child: _drillBusy
                              ? const Center(child: CircularProgressIndicator())
                              : _drillClass == null
                                  ? ListView.builder(
                                      itemCount: _drillClasses.length,
                                      itemBuilder: (_, i) {
                                        final c = _drillClasses[i];
                                        return ListTile(
                                          leading: const Icon(Icons.class_outlined),
                                          title: Text('${c['class_name']} (${c['group_name'] ?? c['section'] ?? ''})',
                                              style: const TextStyle(fontWeight: FontWeight.w700)),
                                          subtitle: Text('${c['students_with_marks']}/${c['student_count']} student • ${c['subjects_with_marks']}/${c['assigned_subjects'] ?? c['subject_count']} subject'),
                                          trailing: const Icon(Icons.arrow_forward_ios, size: 15),
                                          onTap: () => _openDrillClass(c['class_id'] as int),
                                        );
                                      },
                                    )
                                  : Column(children: [
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        child: Row(children: [
                                          TextButton.icon(
                                            icon: const Icon(Icons.arrow_back, size: 16),
                                            label: const Text('সব group', style: TextStyle(fontSize: 12)),
                                            onPressed: () => setState(() { _drillClass = null; _drillStudents = []; }),
                                          ),
                                          const Spacer(),
                                          FilledButton.icon(
                                            icon: const Icon(Icons.picture_as_pdf, size: 16),
                                            label: const Text('সবার PDF (এক ফাইলে)', style: TextStyle(fontSize: 12)),
                                            onPressed: _pdfAll,
                                          ),
                                        ]),
                                      ),
                                      Expanded(
                                        child: ListView.builder(
                                          itemCount: _drillStudents.length,
                                          itemBuilder: (_, i) {
                                            final s = _drillStudents[i];
                                            final open = _drillOpenStudent == s['id'];
                                            return Column(children: [
                                              ListTile(
                                                dense: true,
                                                leading: CircleAvatar(radius: 15, child: Text('${s['roll']}', style: const TextStyle(fontSize: 11))),
                                                title: Text('${s['name']}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                                                subtitle: Text('GPA ${s['final_gpa'] ?? '-'} • ${s['result_status'] ?? '-'}${s['position'] != null ? ' • #${s['position']}' : ''}',
                                                    style: const TextStyle(fontSize: 11.5)),
                                                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                                  IconButton(
                                                    icon: Icon(open ? Icons.expand_less : Icons.expand_more),
                                                    tooltip: 'Subject-wise',
                                                    onPressed: () => setState(() => _drillOpenStudent = open ? null : s['id'] as int),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.picture_as_pdf_outlined),
                                                    tooltip: 'Individual PDF',
                                                    onPressed: () => _pdfOne(s['id'] as int),
                                                  ),
                                                ]),
                                                onTap: () => setState(() => _drillOpenStudent = open ? null : s['id'] as int),
                                              ),
                                              if (open)
                                                Container(
                                                  width: double.infinity,
                                                  margin: const EdgeInsets.only(left: 52, right: 12, bottom: 6),
                                                  padding: const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(
                                                      color: Colors.blueGrey.shade50,
                                                      borderRadius: BorderRadius.circular(8)),
                                                  child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        for (final sub in _drillSubjects)
                                                          Builder(builder: (_) {
                                                            final fams = (s['_families'] as List?) ?? [];
                                                            Map? f;
                                                            try {
                                                              f = fams.cast<Map?>().firstWhere(
                                                                  (x) => x != null && x['subject'] == sub, orElse: () => null);
                                                            } catch (_) {
                                                              f = null;
                                                            }
                                                            return Padding(
                                                              padding: const EdgeInsets.symmetric(vertical: 1.5),
                                                              child: Row(children: [
                                                                Expanded(child: Text('$sub', style: const TextStyle(fontSize: 12))),
                                                                Text(f != null ? '${f['total']}/${f['full']} • ${f['letter_grade']}' : '—',
                                                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                                              ]),
                                                            );
                                                          }),
                                                      ]),
                                                ),
                                            ]);
                                          },
                                        ),
                                      ),
                                    ]),
                        ),
                      ]),
                    ),
                  // ---- Entry-permission sheet ----
                  if (_entryFor != null)
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border(top: BorderSide(color: Colors.grey.shade300))),
                      child: Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Teacher Entry — "${_entryFor!['name']}"',
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                          const Text('এক ক্লিকে সব group-এ permission খুলবে/বন্ধ হবে',
                              style: TextStyle(fontSize: 11.5, color: Colors.black54)),
                          Row(children: [
                            Switch(value: _entryOpen, onChanged: (v) => setState(() => _entryOpen = v)),
                            Text(_entryOpen ? 'Entry খোলা ✏️' : 'Entry বন্ধ 🔒',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          ]),
                        ])),
                        TextButton(onPressed: () => setState(() => _entryFor = null), child: const Text('বাতিল')),
                        const SizedBox(width: 6),
                        FilledButton(onPressed: _doEntryToggle, child: const Text('Apply')),
                      ]),
                    ),
                ]),
    );
  }
}
