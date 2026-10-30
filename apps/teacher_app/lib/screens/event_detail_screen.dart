import 'package:flutter/material.dart';

import '../api.dart';
import '../nctb_grading.dart';
import '../pdf/app_pdf.dart';
import '../pdf/teacher_pdfs.dart';
import 'exam_detail_screen.dart';

/// One event + one class: coverage header, student-wise result table,
/// seat plan preview + seat/admit PDF view-download (admin exams only).
class EventDetailScreen extends StatefulWidget {
  final int eventId;
  final String eventName;
  final Map? event;
  const EventDetailScreen({
    super.key,
    required this.eventId,
    required this.eventName,
    this.event,
  });
  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  List _classes = [];
  int? _classId;
  Map? _result;
  Map? _seatPlan;
  Map? _entryData;
  bool _loading = true;
  bool _resultLoading = false;
  bool _entryLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _classes = ((widget.event?['my_classes']) as List?) ?? const [];
    if (_classes.isNotEmpty) _classId = _classes.first['class_id'];
    _loading = false;
    if (_classId != null) {
      _loadResult();
      _loadEntry();
    }
  }

  Future<void> _loadResult() async {
    if (_classId == null) return;
    if (_result == null)
      setState(() {
        _resultLoading = true;
        _error = null;
      });
    try {
      await Api.loadCachedFirst(
        '/teacher/events/${widget.eventId}/result?class_id=$_classId',
        (r) {
          if (!mounted || r is! Map) return;
          setState(() {
            _result = r;
            _resultLoading = false;
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _resultLoading = false;
      });
    }
  }

  /// Marks-entry subjects: ONLY this class's assigned subjects (backend
  /// scopes by class_id). Each row opens number entry for that subject.
  Future<void> _loadEntry() async {
    if (_classId == null) return;
    if (_entryData == null) setState(() => _entryLoading = true);
    try {
      await Api.loadCachedFirst(
        '/teacher/events/${widget.eventId}/entry-subjects?class_id=$_classId',
        (r) {
          if (!mounted || r is! Map) return;
          setState(() {
            _entryData = r;
            _entryLoading = false;
          });
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _entryLoading = false);
    }
  }

  Future<void> _openEntry(Map subj) async {
    if (_classId == null) return;
    final subjName = subj['subject_name']?.toString() ?? 'Exam';
    final examId = await showDialog<int>(
      context: context,
      builder: (_) => MarksEntryDialog(
        eventId: widget.eventId,
        eventName: widget.eventName,
        classId: _classId!,
        subject: subj,
      ),
    );
    if (examId != null && examId > 0) {
      _loadEntry();
      _loadResult();
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ExamDetailScreen(examId: examId, examName: subjName),
        ),
      );
      _loadEntry();
      _loadResult();
    } else {
      _loadEntry();
      _loadResult();
    }
  }

  Future<void> _loadSeatPlan() async {
    if (_classId == null) return;
    try {
      final r = await Api.get(
        '/teacher/events/${widget.eventId}/seat-plan?class_id=$_classId&rooms=2',
      );
      if (!mounted) return;
      setState(() {
        _seatPlan = r;
      });
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

  /// Seat plan + admit cards are rendered on the phone from the JSON these
  /// endpoints return; no server-side PDF renderer is involved.
  Future<void> _showSeatPdf({required bool share}) async {
    if (_classId == null) return;
    try {
      final r =
          _seatPlan ??
          await Api.get(
            '/teacher/events/${widget.eventId}/seat-plan?class_id=$_classId&rooms=2',
          );
      if (!mounted) return;
      setState(() {
        _seatPlan = r;
      });
      final bytes = await TeacherPdfs.seatPlan(r);
      if (share) {
        await AppPdf.share(bytes, 'seatplan_${widget.eventId}_$_classId.pdf');
      } else {
        await AppPdf.preview(bytes);
      }
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

  Future<void> _showAdmitPdf({required bool share}) async {
    if (_classId == null) return;
    try {
      final r = await Api.get(
        '/teacher/events/${widget.eventId}/admit-cards?class_id=$_classId',
      );
      if (!mounted) return;
      final bytes = await TeacherPdfs.admitCards(r);
      if (share) {
        await AppPdf.share(bytes, 'admit_${widget.eventId}_$_classId.pdf');
      } else {
        await AppPdf.preview(bytes);
      }
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

  bool get _canPrintClassResults {
    final rows = (_result?['rows'] as List?) ?? const [];
    // Subject teachers receive only their own subject rows from the API.
    // Keep the full transcript action limited to the class-wide result scope.
    return rows.any((row) => row is Map && row['scoped'] != true);
  }

  Future<void> _showResultPdf({required bool share}) async {
    final result = _result;
    if (result == null || !_canPrintClassResults) return;
    try {
      final meta = await Api.get(
        '/teacher/events/${widget.eventId}/result-pdf-metadata?class_id=$_classId',
      );
      final payload = <String, dynamic>{...result, if (meta is Map) ...meta};
      final bytes = await TeacherPdfs.classResultCards(payload);
      if (share) {
        await AppPdf.share(
          bytes,
          'result_marksheets_${widget.eventId}_$_classId.pdf',
        );
      } else {
        await AppPdf.preview(bytes);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            'PDF error: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
  }

  static bool _pastDeadline(String raw) {
    try {
      return DateTime.now().isAfter(DateTime.parse(raw.replaceAll(' ', 'T')));
    } catch (_) {
      return false;
    }
  }

  static String _fmtDeadline(String raw) {
    final s = raw.replaceAll('T', ' ');
    return s.length >= 16 ? s.substring(0, 16) : s;
  }

  @override
  Widget build(BuildContext context) {
    final cov = _result?['coverage'];
    final rows = (_result?['rows'] as List?) ?? const [];
    final subjects = (_result?['subjects'] as List?) ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.eventName, style: const TextStyle(fontSize: 16)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (_classes.length > 1)
                  DropdownButtonFormField<int>(
                    initialValue: _classId,
                    decoration: const InputDecoration(
                      labelText: 'শ্রেণী নির্বাচন করুন (Section অনুযায়ী)',
                      border: OutlineInputBorder(),
                    ),
                    items: _classes
                        .map<DropdownMenuItem<int>>(
                          (c) => DropdownMenuItem<int>(
                            value: c['class_id'],
                            child: Text(
                              '${c['class_name']} ${c['group_name'] ?? c['section'] ?? ''}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      setState(() {
                        _classId = v;
                        _seatPlan = null;
                        _entryData = null;
                        _result = null;
                      });
                      _loadResult();
                      _loadEntry();
                    },
                  ),
                if (_classes.length > 1) const SizedBox(height: 10),
                if (_resultLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_error != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  )
                else if (cov != null) ...[
                  Card(
                    color: Colors.teal.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Number Entry Coverage',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '👥 ${cov['with_result']}/${cov['student_count']} জন student-এর data entry হয়েছে',
                          ),
                          Text(
                            '📚 ${cov['subjects_with_marks']}/${cov['subject_count']} টি subject-এর number add হয়েছে',
                          ),
                          const SizedBox(height: 6),
                          // Collapsed subject rows (progressive disclosure): title +
                          // count first; tap to expand per-subject entered/pending.
                          _SubjectCoverageList(
                            subjects: (cov['subjects'] as List? ?? const []),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // ---- Marks entry: only this class's assigned subjects ----
                  Card(
                    color: Colors.indigo.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Marks Entry — এই Class-এর Subjects',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              if (_entryLoading)
                                const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _entryData == null
                                ? 'লোড হচ্ছে…'
                                : '${_entryData!['submitted_subjects'] ?? 0}/${_entryData!['assigned_subjects'] ?? 0} টি subject-এ entry হয়েছে',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 6),
                          for (final s
                              in ((_entryData?['subjects'] as List?) ??
                                  const []))
                            Builder(
                              builder: (_) {
                                final open =
                                    (s['entry_open'] as num?)?.toInt() ?? 1;
                                final isPublished = s['exam_published'] == true;
                                final dead = s['exam_entry_deadline']
                                    ?.toString();
                                final closed =
                                    isPublished ||
                                    open == 0 ||
                                    (dead != null &&
                                        dead.isNotEmpty &&
                                        _pastDeadline(dead));
                                final mine =
                                    (s['is_mine'] == 1 || s['is_mine'] == true);
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 3,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${s['subject_name']}',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Text(
                                              isPublished
                                                  ? '✅ Published — entry বন্ধ'
                                                  : (open == 0
                                                        ? '🔒 Admin entry বন্ধ রেখেছে'
                                                        : (dead != null &&
                                                                  dead.isNotEmpty &&
                                                                  _pastDeadline(
                                                                    dead,
                                                                  )
                                                              ? '⏰ Deadline পার (${_fmtDeadline(dead)})'
                                                              : (mine
                                                                    ? '✓ আপনার subject${dead != null && dead.isNotEmpty ? ' • ⏰ ${_fmtDeadline(dead)} পর্যন্ত' : ''}'
                                                                    : 'শিক্ষক: ${s['subject_teacher_name'] ?? '—'}'))),
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: closed
                                                    ? Colors.red.shade700
                                                    : Colors.black54,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: (s['submitted'] == true)
                                              ? Colors.green.shade100
                                              : Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Text(
                                          (s['submitted'] == true)
                                              ? '${s['entered_count']}/${s['student_count']} ✓'
                                              : 'Pending',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: (s['submitted'] == true)
                                                ? Colors.green.shade800
                                                : Colors.grey.shade700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      FilledButton.tonal(
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        onPressed: closed && !mine
                                            ? null
                                            : () => _openEntry(s as Map),
                                        child: Text(
                                          isPublished
                                              ? 'দেখুন'
                                              : (mine ? 'Entry' : 'খুলুন'),
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_canPrintClassResults) ...[
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.description_outlined),
                          label: const Text('Result PDF দেখুন'),
                          onPressed: () => _showResultPdf(share: false),
                        ),
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('Result PDF শেয়ার'),
                          onPressed: () => _showResultPdf(share: true),
                        ),
                      ],
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.event_seat_outlined),
                        label: const Text('Seat Plan'),
                        onPressed: _loadSeatPlan,
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Seat PDF দেখুন'),
                        onPressed: () => _showSeatPdf(share: false),
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Seat PDF শেয়ার'),
                        onPressed: () => _showSeatPdf(share: true),
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.badge_outlined),
                        label: const Text('Admit PDF দেখুন'),
                        onPressed: () => _showAdmitPdf(share: false),
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Admit PDF শেয়ার'),
                        onPressed: () => _showAdmitPdf(share: true),
                      ),
                    ],
                  ),
                  if (_seatPlan != null) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'Seat Plan Preview',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    for (final rm in (_seatPlan!['rooms'] as List? ?? const []))
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${rm['room']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              for (final p
                                  in (rm['seats'] as List? ?? const []))
                                Text(
                                  '• ${(p[0] as Map?)?['roll']}. ${(p[0] as Map?)?['name'] ?? ''}'
                                  '${p.length > 1 && p[1] != null ? '  |  ${(p[1] as Map)['roll']}. ${(p[1] as Map)['name']}' : ''}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 10),
                  const Text(
                    'Student-wise Result',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        Colors.blueGrey.shade50,
                      ),
                      columns: [
                        const DataColumn(label: Text('Roll')),
                        const DataColumn(label: Text('Name')),
                        for (final s in subjects)
                          DataColumn(
                            label: Text(
                              '$s',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        const DataColumn(label: Text('GPA')),
                        const DataColumn(label: Text('Result')),
                      ],
                      rows: rows.map<DataRow>((r) {
                        final fams = (r['_families'] as List?) ?? const [];
                        return DataRow(
                          cells: [
                            DataCell(Text('${r['roll']}')),
                            DataCell(
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 120,
                                ),
                                child: Text(
                                  '${r['name']}',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                            for (var i = 0; i < subjects.length; i++)
                              DataCell(
                                Text(
                                  fams.length > i && fams[i] != null
                                      ? '${fams[i]['total']}/${fams[i]['full']} (${fams[i]['letter_grade']})'
                                      : '-',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            DataCell(
                              Text(
                                r['final_gpa'] != null
                                    ? '${r['final_gpa']}'
                                    : '-',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                '${r['result_status'] ?? '-'}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: r['result_status'] == 'PASSED'
                                      ? Colors.green
                                      : Colors.red,
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

/// Number-entry dialog for ONE class-assigned subject inside an event.
/// Prefills existing marks when the subject-exam row already exists;
/// on save the backend auto-creates the row if missing. Returns exam_id.
// Collapsible subject-coverage rows: collapsed shows count only; tap a row
// to expand entered/pending detail. (Progressive disclosure — 12 subjects
// don't push the entry buttons off-screen.)
class _SubjectCoverageList extends StatefulWidget {
  final List subjects;
  const _SubjectCoverageList({required this.subjects});
  @override
  State<_SubjectCoverageList> createState() => _SubjectCoverageListState();
}

class _SubjectCoverageListState extends State<_SubjectCoverageList> {
  final Set<int> _open = {};

  @override
  Widget build(BuildContext context) {
    if (widget.subjects.isEmpty) {
      return const Text(
        'এখনো কোনো subject-এ entry হয়নি',
        style: TextStyle(fontSize: 12, color: Colors.black54),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < widget.subjects.length; i++)
          Builder(
            builder: (_) {
              final s = widget.subjects[i];
              final entered = (s['entered_count'] as num?)?.toInt() ?? 0;
              final done = entered > 0;
              final isOpen = _open.contains(i);
              return Column(
                children: [
                  InkWell(
                    onTap: () => setState(() {
                      isOpen ? _open.remove(i) : _open.add(i);
                    }),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Icon(
                            isOpen ? Icons.expand_less : Icons.expand_more,
                            size: 16,
                            color: Colors.black54,
                          ),
                          Expanded(
                            child: Text(
                              '${s['subject_name']}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '$entered জন',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: done ? Colors.green.shade700 : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    child: isOpen
                        ? Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(left: 22, bottom: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              done
                                  ? '✓ $entered জন student-এর number entry হয়েছে'
                                  : '⏳ এখনো entry হয়নি — নিচের Marks Entry থেকে দিন',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Colors.black87,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class MarksEntryDialog extends StatefulWidget {
  final int eventId;
  final String eventName;
  final int classId;
  final Map subject;
  final bool canEdit;
  const MarksEntryDialog({
    super.key,
    required this.eventId,
    required this.eventName,
    required this.classId,
    required this.subject,
    this.canEdit = true,
  });
  @override
  State<MarksEntryDialog> createState() => MarksEntryDialogState();
}

class MarksEntryDialogState extends State<MarksEntryDialog> {
  List _students = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  final Map<int, TextEditingController> _ctls = {};
  // Component-wise controllers: studentId -> { cq: ctl, mcq: ctl, ... }
  final Map<int, Map<String, TextEditingController>> _partCtls = {};

  List get _components => (widget.subject['components'] as List?) ?? const [];
  bool get _componentMode => _components.isNotEmpty;
  num get _fullMarks =>
      num.tryParse('${widget.subject['full_marks'] ?? 100}') ?? 100;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctls.values) {
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
    try {
      final st = await Api.get('/teacher/classes/${widget.classId}/students');
      final list = st is List ? st : [];
      Map<int, Map<String, dynamic>> existing = {};
      final examId = widget.subject['exam_id'];
      if (examId != null) {
        try {
          final d = await Api.get('/teacher/exams/$examId');
          for (final m in ((d as Map?)?['marks'] as List?) ?? const []) {
            existing[m['student_id'] as int] = Map<String, dynamic>.from(m);
          }
        } catch (_) {}
      }
      if (!mounted) return;
      for (final s in list) {
        final id = s['id'] as int;
        final prev = existing[id];
        if (_componentMode) {
          final map = <String, TextEditingController>{};
          for (final c in _components) {
            final k = c['key'] as String;
            final v = prev?[k];
            map[k] = TextEditingController(text: v == null ? '' : '$v');
          }
          _partCtls[id] = map;
        } else {
          _ctls[id] = TextEditingController(
            text: prev == null ? '' : '${prev['marks']}',
          );
        }
      }
      setState(() {
        _students = list;
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

  /// Live component sum for a student (0 when nothing typed).
  num _partSum(int studentId) {
    final m = _partCtls[studentId];
    if (m == null) return 0;
    num sum = 0;
    for (final c in m.values) {
      sum += num.tryParse(c.text.trim()) ?? 0;
    }
    return sum;
  }

  Widget _gradeChip(num marks) {
    final g = NctbGrade.fromMarks(marks, _fullMarks);
    final color = g.letter == 'F'
        ? Colors.red
        : (g.point >= 4.0 ? Colors.green : Colors.orange);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${g.letter} • ${g.point.toStringAsFixed(2)}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!widget.canEdit) {
      Navigator.pop(context);
      return;
    }
    final records = <Map<String, dynamic>>[];
    if (_componentMode) {
      for (final s in _students) {
        final m = _partCtls[s['id']];
        if (m == null) continue;
        // skip students with every component blank
        if (m.values.every((c) => c.text.trim().isEmpty)) continue;
        final rec = <String, dynamic>{
          'student_id': s['id'],
          'total': _fullMarks,
        };
        for (final c in _components) {
          final k = c['key'] as String;
          final v = m[k]?.text.trim() ?? '';
          final n = v.isEmpty ? null : num.tryParse(v);
          if (v.isNotEmpty && n == null) {
            setState(
              () => _error = 'Roll ${s['roll']} — ${c['label']} সঠিক নয়',
            );
            return;
          }
          if (n != null && (c['full'] is num) && n > (c['full'] as num)) {
            setState(
              () => _error =
                  'Roll ${s['roll']} — ${c['label']} সর্বোচ্চ ${c['full']}',
            );
            return;
          }
          rec[k] = n;
        }
        records.add(rec);
      }
    } else {
      for (final s in _students) {
        final t = _ctls[s['id']]?.text.trim() ?? '';
        if (t.isEmpty) continue;
        final v = num.tryParse(t);
        if (v == null) {
          setState(() => _error = 'Roll ${s['roll']}-এর number সঠিক নয়');
          return;
        }
        records.add({'student_id': s['id'], 'marks': v, 'total': _fullMarks});
      }
    }
    if (records.isEmpty) {
      setState(() => _error = 'কোনো number দেওয়া হয়নি');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final r = await Api.post('/teacher/events/${widget.eventId}/marks', {
        'class_id': widget.classId,
        'subject_id': widget.subject['subject_id'],
        'records': records,
      });
      if (!mounted) return;
      if (Api.isQueued(r)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text(
              'ইন্টারনেট নেই — number ফোনে সেভ আছে, online হলেই server-এ যাবে',
            ),
          ),
        );
        Navigator.pop(context, 0);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green,
          content: Text(
            '${r['message'] ?? 'Saved'} (exam #${r['exam_id'] ?? '?'})',
          ),
        ),
      );
      Navigator.pop(context, (r['exam_id'] as num?)?.toInt() ?? 0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _saving = false;
      });
    }
  }

  Widget _studentRow(Map s) {
    final id = s['id'] as int;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                child: Text(
                  '${s['roll']}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${s['name']}',
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_componentMode) _gradeChip(_partSum(id)),
            ],
          ),
          const SizedBox(height: 4),
          if (_componentMode)
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final c in _components)
                  SizedBox(
                    width: 96,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${c['label']} / ${c['full']}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.black54,
                          ),
                        ),
                        TextField(
                          controller: _partCtls[id]?[c['key']],
                          keyboardType: TextInputType.number,
                          readOnly: !widget.canEdit,
                          textAlign: TextAlign.center,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            hintText: '0',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 90,
                child: TextField(
                  controller: _ctls[id],
                  keyboardType: TextInputType.number,
                  readOnly: !widget.canEdit,
                  textAlign: TextAlign.center,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: '/ ${_fullMarks.toInt()}',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final full = '${widget.subject['full_marks'] ?? 100}';
    return AlertDialog(
      title: Text(
        '${widget.subject['subject_name']} — Entry',
        style: const TextStyle(fontSize: 16),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _loading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${widget.eventName} • মোট $full-তে${_componentMode ? ' (CQ/MCQ/PR/CA)' : ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    for (final s in _students) _studentRow(s),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(widget.canEdit ? 'বাতিল' : 'বন্ধ করুন'),
        ),
        if (widget.canEdit)
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
      ],
    );
  }
}
