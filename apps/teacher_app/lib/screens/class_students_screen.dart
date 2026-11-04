import 'package:flutter/material.dart';

import '../api.dart';
import 'student_registration_screen.dart';
import 'student_profile_screen.dart';

class ClassStudentsScreen extends StatefulWidget {
  final dynamic teacher;
  const ClassStudentsScreen({super.key, required this.teacher});
  @override
  State<ClassStudentsScreen> createState() => _ClassStudentsScreenState();
}

class _ClassStudentsScreenState extends State<ClassStudentsScreen> {
  List _classes = [];
  int? _selectedClass;
  List _students = [];
  Map? _summary;
  bool _loading = true;
  String? _error;
  String _query = '';
  String? _summaryFilter;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Api.get('/teacher/profile');
      final classes = (r['classes'] as List? ?? []);
      setState(() {
        _classes = classes;
        if (_selectedClass == null && classes.isNotEmpty) {
          _selectedClass = classes.first['id'];
        }
        _loading = false;
      });
      if (_selectedClass != null) _loadStudents();
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _loadStudents() async {
    if (_students.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      await Api.loadCachedFirst('/teacher/classes/$_selectedClass/guardians', (
        r,
      ) {
        if (!mounted) return;
        setState(() {
          _students = r is List ? r : [];
          _loading = false;
        });
      });
      final summary = await Api.get('/teacher/classes/$_selectedClass/summary');
      if (mounted && summary is Map) setState(() => _summary = summary);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  int? _openingStudentId;

  Future<void> _setStudentActive(Map student, bool active) async {
    final id = student['student_id'];
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Api.put('/teacher/classes/$_selectedClass/students/$id/active', {'active': active});
      if (!mounted) return;
      await _loadStudents();
      messenger.showSnackBar(SnackBar(
        content: Text(active ? 'শিক্ষার্থী আবার সক্রিয় হয়েছে' : 'শিক্ষার্থী নিষ্ক্রিয় হয়েছে'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text(e.toString().replaceFirst('Exception: ', '')),
      ));
    }
  }

  Future<void> _openStudentProfile(Map student) async {
    final studentId = int.tryParse('${student['student_id']}');
    if (studentId == null || _openingStudentId != null) return;
    setState(() => _openingStudentId = studentId);
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => StudentProfileScreen(
            key: ValueKey<int>(studentId),
            studentId: studentId,
            studentName: '${student['student_name'] ?? ''}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _openingStudentId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredStudents = _students.where((item) {
      final s = item as Map;
      final q = _query.trim().toLowerCase();
      final matchesQuery = q.isEmpty ||
          ['student_name', 'roll', 'guardian_name', 'guardian_phone']
              .any((key) => '${s[key] ?? ''}'.toLowerCase().contains(q));
      final matchesFilter = switch (_summaryFilter) {
        'male' => '${s['gender'] ?? ''}'.toLowerCase() == 'male',
        'female' => '${s['gender'] ?? ''}'.toLowerCase() == 'female',
        'scholarship' => s['receives_scholarship'] == true || s['receives_scholarship'] == 1,
        'religion_missing' => '${s['religion'] ?? ''}'.trim().isEmpty || '${s['religion']}'.trim() == 'উল্লেখ নেই',
        'profile_incomplete' => !_profileComplete(s),
        _ => true,
      };
      return matchesQuery && matchesFilter;
    }).toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FC),
      appBar: AppBar(
        title: const Text('শিক্ষার্থী তালিকা', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: const Color(0xFFF5F7FC),
        actions: [
          IconButton(tooltip: 'তালিকা আপডেট', icon: const Icon(Icons.refresh_rounded), onPressed: _loadClasses),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: _selectedClass != null
          ? FloatingActionButton.extended(
              onPressed: () async {
                final cls = _classes.firstWhere(
                  (c) => c['id'] == _selectedClass,
                  orElse: () => null,
                );
                if (cls == null) return;
                final ok = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StudentRegistrationScreen(
                      teacher: widget.teacher,
                      classId: _selectedClass!,
                      classLabel: '${cls['name']} (${cls['section']})',
                    ),
                  ),
                );
                if (ok == true) _loadStudents();
              },
              icon: const Icon(Icons.person_add),
              label: const Text('নতুন ভর্তি'),
            )
          : null,
      body: _loading && _classes.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _classes.isEmpty
          ? Center(child: Text(_error!))
          : _classes.isEmpty
          ? const Center(
              child: Text(
                'আপনি কোনো class-এর class teacher নন।\nAdmin panel-এ class teacher assign করুন।',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 15),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('আপনার ক্লাসের শিক্ষার্থীরা', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF202A49))),
                    const SizedBox(height: 4),
                    Text('শিক্ষার্থীর তথ্য ও অভিভাবকের যোগাযোগ দেখুন', style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade600)),
                    const SizedBox(height: 14),
                    if (_selectedClass != null)
                      Builder(builder: (_) {
                        final cls = _classes.firstWhere(
                          (c) => c['id'] == _selectedClass,
                          orElse: () => null,
                        );
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE6EAF2)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.class_rounded, color: Color(0xFF3F51B5)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  cls == null
                                      ? ''
                                      : '${cls['name']} (${cls['section'] ?? ''}) — ${cls['student_count']} students',
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ]),
                ),
                if (_summary != null) _classSummaryCard(),
                if (!_loading && _error == null && _students.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                    child: TextField(
                      onChanged: (value) => setState(() => _query = value),
                      decoration: InputDecoration(
                        hintText: 'নাম, রোল বা অভিভাবক খুঁজুন',
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true, fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: const Color(0xFFE6EAF2))),
                      ),
                    ),
                  ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                      ? Center(child: Text(_error!))
                      : _students.isEmpty
                      ? const Center(
                          child: _EmptyStudents(),
                        )
                  : filteredStudents.isEmpty
                      ? Center(child: Text(_summaryFilter == null ? 'এই নামে কোনো শিক্ষার্থী পাওয়া যায়নি' : 'এই বিভাগে কোনো শিক্ষার্থী নেই', style: const TextStyle(color: Colors.blueGrey)))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 2, 16, 100),
                          itemCount: filteredStudents.length,
                          itemBuilder: (_, i) {
                            final s = filteredStudents[i];
                            return _StudentCard(
                              student: s,
                              onTap: () => _openStudentProfile(s as Map),
                              onActiveChanged: (active) => _setStudentActive(s as Map, active),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _classSummaryCard() {
    final genders = (_summary?['gender'] as List? ?? []).cast<Map>();
    final religions = (_summary?['religion'] as List? ?? []).cast<Map>();
    int count(String name) => genders
        .where((r) => '${r['label']}'.toLowerCase() == name)
        .fold<int>(0, (s, r) => s + ((r['count'] as num?)?.toInt() ?? 0));
    final total = genders.fold<int>(
      0,
      (s, r) => s + ((r['count'] as num?)?.toInt() ?? 0),
    );
    final incompleteCount = _students.where((s) => !_profileComplete(s as Map)).length;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE9EDF5))),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.insights_rounded, size: 19, color: Color(0xFF5C50E8)),
              const SizedBox(width: 7),
              const Text(
              'ক্লাসের সারাংশ',
              style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF202A49)),
            ),
            ]),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _summaryPill('মোট $total জন', null, onTap: () => setState(() => _summaryFilter = null)),
                _summaryPill('ছেলে ${count('male')}', 'male', onTap: () => setState(() => _summaryFilter = 'male')),
                _summaryPill('মেয়ে ${count('female')}', 'female', onTap: () => setState(() => _summaryFilter = 'female')),
                _summaryPill('উপবৃত্তি ${_summary?['scholarship_count'] ?? 0} জন', 'scholarship', onTap: () => setState(() => _summaryFilter = 'scholarship')),
                for (final r in religions)
                  _summaryPill(
                    '${r['label']}' == 'উল্লেখ নেই'
                        ? 'উল্লেখ নেই · অসম্পূর্ণ প্রোফাইল $incompleteCount জন'
                        : '${r['label']} ${r['count']}',
                    '${r['label']}' == 'উল্লেখ নেই' ? 'profile_incomplete' : null,
                    onTap: '${r['label']}' == 'উল্লেখ নেই'
                        ? () => setState(() => _summaryFilter = 'profile_incomplete')
                        : null,
                  ),
                _summaryPill('অসম্পূর্ণ প্রোফাইল $incompleteCount জন', 'profile_incomplete', onTap: () => setState(() => _summaryFilter = 'profile_incomplete')),
              ],
            ),
          ],
      ),
    );
  }

  bool _profileComplete(Map s) {
    bool has(String key) {
      final value = '${s[key] ?? ''}'.trim();
      return value.isNotEmpty && value != 'উল্লেখ নেই' && value.toLowerCase() != 'unknown';
    }
    final placeholderBirthCertificate = s['birth_cert_placeholder'] == true || s['birth_cert_placeholder'] == 1;
    return has('student_name') && has('dob') && has('gender') && has('religion') &&
        has('father_name') && has('mother_name') && has('guardian_name') &&
        has('guardian_phone') && has('birth_cert_no') && !placeholderBirthCertificate && has('address');
  }

  Widget _summaryPill(String text, String? filter, {VoidCallback? onTap}) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(99),
    child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: _summaryFilter == filter && filter != null ? const Color(0xFFDCD9FF) : const Color(0xFFF1F3FF),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: _summaryFilter == filter && filter != null ? const Color(0xFF8177EB) : Colors.transparent),
    ),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
  ));
}

