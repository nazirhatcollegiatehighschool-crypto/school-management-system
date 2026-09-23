import 'package:flutter/material.dart';
import '../fcm_service.dart';
import '../api.dart';
import '../update_check.dart';
import 'login_screen.dart';
import 'splash_screen.dart';

class ProfileScreen extends StatefulWidget {
  final dynamic teacher;
  const ProfileScreen({super.key, required this.teacher});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map? _profile;
  final bool _saving = false;
  List _ctr = [];
  List _subjects = [];

  @override
  void initState() { super.initState(); _load(); }

  String _teacherId() {
    final uid = widget.teacher['id'];
    final numeric = int.tryParse('$uid');
    if (numeric != null) return numeric.toString().padLeft(6, '0');
    final username = '${widget.teacher['username'] ?? ''}';
    final hash = username.hashCode.abs();
    return (hash % 900000 + 100000).toString();
  }

  Future<void> _load() async {
    try {
      final r = await Api.get('/teacher/profile');
      final [reqs, subs] = await Future.wait([
        Api.get('/teacher/class-teacher-requests').catchError((_) => <dynamic>[]),
        Api.get('/teacher/subjects').catchError((_) => <dynamic>[]),
      ]);
      setState(() {
        _profile = r;
        _ctr = reqs is List ? reqs : [];
        _subjects = subs is List ? subs : [];
      });
    } catch (_) {}
  }

