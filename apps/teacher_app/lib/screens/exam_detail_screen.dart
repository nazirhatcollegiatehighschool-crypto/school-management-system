import 'package:flutter/material.dart';

import '../api.dart';
import '../nctb_grading.dart';
import '../pdf/app_pdf.dart';
import '../pdf/teacher_pdfs.dart';

class ExamDetailScreen extends StatefulWidget {
  final int examId;
  final String examName;
  const ExamDetailScreen({
    super.key,
    required this.examId,
    required this.examName,
  });
  @override
  State<ExamDetailScreen> createState() => _ExamDetailScreenState();
}

class _ExamDetailScreenState extends State<ExamDetailScreen> {
  Map? _data;
  bool _loading = true;
  bool _published = false;
  bool _subjectMine = false;
  bool _isMine = false;
  String? _error;
  late Map<int, TextEditingController> _controllers;
  late Map<int, TextEditingController> _commentControllers;
  // Component-wise controllers: studentId -> { cq: ctl, ... }
  final Map<int, Map<String, TextEditingController>> _partCtls = {};
  List _components = const [];
  bool _componentMode = false;
  Set<int> _lockedIds = {};
  Map<int, num> _existingTotals = {};
  int _enteredCount = 0;
  // Draft marks change only when the teacher explicitly saves.
  String _entryStatus = 'draft';
  String _saveState = ''; // '', 'saving', 'saved', 'error'

  num get _fullMarks =>
      num.tryParse('${(_data?['exam'] ?? {})['full_marks'] ?? ''}') ?? 100;

