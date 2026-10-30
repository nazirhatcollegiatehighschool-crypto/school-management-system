import 'package:flutter/material.dart';

import '../api.dart';
import 'create_exam_screen.dart';
import 'exam_detail_screen.dart';

/// Teacher's direct marks-entry workspace.
/// The API only returns exams from the teacher's own class or subjects, so the
/// list can safely combine class teachers and subject teachers in one place.
class ExamsScreen extends StatefulWidget {
  final dynamic teacher;
  const ExamsScreen({super.key, required this.teacher});

  @override
  State<ExamsScreen> createState() => ExamsScreenState();
}

class ExamsScreenState extends State<ExamsScreen> {
  List<Map<String, dynamic>> _exams = [];
  Set<int> _classTeacherIds = {};
  int? _selectedClassId;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> reload() => _load();

  bool _flag(dynamic value) => value == true || value == 1 || value == '1';
  int? _asInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value');

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _exams = [];
    });
    try {
      final results = await Future.wait([
        Api.getFresh('/teacher/exams'),
        Api.getFresh('/teacher/profile'),
      ]);
      if (!mounted) return;
      final exams = results[0] is List ? (results[0] as List) : const [];
      final profile = results[1] is Map ? results[1] as Map : const {};
      final teacherClasses = (profile['classes'] as List? ?? const [])
          .whereType<Map>()
          .map((c) => _asInt(c['id']))
          .whereType<int>()
          .toSet();
      final available =
          exams.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).where(
            (e) {
              final published = e['status'] == 'published';
              final openFlag = e['entry_open'];
              final isOpen = openFlag == null
                  ? e['event_id'] == null
                  : _flag(openFlag);
              final classId = _asInt(e['class_id']);
              final isOwnClass =
                  classId != null && teacherClasses.contains(classId);
              final hasSubjectAccess =
                  _flag(e['subject_mine']) || _flag(e['is_mine']);
              final needsReview =
                  isOwnClass &&
                  (e['entry_status'] == 'submitted' ||
                      _flag(e['reentry_pending']));
              return !published &&
                  ((isOpen && (isOwnClass || hasSubjectAccess)) || needsReview);
            },
          ).toList()..sort((a, b) {
            final classCompare = '${a['class_name'] ?? ''}'.compareTo(
              '${b['class_name'] ?? ''}',
            );
            if (classCompare != 0) return classCompare;
            return '${a['subject_name'] ?? ''}'.compareTo(
              '${b['subject_name'] ?? ''}',
            );
          });
      final classIds = available
          .map((e) => _asInt(e['class_id']))
          .whereType<int>()
          .toSet();
      setState(() {
        _exams = available;
        _classTeacherIds = teacherClasses;
        if (_selectedClassId == null || !classIds.contains(_selectedClassId)) {
          _selectedClassId = classIds.length == 1 ? classIds.first : null;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'পরীক্ষা ও class-এর access যাচাই করা যায়নি। Internet সংযোগ পরীক্ষা করে আবার চেষ্টা করুন।';
      });
    }
  }

  List<Map<String, dynamic>> get _classes {
    final byId = <int, Map<String, dynamic>>{};
    for (final e in _exams) {
      final id = _asInt(e['class_id']);
      if (id != null) byId.putIfAbsent(id, () => e);
    }
    final classes = byId.values.toList();
    classes.sort((a, b) {
      final nameCompare = '${a['class_name'] ?? ''}'.compareTo(
        '${b['class_name'] ?? ''}',
      );
      if (nameCompare != 0) return nameCompare;
      return '${a['section'] ?? ''}'.compareTo('${b['section'] ?? ''}');
    });
    return classes;
  }

  List<Map<String, dynamic>> get _visibleExams => _selectedClassId == null
      ? _exams
      : _exams.where((e) => _asInt(e['class_id']) == _selectedClassId).toList();

  /// Groups the visible exams by their session (exam event year), newest /
  /// active session first. Teacher-created tests without an event fall into a
  /// single "সাধারণ পরীক্ষা" bucket at the bottom.
  List<_ExamSessionGroup> get _sessionGroups {
    final byKey = <String, _ExamSessionGroup>{};
    for (final e in _visibleExams) {
      final sid = _asInt(e['session_id']);
      final name = '${e['session_name'] ?? ''}'.trim();
      final year = '${e['event_year'] ?? ''}'.trim();
      final key = sid != null
          ? 'id:$sid'
          : (name.isNotEmpty ? 'name:$name' : 'none');
      final group = byKey.putIfAbsent(
        key,
        () => _ExamSessionGroup(
          name: name,
          year: year,
          isActive: _flag(e['session_active']),
          isNone: sid == null && name.isEmpty && year.isEmpty,
        ),
      );
      group.exams.add(e);
    }
    final groups = byKey.values.toList();
    groups.sort((a, b) {
      if (a.isNone != b.isNone) return a.isNone ? 1 : -1;
      if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
      final ai = int.tryParse(a.name);
      final bi = int.tryParse(b.name);
      if (ai != null && bi != null && ai != bi) return bi.compareTo(ai);
      return b.name.compareTo(a.name);
    });
    for (final group in groups) {
      group.exams.sort((a, b) {
        final classCompare = '${a['class_name'] ?? ''}'.compareTo(
          '${b['class_name'] ?? ''}',
        );
        if (classCompare != 0) return classCompare;
        final sectionCompare = '${a['section'] ?? ''}'.compareTo(
          '${b['section'] ?? ''}',
        );
        if (sectionCompare != 0) return sectionCompare;
        return '${a['subject_name'] ?? ''}'.compareTo(
          '${b['subject_name'] ?? ''}',
        );
      });
    }
    return groups;
  }

  String _classLabel(Map<String, dynamic> e) {
    final className = '${e['class_name'] ?? 'Class'}';
    final section = '${e['section'] ?? ''}'.trim();
    final group = '${e['group_name'] ?? ''}'.trim();
    final parts = <String>[
      if (section.isNotEmpty) section,
      if (group.isNotEmpty && group != section) group,
    ];
    return parts.isEmpty ? className : '$className • ${parts.join(' • ')}';
  }

  bool _canEnter(Map<String, dynamic> e) =>
      (_flag(e['subject_mine']) || _flag(e['is_mine'])) &&
      e['entry_status'] != 'submitted' &&
      e['entry_status'] != 'approved';

  Future<void> _openExam(Map<String, dynamic> exam) async {
    final id = _asInt(exam['id']);
    if (id == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExamDetailScreen(
          examId: id,
          examName: '${exam['name'] ?? exam['subject_name'] ?? 'পরীক্ষা'}',
        ),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _approveSubmitted(Map<String, dynamic> exam) async {
    final id = _asInt(exam['id']);
    if (id == null) return;
    try {
      final isReentry =
          exam['reentry_pending'] == true || exam['reentry_pending'] == 1;
      await Api.post(
        '/teacher/exams/$id/${isReentry ? 'reentry-approve' : 'ct-approve'}',
        {},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.green,
          content: Text('নম্বর অনুমোদন করা হয়েছে।'),
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
    final visible = _visibleExams;
    final classOptions = _classes;
    final groups = _sessionGroups;
    // Old cached payloads (or data before session columns existed) contain no
    // session info at all — keep the flat list instead of one giant "unknown"
    // banner in that case.
    final showSessionBanners =
        groups.isNotEmpty && !(groups.length == 1 && groups.first.isNone);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Marks entry'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'new') {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreateExamScreen(teacher: widget.teacher),
                  ),
                );
                _load();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'new',
                child: Row(
                  children: [
                    Icon(Icons.add_rounded),
                    SizedBox(width: 8),
                    Text('নতুন Test তৈরি'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF3F4FA),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _errorState()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                children: [
                  _premiumHeader(visible.length, sessions: groups.length),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'আপনার খোলা পরীক্ষা',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF202A49),
                          ),
                        ),
                      ),
                      if (visible.isNotEmpty) _countPill(visible.length),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Session অনুযায়ী সাজানো — class বেছে নিন, তারপর subject খুলে নম্বর দিন।',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.blueGrey.shade600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (classOptions.length > 1) _classPicker(classOptions),
                  if (classOptions.length == 1)
                    _singleClassChip(classOptions.first),
                  if (classOptions.isNotEmpty) const SizedBox(height: 10),
                  if (visible.isEmpty)
                    _emptyState()
                  else if (!showSessionBanners)
                    ...visible.map(_examTile)
                  else
                    for (var i = 0; i < groups.length; i++) ...[
                      _sessionBanner(groups[i], _paletteFor(i)),
                      ..._groupTiles(groups[i], _paletteFor(i)),
                      if (i != groups.length - 1) const SizedBox(height: 8),
                    ],
                ],
              ),
            ),
    );
  }

  Widget _premiumHeader(int count, {int sessions = 0}) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF202A49), Color(0xFF453BB8), Color(0xFF7266E8)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(25),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF574CE8).withValues(alpha: .25),
          blurRadius: 22,
          offset: const Offset(0, 9),
        ),
      ],
    ),
    child: Stack(
      children: [
        Positioned(
          right: -28,
          top: -48,
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: .07),
            ),
          ),
        ),
        Positioned(
          right: 68,
          bottom: -54,
          child: Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: .06),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 18, 19),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .18),
                  ),
                ),
                child: const Icon(
                  Icons.edit_note_rounded,
                  color: Colors.white,
                  size: 31,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'নম্বর এন্ট্রি',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 19,
                        letterSpacing: -.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      count == 0
                          ? 'এখন কোনো খোলা পরীক্ষা নেই'
                          : '$count টি খোলা exam'
                                '${sessions > 1 ? ' • $sessions টি session' : ''}'
                                ' • আপনার অনুমোদিত class ও subject',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .78),
                        fontSize: 12,
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.white.withValues(alpha: .2)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      'OPEN',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .78),
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  static const List<List<Color>> _sessionPalettes = [
    [Color(0xFF0B6B4F), Color(0xFF14A97A)],
    [Color(0xFF5B2A86), Color(0xFF8B5CF6)],
    [Color(0xFF9A4A08), Color(0xFFE09A2D)],
    [Color(0xFF8A1C4A), Color(0xFFD45C8A)],
    [Color(0xFF1D4ED8), Color(0xFF60A5FA)],
    [Color(0xFF334155), Color(0xFF64748B)],
  ];

  List<Color> _paletteFor(int index) =>
      _sessionPalettes[index % _sessionPalettes.length];

  Widget _bubble(double size, double opacity) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: opacity),
    ),
  );

  Widget _sessionBanner(_ExamSessionGroup group, List<Color> palette) {
    final classCount = group.exams
        .map((e) => _asInt(e['class_id']))
        .whereType<int>()
        .toSet()
        .length;
    final openCount = group.exams.where(_canEnter).length;
    final yearNote =
        group.year.isNotEmpty &&
            group.name.isNotEmpty &&
            group.year != group.name
        ? ' • বছর ${group.year}'
        : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: palette,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: palette.last.withValues(alpha: .24),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(right: -28, top: -38, child: _bubble(126, .09)),
          Positioned(left: -22, bottom: -52, child: _bubble(112, .07)),
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 14, 14, 14),
            child: Row(
              children: [
                Container(
                  width: 45,
                  height: 45,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .22),
                    ),
                  ),
                  child: const Icon(
                    Icons.calendar_month_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              group.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.2,
                              ),
                            ),
                          ),
                          if (group.isActive) ...[
                            const SizedBox(width: 7),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .2),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: const Text(
                                'ACTIVE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: .7,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${group.exams.length} টি পরীক্ষা • $classCount টি ক্লাস'
                        '${openCount > 0 ? ' • $openCount টি খোলা' : ''}$yearNote',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .8),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .2),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${group.exams.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'EXAM',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .75),
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Within each session banner, split exams into compact class blocks so a
  /// long "all classes" list never reads as one messy wall of cards.
  List<Widget> _groupTiles(_ExamSessionGroup group, List<Color> palette) {
    final perClass = <String, int>{};
    for (final e in group.exams) {
      final label = _classLabel(e);
      perClass[label] = (perClass[label] ?? 0) + 1;
    }
    final widgets = <Widget>[];
    String? currentClass;
    for (final e in group.exams) {
      final label = _classLabel(e);
      if (label != currentClass) {
        currentClass = label;
        widgets.add(
          _classSectionHeader(label, perClass[label] ?? 0, palette.first),
        );
      }
      widgets.add(_examTile(e));
    }
    return widgets;
  }

  Widget _classSectionHeader(String label, int count, Color accent) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(9),
          ),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.school_rounded, size: 15, color: Color(0xFF59627D)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF3B4564),
            ),
          ),
        ),
        Text(
          '$count টি',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: accent,
          ),
        ),
      ],
    ),
  );

  Widget _countPill(int count) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFE7E5FF),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      '$count টি',
      style: const TextStyle(
        color: Color(0xFF5148C8),
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
    ),
  );

  Widget _classPicker(List<Map<String, dynamic>> classes) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE5E7F0)),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF202A49).withValues(alpha: .04),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<int?>(
        value: _selectedClassId,
        isExpanded: true,
        icon: const Icon(
          Icons.keyboard_arrow_down_rounded,
          color: Color(0xFF5B50D6),
        ),
        hint: const Text('সব অনুমোদিত Class'),
        items: [
          const DropdownMenuItem<int?>(
            value: null,
            child: Text('সব অনুমোদিত Class'),
          ),
          ...classes.map(
            (e) => DropdownMenuItem<int?>(
              value: _asInt(e['class_id']),
              child: Text(_classLabel(e), overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: (v) => setState(() => _selectedClassId = v),
      ),
    ),
  );

  Widget _singleClassChip(Map<String, dynamic> e) {
    final id = _asInt(e['class_id']);
    final own = id != null && _classTeacherIds.contains(id);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFE9E7FF),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              own ? Icons.workspace_premium_rounded : Icons.menu_book_rounded,
              size: 16,
              color: const Color(0xFF5148C8),
            ),
            const SizedBox(width: 7),
            Text(
              '${_classLabel(e)}${own ? ' • Class Teacher' : ' • Subject Teacher'}',
              style: const TextStyle(
                color: Color(0xFF4139A7),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _examTile(Map<String, dynamic> e) {
    final canEnter = _canEnter(e);
    final classId = _asInt(e['class_id']);
    final isOwnClass = classId != null && _classTeacherIds.contains(classId);
    final subtitle = [
      if (e['subject_name'] != null) '${e['subject_name']}',
      if (e['class_name'] != null) _classLabel(e),
    ].join('  •  ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: const Color(0xFFE8EAF3)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF202A49).withValues(alpha: .045),
            blurRadius: 13,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(19),
        child: InkWell(
          borderRadius: BorderRadius.circular(19),
          onTap: () => _openExam(e),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: canEnter
                          ? const [Color(0xFF5C50E8), Color(0xFF8276F2)]
                          : const [Color(0xFF65708C), Color(0xFF8992A8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    canEnter ? Icons.edit_rounded : Icons.visibility_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${e['name'] ?? e['subject_name'] ?? 'পরীক্ষা'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF202A49),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.blueGrey.shade600,
                        ),
                      ),
                      if (!canEnter && isOwnClass) ...[
                        const SizedBox(height: 5),
                        const Text(
                          'Class Teacher • পর্যবেক্ষণ',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Color(0xFF59627D),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 7),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (isOwnClass &&
                        (e['entry_status'] == 'submitted' ||
                            e['reentry_pending'] == true ||
                            e['reentry_pending'] == 1))
                      IconButton(
                        tooltip:
                            (e['reentry_pending'] == true ||
                                e['reentry_pending'] == 1)
                            ? 'Re-entry অনুমোদন'
                            : 'এক ট্যাপে নম্বর অনুমোদন',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _approveSubmitted(e),
                        icon: Icon(
                          (e['reentry_pending'] == true ||
                                  e['reentry_pending'] == 1)
                              ? Icons.lock_open_rounded
                              : Icons.check_circle_rounded,
                          color: Colors.green,
                        ),
                      ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: canEnter
                          ? const Color(0xFF5C50E8)
                          : const Color(0xFF8790A6),
                      size: 21,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      canEnter ? 'নম্বর দিন' : 'দেখুন',
                      style: TextStyle(
                        color: canEnter
                            ? const Color(0xFF5148C8)
                            : const Color(0xFF68728C),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState() => Container(
    margin: const EdgeInsets.only(top: 6),
    padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFE8EAF3)),
    ),
    child: Column(
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: const BoxDecoration(
            color: Color(0xFFF0EEFF),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.lock_clock_rounded,
            color: Color(0xFF655AE2),
            size: 29,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'এখন কোনো খোলা নম্বর এন্ট্রি নেই',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Color(0xFF202A49),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Admin আপনার subject-এর exam unlock করলে এখানে সরাসরি দেখা যাবে।',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            height: 1.45,
            color: Colors.blueGrey.shade600,
          ),
        ),
      ],
    ),
  );

  Widget _errorState() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const SizedBox(height: 70),
      const Icon(Icons.cloud_off_rounded, size: 42, color: Color(0xFF8A91A5)),
      const SizedBox(height: 12),
      Text(
        _error!,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFF59627D)),
      ),
      const SizedBox(height: 12),
      Center(
        child: FilledButton.tonalIcon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('আবার চেষ্টা করুন'),
        ),
      ),
    ],
  );
}

/// One session bucket on the "নম্বর দিন" screen. `isNone` groups exams that
/// have no exam-event (teacher-created tests) so they stay visually separate
/// from official session exams.
class _ExamSessionGroup {
  _ExamSessionGroup({
    required this.name,
    required this.year,
    required this.isActive,
    required this.isNone,
  });

  final String name;
  final String year;
  final bool isActive;
  final bool isNone;
  final List<Map<String, dynamic>> exams = [];

  String get title {
    if (isNone) return 'সাধারণ পরীক্ষা';
    if (name.isNotEmpty) return '$name সেশন';
    if (year.isNotEmpty) return '$year সেশন';
    return 'সেশন';
  }
}