class _StudentCard extends StatelessWidget {
  final Map student;
  final VoidCallback onTap;
  final ValueChanged<bool> onActiveChanged;
  const _StudentCard({required this.student, required this.onTap, required this.onActiveChanged});

  @override
  Widget build(BuildContext context) {
    final name = '${student['student_name'] ?? 'নাম নেই'}';
    final guardian = '${student['guardian_name'] ?? '-'}';
    final phone = '${student['guardian_phone'] ?? ''}'.trim();
    final login = '${student['guardian_login'] ?? ''}'.trim();
    final active = student['status'] == null || student['status'] == 'active';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE9EDF5)),
        boxShadow: [BoxShadow(color: const Color(0xFF1E2A4A).withValues(alpha: .035), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: active ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 48, height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0xFFE9E7FF), borderRadius: BorderRadius.circular(15)),
                child: Text('${student['roll'] ?? '—'}', style: const TextStyle(color: Color(0xFF5146D8), fontSize: 15, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: active ? const Color(0xFF202A49) : Colors.blueGrey)),
                if (!active && '${student['deactivated_session_name'] ?? ''}'.isNotEmpty)
                  Text('নিষ্ক্রিয় · ${student['deactivated_session_name']}', style: const TextStyle(fontSize: 11, color: Colors.deepOrange)),
                const SizedBox(height: 7),
                _detail(Icons.family_restroom_rounded, 'অভিভাবক: $guardian'),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _detail(Icons.call_outlined, phone),
                ],
                if (login.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _detail(Icons.login_rounded, 'Login: $login'),
                ],
              ])),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Switch.adaptive(value: active, onChanged: onActiveChanged),
                Text(active ? 'সক্রিয়' : 'নিষ্ক্রিয়', style: TextStyle(fontSize: 10, color: active ? Colors.green : Colors.deepOrange)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _detail(IconData icon, String label) => Row(children: [
    Icon(icon, size: 14, color: const Color(0xFF818BA0)),
    const SizedBox(width: 5),
    Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF68748A)))),
  ]);
}

class _EmptyStudents extends StatelessWidget {
  const _EmptyStudents();

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 72, height: 72, decoration: BoxDecoration(color: const Color(0xFFE9E7FF), borderRadius: BorderRadius.circular(24)), child: const Icon(Icons.groups_2_rounded, size: 36, color: Color(0xFF5C50E8))),
    const SizedBox(height: 14),
    const Text('এখনো কোনো শিক্ষার্থী নেই', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF202A49))),
    const SizedBox(height: 5),
    const Text('নতুন ভর্তি বাটনে শিক্ষার্থী যোগ করতে পারেন', style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
  ]);
}