  /// The marks sheet is rendered on the phone from the exam payload this
  /// screen already loaded — the old build called a server PDF route that
  /// never existed, so the button always failed.
  Future<void> _shareMarksheetPdf() async {
    final data = _data;
    if (data == null) return;
    try {
      final bytes = await TeacherPdfs.examMarksheet(data);
      await AppPdf.share(bytes, 'marksheet_exam${widget.examId}.pdf');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('PDF error: $e')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final c in _commentControllers.values) {
      c.dispose();
    }
    for (final m in _partCtls.values) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _data = null;
    });
    try {
      final r = await Api.getFresh('/teacher/exams/${widget.examId}');
      if (!mounted || r is! Map) return;
      final exam = r['exam'];
      final entryFlag = exam is Map ? exam['entry_open'] : null;
      final examOpen =
          exam is Map &&
          (entryFlag == null ||
              entryFlag == true ||
              entryFlag == 1 ||
              entryFlag == '1') &&
          exam['status'] != 'published';
      final eventOpen = exam is Map && exam['event_id'] != null
          ? !(exam['event_is_published'] == true ||
                exam['event_is_published'] == 1 ||
                exam['event_is_published'] == '1')
          : true;
      if (!examOpen || !eventOpen) {
        setState(() {
          _error = 'Admin এই পরীক্ষায় number entry বন্ধ রেখেছেন।';
          _loading = false;
        });
        return;
      }
      _controllers = {};
      _commentControllers = {};
      _partCtls.clear();
      _lockedIds = {};
      _existingTotals = {};
      _published = r['exam']['status'] == 'published';
      _entryStatus = '${r['exam']['entry_status'] ?? 'draft'}';
      _subjectMine =
          r['exam']['subject_mine'] == 1 || r['exam']['subject_mine'] == true;
      _isMine = r['exam']['is_mine'] == 1 || r['exam']['is_mine'] == true;
      // NCTB mark structure (CQ/MCQ/Practical/Written/CA) for this subject.
      final ms = r['exam']['mark_structure'];
      _components = (ms is Map && ms['components'] is List)
          ? (ms['components'] as List)
          : const [];
      _componentMode = _components.isNotEmpty;
      for (final m in (r['marks'] as List)) {
        _commentControllers[m['student_id']] = TextEditingController(
          text: (m['comment'] ?? '').toString(),
        );
        _existingTotals[m['student_id']] = num.tryParse('${m['marks']}') ?? 0;
        if (_componentMode) {
          final map = <String, TextEditingController>{};
          for (final c in _components) {
            final k = c['key'] as String;
            final v = m[k];
            map[k] = TextEditingController(text: v == null ? '' : '$v');
          }
          _partCtls[m['student_id']] = map;
        } else {
          _controllers[m['student_id']] = TextEditingController(
            text: m['marks'].toString(),
          );
        }
        if (m['editable'] == 0 || m['editable'] == false) {
          _lockedIds.add(m['student_id']);
        }
      }
      _enteredCount = (r['marks'] as List).length;
      for (final s in (r['students'] as List)) {
        final sid = s['id'] as int;
        if (_componentMode) {
          if (!_partCtls.containsKey(sid)) {
            _partCtls[sid] = {
              for (final c in _components)
                c['key'] as String: TextEditingController(),
            };
          }
        } else {
          _controllers.putIfAbsent(sid, () => TextEditingController());
        }
        _commentControllers.putIfAbsent(sid, () => TextEditingController());
      }
      setState(() {
        _data = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'পরীক্ষার বর্তমান lock অবস্থা server থেকে যাচাই করা যায়নি। Internet/server সংযোগ পরীক্ষা করে আবার চেষ্টা করুন।';
        _loading = false;
      });
    }
  }

  num _partSum(int studentId) {
    final m = _partCtls[studentId];
    if (m == null) return _existingTotals[studentId] ?? 0;
    num sum = 0;
    var any = false;
    for (final c in m.values) {
      final v = num.tryParse(c.text.trim());
      if (v != null) {
        sum += v;
        any = true;
      }
    }
    return any ? sum : (_existingTotals[studentId] ?? 0);
  }

  List<Map<String, dynamic>> _collectRecords() {
    final records = <Map<String, dynamic>>[];
    final defaultTotal = _fullMarks;
    for (final s in (_data!['students'] as List)) {
      final sid = s['id'] as int;
      if (_componentMode) {
        final m = _partCtls[sid];
        if (m == null || m.values.every((c) => c.text.trim().isEmpty)) continue;
        final rec = <String, dynamic>{'student_id': sid, 'total': defaultTotal};
        for (final c in _components) {
          final k = c['key'] as String;
          final v = m[k]?.text.trim() ?? '';
          rec[k] = v.isEmpty ? null : (num.tryParse(v) ?? 0);
        }
        rec['comment'] = _commentControllers[sid]?.text.trim() ?? '';
        records.add(rec);
      } else {
        final c = _controllers[sid];
        if (c == null || c.text.trim().isEmpty) continue;
        records.add({
          'student_id': sid,
          'marks': num.tryParse(c.text.trim()) ?? 0,
          'total': defaultTotal.toDouble(),
          'comment': _commentControllers[sid]?.text.trim() ?? '',
        });
      }
    }
    return records;
  }

  /// Q3/Q4: submit the completed sheet for class-teacher approval. The
  /// server hard-blocks on missing/out-of-range data and returns a list.
  Future<void> _submitForApproval() async {
    final messenger = ScaffoldMessenger.of(context);
    final records = _collectRecords();
    if (records.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Submit করার আগে marks দিন এবং Save করুন।'),
        ),
      );
      return;
    }
    try {
      final saved = await Api.post('/teacher/exams/${widget.examId}/marks', {
        'records': records,
      });
      if (Api.isQueued(saved)) {
        messenger.showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text(
              'Internet/server সংযোগ ছাড়া marks submit করা যাবে না।',
            ),
          ),
        );
        return;
      }
      final r = await Api.post('/teacher/exams/${widget.examId}/submit', {});
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.green,
          content: Text(
            r['self_approved'] == true
                ? 'Class teacher হিসেবে নিজের entry auto-approve হয়েছে।'
                : 'Class teacher-এর approval-এর জন্য পাঠানো হয়েছে।',
          ),
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Submit করা যায়নি'),
          content: SingleChildScrollView(child: Text(msg)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('বুঝেছি'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _saveMarks() async {
    final messenger = ScaffoldMessenger.of(context);
    final records = _collectRecords();
    if (records.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('কোনো marks দেওয়া হয়নি')));
      return;
    }
    setState(() => _saveState = 'saving');
    try {
      final r = await Api.post('/teacher/exams/${widget.examId}/marks', {
        'records': records,
      });
      if (!mounted) return;
      if (Api.isQueued(r)) {
        setState(() => _saveState = '');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text(
              'ইন্টারনেট নেই — number ফোনে সেভ আছে, online হলেই server-এ যাবে',
            ),
          ),
        );
        return;
      }
      setState(() => _saveState = 'saved');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.teal,
          content: Text(r['message'] ?? 'Saved'),
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saveState = 'error');
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _notify() async {
    final messenger = ScaffoldMessenger.of(context);
    final students = (_data?['students'] as List?) ?? const [];
    final ids = students.map((s) => s['id']).toList();
    if (ids.isEmpty) return;
    try {
      final r = await Api.post('/teacher/notify', {
        'student_ids': ids,
        'title': 'ผลสอบ published',
        'body': '${widget.examName} - result Published',
        'exam_id': widget.examId,
      });
      if (!mounted) return;
      if (Api.isQueued(r)) {
        messenger.showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text(
              'ইন্টারনেট নেই — notification queue-তে আছে, online হলে যাবে',
            ),
          ),
        );
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.green,
          content: Text(
            '${r['notified']} জন student-এর guardian-কে জানানো হয়েছে',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _finalizeWithAbsent() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await Api.post('/teacher/exams/${widget.examId}/finalize');
      if (!mounted) return;
      if (r['confirm'] != true) return;
      final absent = (r['absent_students'] as List?) ?? [];
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Finalize করবেন?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'মোট: ${r['total_students']} জন • Entry হয়েছে: ${r['marked']} জন • Absent হবে: ${r['to_be_marked_absent']} জন',
              ),
              const SizedBox(height: 8),
              const Text(
                'নম্বর না দেওয়া শিক্ষার্থীরা Absent হিসেবে গণ্য হবে। শুধু approved leave/exemption থাকলে বাদ যাবে।',
                style: TextStyle(fontSize: 13),
              ),
              if (absent.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 140,
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: absent.length,
                    itemBuilder: (_, i) => Text(
                      '${absent[i]['roll']} — ${absent[i]['name']}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('বাতিল'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Finalize + Submit'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      final c = await Api.post(
        '/teacher/exams/${widget.examId}/finalize-confirm',
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.green,
          content: Text(c['message'] ?? 'Published'),
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _ctApprove() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Api.post('/teacher/exams/${widget.examId}/ct-approve', {});
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          backgroundColor: Colors.green,
          content: Text('Approved ✓'),
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _ctReject() async {
    final reasonCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject করবেন?'),
        content: TextField(
          controller: reasonCtl,
          decoration: const InputDecoration(
            hintText: 'Reject করার কারণ লিখুন',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final reason = reasonCtl.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Reject করার কারণ লিখুন।')));
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Api.post('/teacher/exams/${widget.examId}/ct-reject', {
        'reason': reason,
      });
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orange,
          content: Text(
            'Rejected — সংশোধনের জন্য Admin re-entry approval চাইতে হবে।',
          ),
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _requestExamReentry() async {
    final reasonCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('নম্বর সংশোধনের আবেদন'),
        content: TextField(
          controller: reasonCtl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'কেন পুনরায় entry দরকার? *',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('আবেদন পাঠান'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await Api.post('/teacher/exams/${widget.examId}/reentry-request', {
        'reason': reasonCtl.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Admin-এর কাছে re-entry আবেদন পাঠানো হয়েছে।'),
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

  @override
  Widget build(BuildContext context) {
    // Scientific role split (mirrors backend can_enter):
    // - assigned subject teacher (or own-test creator) → full entry + edit.
    // - class teacher (other subject) → read-only supervisor + endorse right.
    // Class-teacher status grants supervision/approval only. It must never
    // grant marks entry for another teacher's subject.
    final canEdit =
        _data?['exam']?['can_enter'] == 1 ||
        _data?['exam']?['can_enter'] == true ||
        (_data?['exam']?['can_enter'] == null && (_subjectMine || _isMine));
    final isSupervisor =
        !canEdit &&
        ((_data?['exam']?['is_class_teacher'] == 1) ||
            (_data?['exam']?['is_class_teacher'] == true));
    final reentry = _data?['reentry_request'] is Map
        ? _data!['reentry_request'] as Map
        : null;
    final rejectReason = (_data?['exam']?['reject_reason'] ?? '')
        .toString()
        .trim();
    final dl = (_data?['exam'] ?? {})['entry_deadline']?.toString();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.examName),
        actions: [
          // Explicit save status.
          if (_saveState.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Text(
                  _saveState == 'saving'
                      ? 'Saving…'
                      : (_saveState == 'saved' ? 'Saved ✓' : 'Save failed'),
                  style: TextStyle(
                    fontSize: 11,
                    color: _saveState == 'error' ? Colors.red : Colors.white70,
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Marks Sheet PDF',
            onPressed: _shareMarksheetPdf,
          ),
          if (_published)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: Chip(
                  backgroundColor: Colors.green,
                  label: Text(
                    'Published',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Center(
                child: Chip(
                  backgroundColor: _entryStatus == 'approved'
                      ? Colors.teal
                      : (_entryStatus == 'submitted'
                            ? Colors.orange
                            : Colors.blueGrey),
                  label: Text(
                    _entryStatus == 'approved'
                        ? 'Approved'
                        : (_entryStatus == 'submitted'
                              ? 'Awaiting approval'
                              : 'Draft'),
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton:
          (_loading ||
              _saveState == 'saving' ||
              _published ||
              !canEdit ||
              _entryStatus == 'submitted' ||
              _entryStatus == 'approved')
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'finalize',
                  backgroundColor: Colors.deepOrange,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Finalize with Absent'),
                  onPressed: _finalizeWithAbsent,
                ),
                const SizedBox(height: 8),
                FloatingActionButton.extended(
                  heroTag: 'submit',
                  backgroundColor: Colors.green.shade700,
                  icon: const Icon(Icons.send),
                  label: const Text('Submit for Approval'),
                  onPressed: _submitForApproval,
                ),
                const SizedBox(height: 8),
                FloatingActionButton.extended(
                  heroTag: 'save',
                  icon: const Icon(Icons.save),
                  label: const Text('Save Marks'),
                  onPressed: _saveMarks,
                ),
              ],
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : Column(
              children: [
                if (!canEdit)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Card(
                      color: Colors.blueGrey.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(
                              isSupervisor
                                  ? Icons.supervisor_account_outlined
                                  : Icons.visibility_outlined,
                              color: Colors.blueGrey,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                isSupervisor
                                    ? '👁️ Class teacher view — আপনি supervisor: দেখতে পারেন, number দিতে/বদলাতে পারবেন না। অন্য teacher-এর re-edit request-এ endorse দিতে পারেন।'
                                    : 'এই subject আপনাকে assigned নয় — শুধু দেখতে পারবেন (read-only)। Marks দিতে পারবেন assigned teacher।',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.blueGrey.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (isSupervisor &&
                    _entryStatus == 'submitted' &&
                    ((_data?['exam']?['reject_reason'] ?? '')
                        .toString()
                        .isEmpty))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Card(
                      color: Colors.green.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.rule_folder_outlined,
                                  color: Colors.green,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '📋 Class teacher approval বাকি — approve করলে result publish-ready হবে।',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.green,
                                  ),
                                  icon: const Icon(Icons.check, size: 18),
                                  label: const Text('Approve'),
                                  onPressed: _ctApprove,
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.close, size: 18),
                                  label: const Text('Reject'),
                                  onPressed: _ctReject,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (isSupervisor &&
                    _entryStatus == 'submitted' &&
                    ((_data?['exam']?['reject_reason'] ?? '')
                        .toString()
                        .isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Card(
                      color: Colors.orange.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Marks sheet reject করা হয়েছে। কারণ: ${_data?['exam']?['reject_reason']}\nসংশোধনের জন্য subject teacher-কে Admin re-entry approval চাইতে হবে।',
                        ),
                      ),
                    ),
                  ),
                if (isSupervisor && _entryStatus == 'approved')
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Card(
                      color: Colors.teal.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.teal),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                '✅ Approved — admin publish করলে guardian-রা result দেখতে পাবে।',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (dl != null && dl.isNotEmpty && dl != 'null')
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Card(
                      color: Colors.orange.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.event_busy_outlined,
                              color: Colors.deepOrange,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Entry deadline: ${dl.replaceAll('T', ' ').substring(0, 16)} পর্যন্ত',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_entryStatus == 'draft')
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Card(
                      color: Colors.blue.shade50,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Draft হিসেবে Save করলে submit না করা পর্যন্ত নম্বর edit করা যাবে।',
                        ),
                      ),
                    ),
                  ),
                if (canEdit && ['submitted', 'approved'].contains(_entryStatus))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Card(
                      color: Colors.deepPurple.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.edit_note_rounded,
                              color: Colors.deepPurple,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                rejectReason.isNotEmpty
                                    ? 'Reject-এর কারণ: $rejectReason\nAdmin re-entry approval চাইলে নম্বর edit করা যাবে।'
                                    : reentry != null
                                    ? 'Re-entry আবেদন Admin-এর approval-এর অপেক্ষায়।'
                                    : 'Submit-এর পর নম্বর edit করতে Admin-এর অনুমোদনের আবেদন করুন.',
                              ),
                            ),
                            if (reentry == null)
                              FilledButton.tonal(
                                onPressed: _requestExamReentry,
                                child: const Text('Re-entry চান'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (!_loading && _error == null && _data != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Card(
                      color: Colors.teal.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.fact_check_outlined,
                              color: Colors.teal,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Coverage: $_enteredCount/${(_data!['students'] as List).length} জন student-এর number entry হয়েছে',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(
                      left: 12,
                      right: 12,
                      bottom: 90,
                    ),
                    itemCount: (_data!['students'] as List).length,
                    itemBuilder: (_, i) {
                      final s = _data!['students'][i];
                      final sid = s['id'] as int;
                      final locked =
                          _published ||
                          !canEdit ||
                          _entryStatus == 'submitted' ||
                          _entryStatus == 'approved' ||
                          _lockedIds.contains(sid);
                      final grade = NctbGrade.fromMarks(
                        _partSum(sid),
                        _fullMarks,
                      );
                      final gColor = grade.letter == 'F'
                          ? Colors.red
                          : (grade.point >= 4.0 ? Colors.green : Colors.orange);
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 6,
                            horizontal: 4,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const SizedBox(width: 4),
                                  CircleAvatar(child: Text('${s['roll']}')),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(s['name'])),
                                  // Real-time grade chip (NCTB A+/A/A-/B/C/D/F).
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: gColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${grade.letter} • ${grade.point.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: gColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                              ),
                              if (_componentMode)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 6,
                                    left: 4,
                                  ),
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      for (final c in _components)
                                        SizedBox(
                                          width: 92,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${c['label']} / ${c['full']}',
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.black54,
                                                ),
                                              ),
                                              TextField(
                                                controller:
                                                    _partCtls[sid]?[c['key']],
                                                enabled: !locked,
                                                keyboardType:
                                                    TextInputType.number,
                                                textAlign: TextAlign.center,
                                                onChanged: (_) {
                                                  setState(() {});
                                                },
                                                decoration:
                                                    const InputDecoration(
                                                      hintText: '0',
                                                      border:
                                                          OutlineInputBorder(),
                                                      isDense: true,
                                                      contentPadding:
                                                          EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 8,
                                                          ),
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                )
                              else
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 6,
                                    left: 4,
                                  ),
                                  child: SizedBox(
                                    width: 120,
                                    child: TextField(
                                      controller: _controllers[sid],
                                      enabled: !locked,
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      onChanged: (_) {
                                        setState(() {});
                                      },
                                      decoration: InputDecoration(
                                        hintText:
                                            'Marks / ${_fullMarks.toInt()}',
                                        border: const OutlineInputBorder(),
                                        isDense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 8,
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                              if (locked)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 4,
                                    left: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      const Text(
                                        '🔒 Locked',
                                        style: TextStyle(
                                          color: Colors.red,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 4,
                                    left: 4,
                                  ),
                                  child: TextField(
                                    controller: _commentControllers[sid],
                                    enabled: !locked,
                                    decoration: const InputDecoration(
                                      hintText: 'Comment (optional)',
                                      isDense: true,
                                      border: InputBorder.none,
                                    ),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Guardian notify: ONLY for the teacher's OWN exams.
                // Admin exam-এর ক্ষেত্রে class teacher-ও পাঠাতে পারবে না।
                if (_isMine)
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.notifications_active),
                        label: const Text('Result Notification → Guardians'),
                        onPressed: _notify,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
