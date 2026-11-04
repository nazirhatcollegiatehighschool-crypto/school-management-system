import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';

class RegisteredGuardiansScreen extends StatefulWidget {
  const RegisteredGuardiansScreen({super.key});

  @override
  State<RegisteredGuardiansScreen> createState() =>
      _RegisteredGuardiansScreenState();
}

class _RegisteredGuardiansScreenState extends State<RegisteredGuardiansScreen> {
  List sections = [];
  bool loading = true;
  String? error;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => load(silent: true),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final data = await Api.get('/admin/registered-guardians/sections');
      if (mounted) {
        setState(() {
          sections = data is List ? data : [];
          loading = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFEEF0F8),
    appBar: AppBar(title: const Text('Registered Guardians')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(error!),
                TextButton(
                  onPressed: load,
                  child: const Text('আবার চেষ্টা করুন'),
                ),
              ],
            ),
          )
        : RefreshIndicator(
            onRefresh: load,
            child: sections.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 180),
                      Center(
                        child: Text('এখনও কোনো guardian app account নেই।'),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: sections.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final section = sections[index] as Map;
                      final count = section['student_count'] ?? 0;
                      return Card(
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 8,
                          ),
                          leading: const CircleAvatar(
                            child: Icon(Icons.groups_rounded),
                          ),
                          title: Text(
                            '${section['class_name'] ?? 'শ্রেণি'} • ${section['section'] ?? 'সেকশন নেই'}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '$count জন শিক্ষার্থীর guardian account',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  _GuardianStudentsScreen(section: section),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
  );
}

class _GuardianStudentsScreen extends StatefulWidget {
  final Map section;
  const _GuardianStudentsScreen({required this.section});
  @override
  State<_GuardianStudentsScreen> createState() =>
      _GuardianStudentsScreenState();
}

class _GuardianStudentsScreenState extends State<_GuardianStudentsScreen> {
  List students = [];
  bool loading = true;
  String? error;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => load(silent: true),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final data = await Api.get(
        '/admin/registered-guardians/sections/${widget.section['class_id']}',
        queryParams: widget.section['section'] == null
            ? null
            : {'section': widget.section['section'].toString()},
      );
      if (mounted) {
        setState(() {
          students = data is List ? data : [];
          loading = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFEEF0F8),
    appBar: AppBar(
      title: Text(
        '${widget.section['class_name']} • ${widget.section['section'] ?? ''}',
      ),
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? Center(child: Text(error!))
        : RefreshIndicator(
            onRefresh: load,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: students.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final student = students[index] as Map;
                final active = student['is_active'] == true;
                return Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: active
                          ? const Color(0xFFE3F8EC)
                          : const Color(0xFFF1F2F6),
                      child: Icon(
                        Icons.person_rounded,
                        color: active ? Colors.green.shade700 : Colors.grey,
                      ),
                    ),
                    title: Text(
                      '${student['student_name'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text('রোল: ${student['roll'] ?? '—'}'),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFFE3F8EC)
                            : const Color(0xFFF1F2F6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        active ? 'Active' : 'Inactive',
                        style: TextStyle(
                          color: active
                              ? Colors.green.shade800
                              : Colors.grey.shade700,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    onTap: () => _showActivity(context, student),
                  ),
                );
              },
            ),
          ),
  );

  void _showActivity(BuildContext context, Map student) {
    final guardians = (student['guardians'] as List? ?? []).cast<Map>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${student['student_name'] ?? 'শিক্ষার্থী'}',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              for (final guardian in guardians) ...[
                Text(
                  guardian['name']?.toString().isNotEmpty == true
                      ? guardian['name']
                      : 'অভিভাবক',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                _activityLine('সর্বশেষ লগইন', guardian['last_login_at']),
                _activityLine(
                  'সর্বশেষ online দেখা গেছে',
                  guardian['last_seen_at'],
                ),
                if (guardian['last_inactive_at'] != null)
                  _activityLine(
                    'সর্বশেষ inactive সময়',
                    guardian['last_inactive_at'],
                  )
                else if (guardian['is_active'] != true)
                  _activityLine('সর্বশেষ Active ছিল', guardian['last_seen_at']),
                const Divider(height: 22),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _activityLine(String label, dynamic value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(
          width: 150,
          child: Text(label, style: TextStyle(color: Colors.grey.shade700)),
        ),
        Expanded(
          child: Text(
            _formatTime(value),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

String _formatTime(dynamic value) {
  if (value == null || '$value'.isEmpty) return 'তথ্য নেই';
  final date = DateTime.tryParse('$value')?.toLocal();
  if (date == null) return '$value';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
}
