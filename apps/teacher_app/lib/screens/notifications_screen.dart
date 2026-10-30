import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import 'attendance_access_screen.dart';

class TeacherNotificationsScreen extends StatefulWidget {
  final Future<void> Function(Map<String, dynamic>) onOpen;
  const TeacherNotificationsScreen({super.key, required this.onOpen});

  @override
  State<TeacherNotificationsScreen> createState() =>
      _TeacherNotificationsScreenState();
}

class _TeacherNotificationsScreenState
    extends State<TeacherNotificationsScreen> {
  List _rows = [];
  List _profileRequests = [];
  int _unread = 0;
  bool _loading = true;
  String? _error;
  final Set<int> _acting = {};
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  bool _expired(Map row) {
    final status = '${row['attendance_request_status'] ?? ''}';
    if (status == 'expired') return true;
    if (status != 'pending') return false;
    final at = int.tryParse('${row['attendance_request_expires_at'] ?? ''}');
    return at != null && at <= DateTime.now().millisecondsSinceEpoch;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await Future.wait([
        Api.get('/teacher/notifications'),
        Api.get('/teacher/student-profile-edit-requests'),
      ]);
      final result = data[0];
      if (!mounted) return;
      setState(() {
        _rows = result['notifications'] as List? ?? [];
        _profileRequests = data[1] as List? ?? [];
        _unread = int.tryParse('${result['unread'] ?? 0}') ?? 0;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _open(Map row) async {
    final id = int.tryParse('${row['id']}');
    if (id != null) {
      try {
        await Api.post('/teacher/notifications/$id/read', {});
      } catch (_) {}
    }
    if (!mounted) return;
    // Attendance access requests belong to the dedicated approve/reject screen
    // so the class teacher sees the expiry state and the full request context.
    if (row['attendance_request_status'] != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AttendanceAccessScreen()),
      );
      if (mounted) await _load();
      return;
    }
    Navigator.pop(context);
    final data = Map<String, dynamic>.from(row);
    if ('${row['title']}' == 'শিক্ষার্থী প্রোফাইল সংশোধন অনুরোধ') {
      data['kind'] = 'student_profile_edit_request';
    }
    await widget.onOpen(data);
  }

  Future<void> _decide(Map row, bool accept) async {
    final id = int.tryParse('${row['related_id']}');
    if (id == null || !_acting.add(id)) return;
    setState(() {});
    try {
      await Api.post('/attendance/access-requests/$id/decision', {
        'decision': accept ? 'accept' : 'reject',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept ? 'হাজিরার অনুরোধ অনুমোদিত' : 'হাজিরার অনুরোধ প্রত্যাখ্যাত',
          ),
        ),
      );
      await _load();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      await _load();
    } finally {
      _acting.remove(id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _reviewProfile(Map row, String status) async {
    final id = int.tryParse('${row['id']}');
    if (id == null) return;
    try {
      await Api.post('/teacher/student-profile-edit-requests/$id/review', {
        'status': status,
      });
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_unread > 0 ? 'নোটিফিকেশন ($_unread)' : 'নোটিফিকেশন'),
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(child: Text(_error!))
        : _rows.isEmpty && _profileRequests.isEmpty
        ? const Center(child: Text('নতুন কোনো নোটিফিকেশন নেই।'))
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _rows.length + _profileRequests.length,
              itemBuilder: (_, index) {
                if (index >= _rows.length) {
                  final r = _profileRequests[index - _rows.length];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${r['student_name']} · Roll ${r['roll']} · ${r['class_name']} ${r['section'] ?? ''}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'অভিভাবক প্রোফাইল সংশোধন চেয়েছেন: ${r['reason']}',
                          ),
                          Text(
                            'প্রস্তাবিত তথ্য: ${r['proposed_changes'] ?? '—'}',
                          ),
                          if ('${r['status']}' == 'pending')
                            Row(
                              children: [
                                TextButton(
                                  onPressed: () =>
                                      _reviewProfile(r, 'rejected'),
                                  child: const Text('Reject'),
                                ),
                                const Spacer(),
                                FilledButton(
                                  onPressed: () =>
                                      _reviewProfile(r, 'resolved'),
                                  child: const Text('সংশোধন শেষে Resolved'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  );
                }
                final row = _rows[index];
                final read = row['read_at'] != null;
                final attendanceRequest =
                    '${row['attendance_request_status'] ?? ''}';
                final expired = _expired(row);
                final effectiveRequest =
                    expired && attendanceRequest == 'pending'
                    ? 'expired'
                    : attendanceRequest;
                final requestId = int.tryParse('${row['related_id']}');
                return Card(
                  color: read ? Colors.white : const Color(0xFFEFF3FF),
                  child: Column(
                    children: [
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: read
                              ? Colors.blueGrey.shade50
                              : Colors.indigo.shade50,
                          child: Icon(
                            _icon('${row['type'] ?? ''}'),
                            color: Colors.indigo,
                          ),
                        ),
                        title: Text(
                          '${row['title'] ?? 'নোটিফিকেশন'}',
                          style: TextStyle(
                            fontWeight: read
                                ? FontWeight.w500
                                : FontWeight.w800,
                          ),
                        ),
                        subtitle: Text(
                          '${row['body'] ?? ''}\n${row['class_name'] ?? row['student_name'] ?? ''}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _open(row),
                      ),
                      if (attendanceRequest.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: effectiveRequest == 'pending'
                              ? Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed:
                                            requestId == null ||
                                                _acting.contains(requestId)
                                            ? null
                                            : () => _decide(row, false),
                                        icon: const Icon(Icons.close),
                                        label: const Text('Reject'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed:
                                            requestId == null ||
                                                _acting.contains(requestId)
                                            ? null
                                            : () => _decide(row, true),
                                        icon: const Icon(Icons.check),
                                        label: const Text('Accept'),
                                      ),
                                    ),
                                  ],
                                )
                              : Align(
                                  alignment: Alignment.centerRight,
                                  child: Chip(
                                    label: Text(
                                      effectiveRequest == 'expired'
                                          ? 'মেয়াদ শেষ — অনুমোদন বন্ধ'
                                          : effectiveRequest,
                                    ),
                                    avatar: Icon(
                                      effectiveRequest == 'expired'
                                          ? Icons.timer_off_outlined
                                          : Icons.done_all,
                                      size: 16,
                                    ),
                                  ),
                                ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
  );

  IconData _icon(String type) => switch (type) {
    'attendance' => Icons.fact_check_outlined,
    'homework' => Icons.menu_book_outlined,
    'complaint' => Icons.description_outlined,
    'promotion' => Icons.school_outlined,
    'result' || 'class_test_result' => Icons.assessment_outlined,
    _ => Icons.notifications_outlined,
  };
}