  Future<void> _requestDialog() async {
    final classes = _profile?['classes'] as List? ?? [];
    final ctIds = classes.map((c) => c['id']).toSet();
    // classes the teacher teaches but is not CT of yet
    final teachClassIds = <int>{};
    final teachMap = <int, List<String>>{};
    for (final s in _subjects) {
      final cid = s['class_id'] as int?;
      if (cid == null) continue;
      teachClassIds.add(cid);
      teachMap.putIfAbsent(cid, () => []).add('${s['name']} (${s['class_name']} ${s['section']})');
    }
    final requestable = teachClassIds
        .where((cid) => !ctIds.contains(cid))
        .toList()
      ..sort();
    final pendingIds = _ctr.where((r) => r['status'] == 'pending').map((r) => r['class_id']).toSet();
    if (requestable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.orange.shade700,
          content: const Text('আপনি এমন কোনো class-এ subject পড়ান না যেখানে আপনি এখনো class teacher নন।\nনতুন class teacher অনুরোধ admin panel থেকে সরাসরি assign করা যায়।')));
      return;
    }
    int? selectedId = requestable.first;
    final noteCtl = TextEditingController();
    final cnameMap = <int, String>{};
    for (final k in teachMap.keys) {
      final first = teachMap[k]!.first;
      final open = first.lastIndexOf('(');
      final close = first.lastIndexOf(')');
      final inner = (open != -1 && close > open)
          ? first.substring(open + 1, close).trim()
          : '';
      final lastSpace = inner.lastIndexOf(' ');
      final className = lastSpace > 0 ? inner.substring(0, lastSpace) : inner;
      final section = lastSpace > 0 ? inner.substring(lastSpace + 1) : '';
      cnameMap[k] = inner.isNotEmpty ? '$className ($section)' : '$k';
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Class Teacher অনুরোধ'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('আপনি যে class-এ ভর্তি/নিয়ন্ত্রণ নিতে চান সেটি বেছে নিন। Admin অনুমোদনের পর class teacher হবেন।',
              style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: selectedId,
            decoration: const InputDecoration(labelText: 'Class *', border: OutlineInputBorder()),
            items: requestable.map((cid) => DropdownMenuItem<int>(
                value: cid,
                child: Text('${cnameMap[cid] ?? cid}${pendingIds.contains(cid) ? ' (pending)' : ''}'))).toList(),
            onChanged: (v) => selectedId = v,
          ),
          const SizedBox(height: 12),
          TextField(controller: noteCtl, maxLines: 2,
              decoration: const InputDecoration(labelText: 'নোট (ঐচ্ছিক)', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit Request')),
        ],
      ),
    );
    if (saved != true || selectedId == null) return;
    try {
      await Api.post('/teacher/class-teacher-request', {
        'class_id': selectedId,
        'note': noteCtl.text.trim().isEmpty ? null : noteCtl.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Colors.green, content: Text('অনুরোধ পাঠানো হয়েছে। Admin অনুমোদন করলে class teacher হবেন।')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _editInfo() async {
    final tv = _profile?['teacher'] as Map? ?? widget.teacher;
    final name = tv['name'] ?? '';
    final rawDesig = tv['designation'];
    final designation = rawDesig == null ? '' : '$rawDesig';
    final nameCtl = TextEditingController(text: '$name');
    final desigCtl = TextEditingController(text: designation);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Info'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtl, decoration: const InputDecoration(labelText: 'Name'), textCapitalization: TextCapitalization.words),
          const SizedBox(height: 10),
          TextField(controller: desigCtl, decoration: const InputDecoration(labelText: 'Designation (পদবি)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved != true) return;
    final r = await Api.put('/teacher/profile', {
      'name': nameCtl.text.trim(),
      'designation': desigCtl.text.trim(),
    });
    if (!mounted) return;
    if (r is Map && r['ok'] == true) {
      await Api.saveToken(r['token']);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated')));
      await _load();
      if (!mounted) return;
      setState(() {});
      // refresh splash so UI carries new name
      if (r['user'] != null && mounted) {
        final nav = Navigator.of(context);
        nav.pushReplacement(MaterialPageRoute(builder: (_) => const SplashScreen()));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r is Map ? '${r['error'] ?? 'Failed'}' : 'Failed')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final subjects = _profile?['subjects'] as List? ?? [];
    final classes = _profile?['classes'] as List? ?? [];
    final teacher = _profile?['teacher'] as Map? ?? widget.teacher;
    final designation = teacher['designation'] ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Profile'), actions: [
        IconButton(icon: const Icon(Icons.edit), tooltip: 'Edit Info', onPressed: _saving ? null : _editInfo),
        IconButton(icon: const Icon(Icons.logout), onPressed: () async {
          unregisterDeviceToken();
          final messenger = ScaffoldMessenger.of(context);
          final nav = Navigator.of(context);
          await Api.clearToken();
          if (!mounted) return;
          nav.pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
          messenger.clearSnackBars();
        }),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          CircleAvatar(radius: 30, backgroundColor: Colors.teal.shade100,
              child: Text('${teacher['name']}'.characters.first, style: const TextStyle(fontSize: 24))),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${teacher['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (designation != null && '$designation'.trim().isNotEmpty)
              Text('$designation', style: TextStyle(color: Colors.teal.shade700, fontWeight: FontWeight.w600)),
            Text('ID: ${_teacherId()}', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
          ]),
        ]))),
        const SizedBox(height: 12),
        Card(child: ListTile(
          leading: const Icon(Icons.menu_book),
          title: Text('আমার Subjects (${subjects.length})'),
          subtitle: Text(subjects.map((s) => '${s['name']} (${s['class_name']} ${s['section']})').join(', ')),
        )),
        Card(child: ListTile(
          leading: const Icon(Icons.class_),
          title: Text('Class Teacher of (${classes.length})'),
          subtitle: Text(classes.isEmpty
              ? 'কোনো class assign করা নেই'
              : classes.map((c) => '${c['name']} (${c['section']}) — ${c['student_count']} students').join(', ')),
        )),
        const SizedBox(height: 12),
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Class Teacher Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
            FilledButton.tonal(onPressed: _requestDialog, child: const Text('+ অনুরোধ')),
          ]),
          const SizedBox(height: 8),
          if (_ctr.isEmpty)
            const Text('কোনো pending/recent অনুরোধ নেই।', style: TextStyle(color: Colors.grey, fontSize: 13))
          else
            ..._ctr.take(5).map((r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Icon(Icons.circle, size: 10,
                    color: r['status'] == 'approved' ? Colors.green : (r['status'] == 'pending' ? Colors.orange : Colors.red)),
                const SizedBox(width: 8),
                Expanded(child: Text('${r['class_name']} (${r['group_name'] ?? r['section']})',
                    style: const TextStyle(fontSize: 13))),
                Text('${r['status']}', style: TextStyle(fontSize: 12,
                    color: r['status'] == 'approved' ? Colors.green : Colors.grey)),
              ]),
            )),
        ]))),
        const SizedBox(height: 12),
        const Card(color: Color(0xFFE0F2F1), child: Padding(
          padding: EdgeInsets.all(14),
          child: Text('ℹ️ Exam-এ marks দেওয়ার পর ১০ মিনিট edit করা যায়। এরপর admin unlock ছাড়া সম্ভব নয়।',
              style: TextStyle(fontSize: 13)),
        )),
        const SizedBox(height: 12),
        Card(child: ListTile(
          leading: const Icon(Icons.system_update_alt, color: Colors.teal),
          title: const Text('অ্যাপ আপডেট'),
          subtitle: Text('বর্তমান version: v$appVersion — নতুন update চেক করুন'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => checkForUpdate(context, 'teacher', manual: true),
        )),
      ]),
    );
  }
}

