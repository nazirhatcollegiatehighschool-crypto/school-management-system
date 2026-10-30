import 'package:flutter/material.dart';

import '../api.dart';
import '../pdf/admin_pdfs.dart';
import '../pdf/app_pdf.dart';

/// Promotion Dashboard — Admin UI for student promotion.
///
/// Workflow:
/// 1. Configure promotion rules (per class + exam type)
/// 2. Select class + promotion-source event
/// 3. Calculate eligibility (mandatory-pass + grace + GPA rules)
/// 4. Review auto-calculated statuses, override individual students
/// 5. Bulk approve / bulk retain
/// 6. Execute promotion (moves students to the next class, assigns rolls)
/// 7. Export the promotion report (on-device PDF) and read the audit history
///
/// All API paths are mounted under `/api/admin`, e.g. `/admin/promotion/status`.
class PromotionScreen extends StatefulWidget {
  const PromotionScreen({super.key});

  @override
  State<PromotionScreen> createState() => _PromotionScreenState();
}

class _PromotionScreenState extends State<PromotionScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);

  // Top-bar selection
  List _classes = [];
  List _events = [];
  List _sessions = [];
  int? _classId;
  int? _eventId;
  int? _targetSessionId;
  bool _loading = false;
  String _error = '';
  String _statusMsg = '';

  // Tab 1 — rules
  List _rules = [];
  bool _rulesLoading = false;

  // Tab 2 — eligibility calculation
  List _review = [];
  Map _calcSummary = {};
  bool _reviewed = false;

  // Tab 3 — status dashboard
  List _students = [];
  String _statusFilter = 'all';

  // Tab 4 — history
  List _history = [];
  List<Map<String, dynamic>> _groupRows = [];
  bool _groupLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadGroupApprovals();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ============================================================== DATA LOADING

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final results = await Future.wait([
        Api.get('/admin/classes'),
        Api.get('/results/events'),
        Api.get('/admin/sessions'),
      ]);
      if (!mounted) return;
      setState(() {
        _classes = results[0] is List ? results[0] : [];
        _events = results[1] is List ? results[1] : [];
        _sessions = results[2] is List ? results[2] : [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendly(e);
      });
    }
  }

  String _friendly(Object e) => e.toString().replaceFirst('Exception: ', '');

  Future<void> _loadGroupApprovals() async {
    setState(() {
      _groupLoading = true;
      _error = '';
    });
    try {
      final r = await Api.get('/admin/group-approval');
      if (!mounted) return;
      setState(() {
        _groupRows =
            (r is Map && r['students'] is List
                    ? r['students'] as List
                    : const [])
                .whereType<Map>()
                .map((v) => Map<String, dynamic>.from(v))
                .toList();
        _groupLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _groupLoading = false;
        _error = _friendly(e);
      });
    }
  }

  Future<void> _approveGroup(Map<String, dynamic> student) async {
    String? group, compulsory, optional;
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text('${student['name']} — Class 9 group approval'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: group,
                decoration: const InputDecoration(labelText: 'Group *'),
                items: const ['Arts', 'Commerce', 'Science']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setDialog(() {
                  group = v;
                  compulsory = null;
                  optional = null;
                }),
              ),
              if (group == 'Arts') ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: compulsory,
                  decoration: const InputDecoration(
                    labelText: 'Compulsory subject *',
                  ),
                  items: const ['Civics', 'Economics']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) => setDialog(() => compulsory = v),
                ),
              ],
              if (group != null && (group != 'Arts' || compulsory != null)) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: ValueKey(group),
                  initialValue: optional,
                  decoration: const InputDecoration(
                    labelText: 'Optional subject *',
                  ),
                  items:
                      (group == 'Science'
                              ? const [
                                  'Higher Mathematics',
                                  'Agriculture',
                                  'Home Science',
                                ]
                              : const ['Agriculture', 'Home Science'])
                          .map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          )
                          .toList(),
                  onChanged: (v) => setDialog(() => optional = v),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('বাতিল'),
            ),
            FilledButton(
              onPressed:
                  group == null ||
                      optional == null ||
                      (group == 'Arts' && compulsory == null)
                  ? null
                  : () => Navigator.pop(dialogContext, {
                      'group': group!,
                      'compulsory_subject': compulsory ?? '',
                      'optional_subject': optional!,
                    }),
              child: const Text('অনুমোদন করুন'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    try {
      await Api.post('/admin/group-assign', {
        'student_id': student['student_id'],
        'class_id': student['from_class_id'],
        'group': result['group'],
        'compulsory_subject': result['compulsory_subject'],
        'optional_subject': result['optional_subject'],
      });
      await _loadGroupApprovals();
      if (mounted) {
        setState(
          () => _statusMsg =
              '${student['name']} ${result['group']} group-এ অনুমোদিত হয়েছে',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    }
  }

  int? _yearOf(dynamic value) {
    final match = RegExp(r'(19|20)\d{2}').firstMatch(value?.toString() ?? '');
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  Map? get _activeSession {
    final active = _sessions
        .where((s) => s['is_active'] == true || s['is_active'] == 1)
        .toList();
    if (active.isNotEmpty) return active.first as Map;
    final sorted = [..._sessions]
      ..sort(
        (a, b) => (_yearOf(b['name']) ?? 0).compareTo(_yearOf(a['name']) ?? 0),
      );
    return sorted.isEmpty ? null : sorted.first as Map;
  }

  Map? _eventById(int? id) {
    for (final event in _events) {
      if ((event['id'] as num?)?.toInt() == id) return event as Map;
    }
    return null;
  }

  int? _nextSessionFor(Map? event) {
    if (event == null) return null;
    final sourceYear = _yearOf(event['year']) ?? _yearOf(event['session_name']);
    if (sourceYear == null) return null;
    for (final session in _sessions) {
      if (_yearOf(session['name']) == sourceYear + 1) {
        return (session['id'] as num?)?.toInt();
      }
    }
    return null;
  }

  // Only published promotion-source events are usable: Class 10 promotes from
  // a TEST event, Class 6–9 from an ANNUAL event.
  List get _promotionEvents {
    final cls = _selectedClass;
    if (RegExp(
      r'ssc',
      caseSensitive: false,
    ).hasMatch(cls?['name']?.toString() ?? '')) {
      return [];
    }
    final isClass10 =
        cls != null &&
        RegExp(
          r'class\s*10',
          caseSensitive: false,
        ).hasMatch(cls['name']?.toString() ?? '');
    final needKind = isClass10 ? 'test' : 'annual';
    final activeSession = _activeSession;
    final activeSessionId = (activeSession?['id'] as num?)?.toInt();
    final activeYear = _yearOf(activeSession?['name']);
    return _events.where((e) {
      if (e['is_published'] != 1 && e['is_published'] != true) return false;
      if (e['exam_kind']?.toString() != needKind) return false;
      if (activeSessionId != null &&
          (e['session_id'] as num?)?.toInt() != activeSessionId) {
        return false;
      }
      return activeYear == null || _yearOf(e['year']) == activeYear;
    }).toList();
  }

  Map? get _selectedClass {
    for (final c in _classes) {
      if ((c['id'] as num?)?.toInt() == _classId) return c;
    }
    return null;
  }

  String get _promotionKind {
    final name = _selectedClass?['name']?.toString() ?? '';
    return RegExp(r'class\s*10', caseSensitive: false).hasMatch(name)
        ? 'test'
        : 'annual';
  }

  bool get _activeExamYearMismatch {
    final session = _activeSession;
    final sessionId = (session?['id'] as num?)?.toInt();
    final sessionYear = _yearOf(session?['name']);
    if (sessionId == null || sessionYear == null) return false;
    return _events.any(
      (event) =>
          (event['is_published'] == 1 || event['is_published'] == true) &&
          event['exam_kind']?.toString() == _promotionKind &&
          (event['session_id'] as num?)?.toInt() == sessionId &&
          _yearOf(event['year']) != sessionYear,
    );
  }

  // ============================================================== TAB 1: RULES

  Future<void> _loadRules() async {
    if (_classId == null) {
      return;
    }
    setState(() {
      _rulesLoading = true;
    });
    try {
      final r = await Api.get('/admin/promotion-rules/class/$_classId');
      if (!mounted) return;
      setState(() {
        _rules = r is List ? r : [];
        _rulesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rulesLoading = false;
        _error = _friendly(e);
      });
    }
  }

  Future<void> _saveRule(String examType) async {
    if (_classId == null) return;
    final grace = await _askGrace(examType);
    if (grace == null) return;
    setState(() => _loading = true);
    try {
      await Api.put('/admin/promotion-rules', {
        'class_id': _classId,
        'exam_type': examType,
        'is_promotion_source': true,
        'min_passing_gpa': 2.0,
        'allow_conditional': true,
        'grace_failed_subjects': grace,
        'mandatory_subjects': const <String>[],
      });
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusMsg = '$examType নিয়ম সংরক্ষিত হয়েছে';
      });
      _loadRules();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendly(e);
      });
    }
  }

  Future<int?> _askGrace(String examType) async {
    var value = 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('$examType — Grace Limit'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'কত বিষয়ে fail হলেও ছাত্রটি শর্তসাপেক্ষে উত্তীর্ণ ধরা হবে?',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: value > 0 ? () => setD(() => value--) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text(
                    '$value',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: value < 11 ? () => setD(() => value++) : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('বাতিল'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    return ok == true ? value : null;
  }

  // ================================================= TAB 2: ELIGIBILITY CALC

  Future<void> _calculate() async {
    if (_classId == null || _eventId == null || _targetSessionId == null) {
      setState(
        () => _error =
            'শ্রেণি, প্রকাশিত ফলাফল এবং পরবর্তী শিক্ষাবর্ষ নির্বাচন/তৈরি করুন',
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
      _reviewed = false;
    });
    try {
      final r = await Api.post('/admin/promotion/calculate', {
        'class_id': _classId,
        'event_id': _eventId,
        'target_session_id': _targetSessionId,
      });
      if (!mounted) return;
      setState(() {
        _review = r['review'] is List ? (r['review'] as List) : [];
        _calcSummary = r['summary'] is Map ? Map.from(r['summary']) : {};
        _reviewed = true;
        _loading = false;
      });
      _loadStatus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendly(e);
      });
    }
  }

  Future<void> _override(
    int studentId,
    String status,
    String decision,
    String note,
  ) async {
    setState(() => _loading = true);
    try {
      await Api.put('/admin/promotion/status/$studentId', {
        'status': status,
        'decision': decision,
        'target_session_id': _targetSessionId,
        'admin_note': note,
      });
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusMsg = 'ছাত্রের সিদ্ধান্ত পরিবর্তন হয়েছে';
      });
      _calculate();
      _loadStatus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendly(e);
      });
    }
  }

  // ================================================== TAB 3: STATUS DASHBOARD

  Future<void> _loadStatus() async {
    if (_targetSessionId == null) return;
    setState(() => _loading = true);
    try {
      final params = <String, String>{
        'target_session_id': _targetSessionId.toString(),
      };
      final r = await Api.get('/admin/promotion/status', queryParams: params);
      if (!mounted) return;
      setState(() {
        _students = r is List ? r : [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendly(e);
      });
    }
  }

  List get _filteredStudents {
    if (_statusFilter == 'all') return _students;
    return _students
        .where((s) => s['status']?.toString() == _statusFilter)
        .toList();
  }

  List<int> get _selectedIds => _students
      .where((s) => s['selected'] == true)
      .map((s) => (s['student_id'] as num).toInt())
      .toList();

  Future<void> _bulkAction(String action) async {
    if (_targetSessionId == null) return;
    final ids = _selectedIds;
    if (ids.isEmpty) {
      setState(() => _error = 'কোনো ছাত্র নির্বাচন করা হয়নি');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(action == 'approve' ? 'স্বীকৃতি দিবেন?' : 'রক্ষণ করবেন?'),
        content: Text(
          '${ids.length} জন ছাত্রকে '
          '${action == 'approve' ? 'উত্তীর্ণ হিসেবে অনুমোদন' : 'রাখা হয়েছে হিসেবে চিহ্নিত'} করা হবে।',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('নিশ্চিত করুন'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _loading = true);
    try {
      final endpoint = action == 'approve'
          ? '/admin/promotion/bulk-approve'
          : '/admin/promotion/bulk-retain';
      final r = await Api.post(endpoint, {
        'student_ids': ids,
        'target_session_id': _targetSessionId,
      });
      if (!mounted) return;
      final count = action == 'approve'
          ? (r['approved'] ?? 0)
          : (r['retained'] ?? 0);
      setState(() {
        _loading = false;
        _statusMsg =
            '$count জন ছাত্রকে '
            '${action == 'approve' ? 'অনুমোদন' : 'রক্ষণ'} করা হয়েছে';
      });
      _loadStatus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendly(e);
      });
    }
  }

  Future<void> _executePromotion() async {
    if (_targetSessionId == null) return;
    final approvedCount = _students
        .where((s) => s['status'] == 'approved' && s['decision'] == 'promoted')
        .length;
    if (approvedCount == 0) {
      setState(() => _error = 'প্রমোট করার জন্য কোনো অনুমোদিত ছাত্র নেই');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('প্রমোশন নিশ্চিত করুন'),
        content: Text(
          '$approvedCount জনকে পরবর্তী শ্রেণিতে স্থানান্তর করা হবে। নিশ্চিত?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('নিশ্চিত করুন'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _loading = true);
    try {
      final r = await Api.post('/admin/promotion/execute', {
        'target_session_id': _targetSessionId,
      });
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusMsg = '${r['moved'] ?? 0} জন স্থানান্তরিত হয়েছে';
      });
      _loadStatus();
      _loadHistory();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_statusMsg)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendly(e);
      });
    }
  }

  // ================================================ TAB 4: HISTORY & REPORT

  Future<void> _loadHistory() async {
    if (_targetSessionId == null) return;
    setState(() => _loading = true);
    try {
      final params = <String, String>{
        'session_id': _targetSessionId.toString(),
      };
      final r = await Api.get('/admin/promotion/history', queryParams: params);
      if (!mounted) return;
      setState(() {
        _history = r is List ? r : [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendly(e);
      });
    }
  }

  /// The report is rendered on the phone (like every other PDF in this app),
  /// so it works even when the server only speaks JSON.
  Future<void> _exportReport() async {
    if (_targetSessionId == null) return;
    setState(() => _loading = true);
    try {
      final params = <String, String>{
        'session_id': _targetSessionId.toString(),
      };
      final r = await Api.get('/admin/promotion/report', queryParams: params);
      if (!mounted) return;
      final rows = r['data'] is List ? (r['data'] as List) : const [];
      final dynamic settings = await Api.get('/admin/settings');
      if (!mounted) return;
      setState(() => _loading = false);
      final bytes = await AdminPdfs.promotionReport(
        rows.cast<Map>(),
        settings: settings is Map ? settings : const {},
        sessionName: _sessionName(_targetSessionId),
      );
      await AppPdf.share(bytes, 'promotion_report_$_targetSessionId.pdf');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendly(e);
      });
    }
  }

  String _sessionName(int? id) {
    for (final s in _sessions) {
      if ((s['id'] as num?)?.toInt() == id) {
        return s['name']?.toString() ?? '';
      }
    }
    return '';
  }

  // ================================================================ LABELS

  String _statusLabel(String? status) {
    switch (status) {
      case 'eligible':
        return 'যোগ্য';
      case 'conditional':
        return 'শর্তসাপেক্ষ';
      case 'not_eligible':
        return 'যোগ্য নয়';
      case 'pending_results':
        return 'ফলাফল নেই';
      case 'pending_review':
        return 'রিভিউ';
      case 'approved':
        return 'অনুমোদিত';
      case 'promoted':
        return 'প্রমোটেড';
      case 'retained':
        return 'অনিয়মিত · আগের শ্রেণিতে';
      case 'admin_override':
        return 'ওভাররাইড';
      default:
        return status ?? '';
    }
  }

  String _decisionLabel(String? decision) {
    switch (decision) {
      case 'promoted':
        return 'প্রমোট';
      case 'retained':
        return 'Reject · অনিয়মিত';
      case 'conditional':
        return 'শর্তসাপেক্ষ';
      case 'admin_override':
        return 'ওভাররাইড';
      default:
        return decision ?? '';
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'eligible':
        return Colors.green;
      case 'conditional':
        return Colors.amber.shade800;
      case 'approved':
        return Colors.green.shade700;
      case 'promoted':
        return Colors.green;
      case 'retained':
        return Colors.red;
      case 'not_eligible':
        return Colors.red;
      case 'pending_review':
        return Colors.blue;
      case 'admin_override':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  Color _decisionColor(String? decision) {
    switch (decision) {
      case 'promoted':
        return Colors.green;
      case 'conditional':
        return Colors.amber.shade800;
      case 'retained':
        return Colors.red;
      case 'admin_override':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  // ================================================================ UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('শ্রেণি উত্তরণ'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'নিয়ম', icon: Icon(Icons.settings)),
            Tab(text: 'যোগ্যতা', icon: Icon(Icons.calculate)),
            Tab(text: 'ড্যাশবোর্ড', icon: Icon(Icons.dashboard)),
            Tab(text: 'রিপোর্ট', icon: Icon(Icons.assessment)),
            Tab(text: 'Group Approval', icon: Icon(Icons.group_add_outlined)),
          ],
        ),
      ),
      body: _loading && _classes.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _topBar(),
                if (_loading) const LinearProgressIndicator(),
                if (_error.isNotEmpty)
                  _banner(Icons.error, Colors.red, _error, () {
                    setState(() => _error = '');
                  }),
                if (_statusMsg.isNotEmpty)
                  _banner(Icons.check_circle, Colors.green, _statusMsg, null),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _rulesTab(),
                      _calculateTab(),
                      _statusTab(),
                      _historyTab(),
                      _groupApprovalTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _banner(
    IconData icon,
    Color color,
    String text,
    VoidCallback? onClose,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Card(
        color: color.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text, style: TextStyle(color: color)),
              ),
              if (onClose != null)
                IconButton(icon: const Icon(Icons.close), onPressed: onClose),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    final events = _promotionEvents;
    final selectedEvent = _eventById(_eventId);
    final eventYear = selectedEvent == null
        ? null
        : (_yearOf(selectedEvent['year']) ??
              _yearOf(selectedEvent['session_name']));
    final targetYear = eventYear == null ? null : eventYear + 1;
    final nextSessionExists = _targetSessionId != null;
    final className = _selectedClass?['name']?.toString() ?? '';
    final classNumber = RegExp(r'(\d+)').firstMatch(className);
    final destinationName =
        RegExp(r'class\s*10', caseSensitive: false).hasMatch(className)
        ? 'SSC Batch'
        : classNumber == null
        ? 'পরবর্তী শ্রেণি'
        : 'Class ${int.parse(classNumber.group(1)!) + 1}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _picker(
                  'শ্রেণি *',
                  _classId,
                  _classes.map((c) => (c['id'] as num).toInt()).toList(),
                  _classes.map((c) {
                    final g = c['group_name']?.toString() ?? '';
                    final s = c['section']?.toString() ?? '';
                    final extra = g.isNotEmpty ? g : s;
                    return '${c['name']}${extra.isNotEmpty ? ' ($extra)' : ''}';
                  }).toList(),
                  (v) {
                    setState(() {
                      _classId = v;
                      _eventId = null;
                      _targetSessionId = null;
                      _students = [];
                      _history = [];
                      _reviewed = false;
                    });
                    _loadRules();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _picker(
                  'পরীক্ষা Event *',
                  _eventId,
                  events.map((e) => (e['id'] as num).toInt()).toList(),
                  events
                      .map(
                        (e) =>
                            '${e['name'] ?? 'পরীক্ষা'} · ${e['year'] ?? e['session_name'] ?? ''}',
                      )
                      .toList(),
                  (v) {
                    final event = _eventById(v);
                    final nextSessionId = _nextSessionFor(event);
                    setState(() {
                      _eventId = v;
                      _targetSessionId = nextSessionId;
                      _reviewed = false;
                      _students = [];
                      _history = [];
                    });
                    if (nextSessionId != null) {
                      _loadStatus();
                      _loadHistory();
                    }
                  },
                ),
              ),
            ],
          ),
          if (_selectedClass != null) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 2, bottom: 4),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F2FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.trending_up_rounded,
                    color: Color(0xFF4F46E5),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      selectedEvent == null
                          ? '$className → $destinationName  ·  ${targetYear == null ? 'প্রকাশিত ফলাফল বাছুন' : 'শিক্ষাবর্ষ $targetYear'}'
                          : '$className → $destinationName  ·  ${eventYear ?? '—'} → ${nextSessionExists ? targetYear : 'পরের সেশন তৈরি করুন'}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF313B70),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_selectedClass != null &&
              events.isEmpty &&
              _activeExamYearMismatch)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'এই session-এর প্রকাশিত উত্তরণ পরীক্ষার বছর মেলেনি। পরীক্ষা ও ফলাফল-এ event-এর শিক্ষাবর্ষ ঠিক করে আবার চেষ্টা করুন.',
                style: TextStyle(color: Colors.deepOrange, fontSize: 11),
              ),
            ),
          if (_classId != null && _eventId != null && nextSessionExists) ...[
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _calculate,
                icon: const Icon(Icons.calculate),
                label: const Text('যোগ্যতা ক্যালকুলেট করুন'),
              ),
            ),
          ] else if (_classId != null && _eventId != null) ...[
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'আগের শিক্ষাবর্ষের পরের session তৈরি না হওয়া পর্যন্ত promotion হিসাব করা যাবে না। পরীক্ষা ও ফলাফল → নতুন একাডেমিক সেশন থেকে তৈরি করুন।',
                style: TextStyle(color: Colors.deepOrange, fontSize: 11),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------- TAB 1: RULES

  Widget _rulesTab() {
    if (_classId == null) {
      return const Center(
        child: Text(
          'প্রথমে শ্রেণি নির্বাচন করুন',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    final sourceRules = _rules
        .where((r) => r['exam_type']?.toString() == _promotionKind)
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _saveRule(_promotionKind),
              icon: const Icon(Icons.tune_rounded),
              label: Text(
                '${_promotionKind.toUpperCase()} ফলাফলের উত্তরণ নিয়ম',
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _rulesLoading
              ? const Center(child: CircularProgressIndicator())
              : sourceRules.isEmpty
              ? const Center(
                  child: Text(
                    'এই শ্রেণির উত্তরণের নিয়ম এখনো সংরক্ষণ করা হয়নি',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: sourceRules.length,
                  itemBuilder: (_, i) {
                    final r = sourceRules[i];
                    final isSource =
                        r['is_promotion_source'] == true ||
                        r['is_promotion_source'] == 1;
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          isSource ? Icons.star : Icons.star_border,
                          color: isSource ? Colors.amber : Colors.grey,
                        ),
                        title: Text(
                          r['exam_type']?.toString().toUpperCase() ?? '',
                        ),
                        subtitle: Text(
                          'Source: ${isSource ? 'হ্যাঁ' : 'না'} • '
                          'Grace: ${r['grace_failed_subjects'] ?? 0} • '
                          'Min GPA: ${r['min_passing_gpa']}',
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // --------------------------------------------------------- TAB 2: CALCULATE

  Widget _calculateTab() {
    if (_classId == null || _eventId == null) {
      return const Center(
        child: Text(
          'শ্রেণি এবং পরীক্ষা Event নির্বাচন করুন',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }
    if (!_reviewed) {
      return const Center(
        child: Text(
          'যোগ্যতা ক্যালকুলেট করতে উপরের বাটনে চাপ দিন',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Card(
            color: Colors.blue.withValues(alpha: 0.05),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  const Text(
                    'সারসংক্ষেপ',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _summaryChip('মোট', '${_calcSummary['total'] ?? 0}'),
                      _summaryChip(
                        'যোগ্য',
                        '${_calcSummary['eligible'] ?? 0}',
                        Colors.green,
                      ),
                      _summaryChip(
                        'শর্তসাপেক্ষ',
                        '${_calcSummary['conditional'] ?? 0}',
                        Colors.amber,
                      ),
                      _summaryChip(
                        'যোগ্য নয়',
                        '${_calcSummary['not_eligible'] ?? 0}',
                        Colors.red,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: _review.isEmpty
              ? const Center(
                  child: Text(
                    'কোনো ছাত্র পাওয়া যায়নি',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _review.length,
                  itemBuilder: (_, i) => _reviewTile(_review[i]),
                ),
        ),
      ],
    );
  }

  Widget _reviewTile(Map st) {
    final status = st['status']?.toString() ?? 'pending_results';
    final decision = st['decision']?.toString();
    final studentId = (st['student_id'] as num?)?.toInt() ?? 0;
    final color = _statusColor(status);
    final failed = st['failed_subjects'] is List
        ? (st['failed_subjects'] as List)
        : const [];
    final mandatory = st['mandatory_failed'] is List
        ? (st['mandatory_failed'] as List)
        : const [];
    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${st['name']}  •  ${st['from_section'] ?? ''} শাখা • রোল ${st['roll'] ?? '-'}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                _statusChip(status),
                if (decision != null) _decisionChip(decision),
              ],
            ),
            if (st['final_gpa'] != null)
              Text(
                'GPA: ${(st['final_gpa'] as num).toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12),
              ),
            if (failed.isNotEmpty)
              Text(
                'ফেল: ${failed.join(', ')}',
                style: TextStyle(fontSize: 11, color: Colors.red.shade700),
              ),
            if (mandatory.isNotEmpty)
              Text(
                'বাধ্যতামূলক ফেল: ${mandatory.join(', ')}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            Text(
              'কারণ: ${st['reason'] ?? '-'}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            Row(
              children: [
                const Spacer(),
                TextButton.icon(
                  onPressed: studentId == 0 ? null : () => _askDecisionNote(st),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('অনুমোদন'),
                ),
                TextButton.icon(
                  onPressed: studentId == 0
                      ? null
                      : () => _override(
                          studentId,
                          'retained',
                          'retained',
                          'পরবর্তী শ্রেণিতে উন্নীত করা হয়নি',
                        ),
                  icon: const Icon(Icons.block, size: 16),
                  label: const Text('রাখুন'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _askDecisionNote(Map student) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('বিশেষ বিবেচনায় উত্তীর্ণ'),
        content: TextField(
          controller: controller,
          maxLength: 500,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'কারণ / নোট',
            hintText: 'ফল অনুপস্থিত বা অসম্পূর্ণ হলে কারণ লিখুন',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('অনুমোদন'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note == null) return;
    final id = (student['student_id'] as num?)?.toInt() ?? 0;
    if (id == 0) return;
    if (note.isEmpty &&
        (student['status'] == 'pending_results' ||
            student['status'] == 'not_eligible')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('এই শিক্ষার্থীর জন্য কারণ লিখতে হবে।')),
      );
      return;
    }
    await _override(id, 'approved', 'promoted', note);
  }

  // ------------------------------------------------------------- TAB 3: STATUS

  Widget _statusTab() {
    if (_targetSessionId == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'টার্গেট সেশন নির্বাচন করুন',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }
    if (_students.isEmpty && !_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'এই সেশনে কোনো ছাত্র নেই',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }
    final rows = _filteredStudents;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('সব', 'all'),
                _filterChip('যোগ্য', 'eligible'),
                _filterChip('শর্তসাপেক্ষ', 'conditional'),
                _filterChip('অনুমোদিত', 'approved'),
                _filterChip('রক্ষিত', 'retained'),
                _filterChip('প্রমোটেড', 'promoted'),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _selectedIds.isEmpty
                      ? null
                      : () => _bulkAction('approve'),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('বাল্ক অনুমোদন'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _selectedIds.isEmpty
                      ? null
                      : () => _bulkAction('retain'),
                  icon: const Icon(Icons.block_outlined),
                  label: const Text('বাল্ক রক্ষণ'),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed:
                  _students.any(
                    (s) =>
                        s['status'] == 'approved' &&
                        s['decision'] == 'promoted',
                  )
                  ? _executePromotion
                  : null,
              icon: const Icon(Icons.upgrade),
              label: Text(
                'অনুমোদিত শিক্ষার্থীদের পরের শ্রেণিতে পাঠান (${_students.where((s) => s['status'] == 'approved' && s['decision'] == 'promoted').length})',
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: rows.isEmpty
              ? const Center(
                  child: Text(
                    'এই ফিল্টারে কোনো ছাত্র নেই',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: rows.length,
                  itemBuilder: (_, i) => _studentRow(rows[i]),
                ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, String value) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: FilterChip(
      label: Text(label),
      selected: _statusFilter == value,
      onSelected: (selected) =>
          setState(() => _statusFilter = selected ? value : 'all'),
    ),
  );

  Widget _studentRow(Map s) {
    final status = s['status']?.toString() ?? 'pending_results';
    final decision = s['decision']?.toString();
    final fromClass = s['from_class_name'] ?? '';
    final targetClass = s['target_class_name'] ?? '';
    final color = _statusColor(status);
    return Card(
      color: color.withValues(alpha: 0.08),
      child: CheckboxListTile(
        value: s['selected'] == true,
        onChanged: (v) => setState(() => s['selected'] = v),
        title: Text(
          '${s['name']}  •  রোল ${s['roll'] ?? '-'}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              targetClass.isEmpty
                  ? '$fromClass  →  (গন্তব্য শ্রেণি নির্ধারিত হয়নি)'
                  : '$fromClass  →  $targetClass',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (s['final_gpa'] != null)
              Text(
                'GPA: ${(s['final_gpa'] as num).toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 11),
              ),
            Row(
              children: [
                _statusChip(status),
                if (decision != null) _decisionChip(decision),
              ],
            ),
          ],
        ),
        controlAffinity: ListTileControlAffinity.leading,
      ),
    );
  }

  // ------------------------------------------------------------- TAB 4: HISTORY

  Widget _historyTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _targetSessionId == null ? null : _exportReport,
                  icon: const Icon(Icons.download),
                  label: const Text('রিপোর্ট (PDF)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _targetSessionId == null ? null : _loadHistory,
                  icon: const Icon(Icons.history),
                  label: const Text('ইতিহাস লোড'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _history.isEmpty
              ? const Center(
                  child: Text(
                    'ইতিহাস খালি',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _history.length,
                  itemBuilder: (_, i) => _historyTile(_history[i]),
                ),
        ),
      ],
    );
  }

  Widget _groupApprovalTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Waiting for Group Approval',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: _groupLoading ? null : _loadGroupApprovals,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        if (_groupLoading) const LinearProgressIndicator(),
        Expanded(
          child: _groupRows.isEmpty && !_groupLoading
              ? const Center(
                  child: Text(
                    'কোনো student group approval-এর অপেক্ষায় নেই। Admin এবং Class 9-এর class teacher-রা একই ranked list দেখেন।',
                  ),
                )
              : ListView.builder(
                  itemCount: _groupRows.length,
                  itemBuilder: (context, index) {
                    final row = _groupRows[index];
                    return Card(
                      child: ListTile(
                        onTap: () => _approveGroup(row),
                        leading: CircleAvatar(
                          child: Text('${row['combined_rank'] ?? index + 1}'),
                        ),
                        title: Text('${row['name'] ?? ''}'),
                        subtitle: Text(
                          'Roll ${row['roll'] ?? '—'}  ·  Grade ${row['final_grade'] ?? '—'}  ·  GPA ${row['final_gpa'] ?? 0}  ·  মোট নম্বর ${row['total_marks_obtained'] ?? 0}',
                        ),
                        trailing: FilledButton.tonal(
                          onPressed: () => _approveGroup(row),
                          child: const Text('Group দিন'),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _historyTile(Map h) {
    final created = h['created_at']?.toString() ?? '';
    return Card(
      child: ListTile(
        leading: Icon(
          _actionIcon(h['action']),
          color: _actionColor(h['action']),
        ),
        title: Text(
          '${h['student_name'] ?? ''}  •  ${_actionLabel(h['action'])}',
        ),
        subtitle: Text(
          '${h['from_class_name'] ?? ''} → ${h['to_class_name'] ?? ''}'
          '${h['session_name'] == null ? '' : '  •  ${h['session_name']}'}'
          '${h['admin_name'] == null ? '' : '  •  ${h['admin_name']}'}',
        ),
        trailing: Text(
          created.length >= 16 ? created.substring(0, 16) : created,
        ),
      ),
    );
  }

  String _actionLabel(String? action) {
    switch (action) {
      case 'eligible_calculated':
        return 'যোগ্যতা হিসাব';
      case 'reviewed':
        return 'রিভিউ';
      case 'approved':
        return 'অনুমোদিত';
      case 'retained':
        return 'রক্ষিত';
      case 'bulk_approved':
        return 'বাল্ক অনুমোদন';
      case 'bulk_retained':
        return 'বাল্ক রক্ষণ';
      case 'admin_override':
        return 'ওভাররাইড';
      default:
        return action ?? '';
    }
  }

  IconData _actionIcon(String? action) {
    switch (action) {
      case 'eligible_calculated':
        return Icons.calculate;
      case 'reviewed':
        return Icons.rate_review;
      case 'approved':
      case 'bulk_approved':
        return Icons.check_circle;
      case 'retained':
      case 'bulk_retained':
        return Icons.block;
      case 'admin_override':
        return Icons.admin_panel_settings;
      default:
        return Icons.history;
    }
  }

  Color _actionColor(String? action) {
    switch (action) {
      case 'approved':
      case 'bulk_approved':
        return Colors.green;
      case 'retained':
      case 'bulk_retained':
        return Colors.red;
      case 'admin_override':
        return Colors.purple;
      default:
        return Colors.blue;
    }
  }

  // ------------------------------------------------------------- SMALL WIDGETS

  Widget _picker(
    String label,
    int? value,
    List<int> items,
    List<String> labels,
    ValueChanged<int?> onChanged,
  ) {
    final pairs = <int, String>{};
    for (var i = 0; i < items.length; i++) {
      pairs[items[i]] = labels[i];
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<int>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final e in pairs.entries)
            DropdownMenuItem<int>(
              value: e.key,
              child: Text(e.value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _statusChip(String? status) => Chip(
    label: Text(
      _statusLabel(status ?? ''),
      style: const TextStyle(fontSize: 11),
    ),
    backgroundColor: _statusColor(status ?? '').withValues(alpha: 0.15),
    labelStyle: TextStyle(
      color: _statusColor(status ?? ''),
      fontWeight: FontWeight.w600,
    ),
    visualDensity: VisualDensity.compact,
  );

  Widget _decisionChip(String? decision) => Chip(
    label: Text(
      _decisionLabel(decision ?? ''),
      style: const TextStyle(fontSize: 11),
    ),
    backgroundColor: _decisionColor(decision ?? '').withValues(alpha: 0.15),
    labelStyle: TextStyle(
      color: _decisionColor(decision ?? ''),
      fontWeight: FontWeight.w600,
    ),
    visualDensity: VisualDensity.compact,
  );

  Widget _summaryChip(String label, String value, [Color? color]) => Chip(
    label: Text(
      '$label: $value',
      style: TextStyle(fontWeight: FontWeight.bold, color: color),
    ),
    backgroundColor: (color ?? Colors.blue).withValues(alpha: 0.1),
  );
}
