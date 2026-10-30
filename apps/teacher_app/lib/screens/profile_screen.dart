import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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
  bool _signatureBusy = false;
  List _ctr = [];
  List _subjects = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

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
      await Future.wait([
        Api.loadCachedFirst('/teacher/profile', (r) {
          if (!mounted || r is! Map) return;
          setState(() => _profile = r);
        }),
        Api.loadCachedFirst('/teacher/class-teacher-requests', (r) {
          if (!mounted) return;
          setState(() => _ctr = r is List ? r : []);
        }),
        Api.loadCachedFirst('/teacher/subjects', (r) {
          if (!mounted) return;
          setState(() => _subjects = r is List ? r : []);
        }),
      ]);
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
      teachMap
          .putIfAbsent(cid, () => [])
          .add('${s['name']} (${s['class_name']} ${s['section']})');
    }
    final requestable =
        teachClassIds.where((cid) => !ctIds.contains(cid)).toList()..sort();
    final pendingIds = _ctr
        .where((r) => r['status'] == 'pending')
        .map((r) => r['class_id'])
        .toSet();
    if (requestable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.orange.shade700,
          content: const Text(
            'আপনি এমন কোনো class-এ subject পড়ান না যেখানে আপনি এখনো class teacher নন।\nনতুন class teacher অনুরোধ admin panel থেকে সরাসরি assign করা যায়।',
          ),
        ),
      );
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'আপনি যে class-এ ভর্তি/নিয়ন্ত্রণ নিতে চান সেটি বেছে নিন। Admin অনুমোদনের পর class teacher হবেন।',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: selectedId,
              decoration: const InputDecoration(
                labelText: 'Class *',
                border: OutlineInputBorder(),
              ),
              items: requestable
                  .map(
                    (cid) => DropdownMenuItem<int>(
                      value: cid,
                      child: Text(
                        '${cnameMap[cid] ?? cid}${pendingIds.contains(cid) ? ' (pending)' : ''}',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => selectedId = v,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'নোট (ঐচ্ছিক)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Submit Request'),
          ),
        ],
      ),
    );
    if (saved != true || selectedId == null) return;
    try {
      final r = await Api.post('/teacher/class-teacher-request', {
        'class_id': selectedId,
        'note': noteCtl.text.trim().isEmpty ? null : noteCtl.text.trim(),
      });
      if (!mounted) return;
      if (Api.isQueued(r)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text(
              'ইন্টারনেট নেই — অনুরোধ queue-তে আছে, online হলে যাবে',
            ),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.green,
          content: Text(
            'অনুরোধ পাঠানো হয়েছে। Admin অনুমোদন করলে class teacher হবেন।',
          ),
        ),
      );
      await _load();
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

  Future<void> _changePasswordDialog() async {
    final curCtl = TextEditingController();
    final newCtl = TextEditingController();
    final confCtl = TextEditingController();
    var obscure = true;
    final dlgCtx = context;
    final ok = await showDialog<bool>(
      context: dlgCtx,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Password পরিবর্তন'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: curCtl,
                obscureText: obscure,
                decoration: const InputDecoration(
                  labelText: 'বর্তমান password *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: newCtl,
                obscureText: obscure,
                decoration: const InputDecoration(
                  labelText: 'নতুন password (কমপক্ষে ৬ অক্ষর) *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: confCtl,
                obscureText: obscure,
                decoration: const InputDecoration(
                  labelText: 'নতুন password আবার *',
                  border: OutlineInputBorder(),
                ),
              ),
              Row(
                children: [
                  Checkbox(
                    value: !obscure,
                    onChanged: (v) => setD(() => obscure = !(v ?? false)),
                  ),
                  const Text('দেখান', style: TextStyle(fontSize: 13)),
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
              child: const Text('পরিবর্তন'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (!context.mounted) return;
    if (curCtl.text.isEmpty || newCtl.text.length < 6) {
      ScaffoldMessenger.of(dlgCtx).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            'বর্তমান password দিন ও নতুন password কমপক্ষে ৬ অক্ষরের হতে হবে।',
          ),
        ),
      );
      return;
    }
    if (newCtl.text != confCtl.text) {
      ScaffoldMessenger.of(dlgCtx).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('নতুন password দুবার এক হয়নি।'),
        ),
      );
      return;
    }
    // Confirmation popup — teacher taps OK, old is replaced immediately.
    final pwdCtx = context;
    final confirm = await showDialog<bool>(
      context: pwdCtx,
      builder: (ctx) => AlertDialog(
        title: const Text('নিশ্চিত?'),
        content: const Text(
          'OK চাপলেই পুরনো password বদলে নতুনটা কার্যকর হবে।',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final r = await Api.put('/teacher/profile/password', {
        'current_password': curCtl.text,
        'new_password': newCtl.text,
      });
      if (!context.mounted) return;
      if (Api.isQueued(r)) {
        ScaffoldMessenger.of(pwdCtx).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text(
              'ইন্টারনেট নেই — request queue-তে আছে, online হলে পাঠানো হবে',
            ),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(pwdCtx).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.green,
          content: Text(
            'Password বদলে গেছে। পরের বার নতুন password দিয়ে login করবেন।',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(pwdCtx).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _uploadSignature() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
    );
    if (image == null) return;
    setState(() => _signatureBusy = true);
    try {
      await Api.uploadFile(
        '/teacher/signature',
        image.path,
        field: 'signature',
      );
      final fresh = await Api.refreshCache('/teacher/profile');
      if (!mounted) return;
      if (fresh is Map) {
        setState(() => _profile = fresh);
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('স্বাক্ষর আপলোড হয়েছে')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text(e.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _signatureBusy = false);
    }
  }

  Future<void> _removeSignature() async {
    setState(() => _signatureBusy = true);
    try {
      await Api.delete('/teacher/signature');
      final fresh = await Api.refreshCache('/teacher/profile');
      if (!mounted) return;
      if (fresh is Map) {
        setState(() => _profile = fresh);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('স্বাক্ষর মুছে ফেলা হয়েছে')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text(e.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _signatureBusy = false);
    }
  }

  Future<void> _editInfo() async {
    final tv = _profile?['teacher'] as Map? ?? widget.teacher;
    final name = tv['name'] ?? '';
    final phone = tv['phone']?.toString() ?? '';
    final nameCtl = TextEditingController(text: '$name');
    final phoneCtl = TextEditingController(text: phone);
    String fieldDate(dynamic value) =>
        value == null ? '' : value.toString().split('T').first;
    final dobCtl = TextEditingController(text: fieldDate(tv['teacher_dob']));
    final addressCtl = TextEditingController(
      text: '${tv['teacher_address'] ?? ''}',
    );
    final bloodCtl = TextEditingController(
      text: '${tv['teacher_blood_group'] ?? ''}',
    );
    final indexCtl = TextEditingController(
      text: '${tv['teacher_index_number'] ?? ''}',
    );
    final pnsCtl = TextEditingController(
      text: '${tv['teacher_pns_number'] ?? ''}',
    );
    final degreeCtl = TextEditingController(
      text: '${tv['teacher_degree'] ?? ''}',
    );
    final joiningCtl = TextEditingController(
      text: fieldDate(tv['teacher_joining_date']),
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('শিক্ষকের তথ্য'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtl,
                decoration: const InputDecoration(labelText: 'Name'),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 10),
              const Text(
                'পদবি Admin নির্ধারণ করেন। পরিবর্তনের জন্য Admin-এর সঙ্গে যোগাযোগ করুন।',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneCtl,
                decoration: const InputDecoration(
                  labelText: 'Phone (01XXXXXXXXX)',
                  hintText: '01XXXXXXXXX',
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'নিচের তথ্যগুলো ঐচ্ছিক; Guardian app-এ শুধু নাম ও ফোন দেখানো হয়।',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              TextField(
                controller: dobCtl,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(
                  labelText: 'জন্মতারিখ (YYYY-MM-DD)',
                ),
              ),
              TextField(
                controller: addressCtl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'ঠিকানা'),
              ),
              TextField(
                controller: bloodCtl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'রক্তের গ্রুপ'),
              ),
              TextField(
                controller: indexCtl,
                decoration: const InputDecoration(labelText: 'Index number'),
              ),
              TextField(
                controller: pnsCtl,
                decoration: const InputDecoration(labelText: 'PNS number'),
              ),
              TextField(
                controller: degreeCtl,
                decoration: const InputDecoration(
                  labelText: 'শিক্ষাগত যোগ্যতা / Degree',
                ),
              ),
              TextField(
                controller: joiningCtl,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(
                  labelText: 'যোগদানের তারিখ (YYYY-MM-DD)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final phoneV = phoneCtl.text.trim();
    if (phoneV.isNotEmpty && !RegExp(r'^01\d{9}$').hasMatch(phoneV)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            'Phone must be 11 digits starting with 01 (যেমন 01712345678)',
          ),
        ),
      );
      return;
    }
    final r = await Api.put('/teacher/profile', {
      'name': nameCtl.text.trim(),
      'phone': phoneV.isEmpty ? null : phoneV,
      'teacher_dob': dobCtl.text.trim().isEmpty ? null : dobCtl.text.trim(),
      'teacher_address': addressCtl.text.trim().isEmpty
          ? null
          : addressCtl.text.trim(),
      'teacher_blood_group': bloodCtl.text.trim().isEmpty
          ? null
          : bloodCtl.text.trim(),
      'teacher_index_number': indexCtl.text.trim().isEmpty
          ? null
          : indexCtl.text.trim(),
      'teacher_pns_number': pnsCtl.text.trim().isEmpty
          ? null
          : pnsCtl.text.trim(),
      'teacher_degree': degreeCtl.text.trim().isEmpty
          ? null
          : degreeCtl.text.trim(),
      'teacher_joining_date': joiningCtl.text.trim().isEmpty
          ? null
          : joiningCtl.text.trim(),
    });
    if (!mounted) return;
    if (Api.isQueued(r)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orange,
          content: Text(
            'ইন্টারনেট নেই — পরিবর্তন queue-তে আছে, online হলে যাবে',
          ),
        ),
      );
      return;
    }
    if (r is Map && r['ok'] == true) {
      await Api.saveToken(r['token']);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Profile updated')));
      await _load();
      if (!mounted) return;
      setState(() {});
      // refresh splash so UI carries new name
      if (r['user'] != null && mounted) {
        final nav = Navigator.of(context);
        nav.pushReplacement(
          MaterialPageRoute(builder: (_) => const SplashScreen()),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(r is Map ? '${r['error'] ?? 'Failed'}' : 'Failed'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final subjects = _profile?['subjects'] as List? ?? [];
    final classes = _profile?['classes'] as List? ?? [];
    final teacher = _profile?['teacher'] as Map? ?? widget.teacher;
    final designation = teacher['designation'] ?? '';
    final teacherName = '${teacher['name'] ?? 'Teacher'}';
    return Scaffold(
      backgroundColor: const Color(0xFFF2F5FA),
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Info',
            onPressed: _saving ? null : _editInfo,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final nav = Navigator.of(context);
              await unregisterDeviceToken();
              await Api.clearToken();
              if (!mounted) return;
              nav.pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
              messenger.clearSnackBars();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF1E3A5F),
                  Color(0xFF356D86),
                  Color(0xFF258A7A),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1E3A5F).withValues(alpha: .18),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: Colors.white.withValues(alpha: .18),
                  foregroundColor: Colors.white,
                  child: Text(
                    teacherName.trim().isEmpty
                        ? 'T'
                        : teacherName.trim().characters.first.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        teacherName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if ('$designation'.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          '$designation',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'শিক্ষক ID  ${_teacherId()}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ProfileStat(
                  icon: Icons.menu_book_rounded,
                  value: '${subjects.length}',
                  label: 'বিষয়',
                  color: const Color(0xFF635BDB),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ProfileStat(
                  icon: Icons.class_rounded,
                  value: '${classes.length}',
                  label: 'Class teacher class',
                  color: const Color(0xFF0C8B78),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: ListTile(
              leading: Icon(
                Icons.draw_outlined,
                color: teacher['signature_url'] != null
                    ? Colors.green
                    : Colors.blueGrey,
              ),
              title: const Text('স্বাক্ষর'),
              subtitle: Text(
                teacher['signature_url'] != null
                    ? 'আপনার স্বাক্ষর marksheet ও admit card-এ ব্যবহার হবে।'
                    : 'সাদা কাগজে গাঢ় কালিতে সই করে ছবি তুলুন।',
              ),
              trailing: _signatureBusy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'স্বাক্ষর আপলোড',
                          icon: const Icon(Icons.upload_file),
                          onPressed: _uploadSignature,
                        ),
                        if (teacher['signature_url'] != null)
                          IconButton(
                            tooltip: 'স্বাক্ষর মুছুন',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: _removeSignature,
                          ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: ListTile(
              leading: const Icon(Icons.menu_book),
              title: Text('আমার Subjects (${subjects.length})'),
              subtitle: Text(
                subjects
                    .map(
                      (s) =>
                          '${s['name']} (${s['class_name']} ${s['section']})',
                    )
                    .join(', '),
              ),
            ),
          ),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: ListTile(
              leading: const Icon(Icons.class_),
              title: Text('Class Teacher of (${classes.length})'),
              subtitle: Text(
                classes.isEmpty
                    ? 'কোনো class assign করা নেই'
                    : classes
                          .map(
                            (c) =>
                                '${c['name']} (${c['section']}) — ${c['student_count']} students',
                          )
                          .join(', '),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Class Teacher Status',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      FilledButton.tonal(
                        onPressed: _requestDialog,
                        child: const Text('+ অনুরোধ'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_ctr.isEmpty)
                    const Text(
                      'কোনো pending/recent অনুরোধ নেই।',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    )
                  else
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ..._ctr
                            .take(5)
                            .map(
                              (r) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 3,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.circle,
                                      size: 10,
                                      color: r['status'] == 'approved'
                                          ? Colors.green
                                          : (r['status'] == 'pending'
                                                ? Colors.orange
                                                : Colors.red),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${r['class_name']} (${r['group_name'] ?? r['section']})',
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                    Text(
                                      '${r['status']}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: r['status'] == 'approved'
                                            ? Colors.green
                                            : Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: Color(0xFFE0F2F1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'ℹ️ Draft marks Save করে submit না করা পর্যন্ত edit করা যায়। Submit-এর পর re-entry আবেদন Admin অনুমোদন করলে আবার edit করা যাবে।',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.system_update_alt, color: Colors.teal),
              title: const Text('অ্যাপ আপডেট'),
              // Scientific fix: show version AND build (e.g. v1.4.1 • build
              // 1791835509). The old tile showed only "v1.4.1" — identical text
              // before AND after a same-version rebuild, which made users (rightly)
              // believe "update করলাম অথচ কিছু বদলালো না". Build number is the
              // true identity of a binary; version string is just a label.
              subtitle: FutureBuilder(
                future: Future.wait([installedVersion(), installedBuild()]),
                builder: (_, s) {
                  final v = s.data is List
                      ? (s.data as List)[0].toString()
                      : '…';
                  final b = s.data is List
                      ? (s.data as List)[1].toString()
                      : '…';
                  return Text(
                    'ফোনে: v$v • build $b — tap করে সার্ভারের সাথে মিলান',
                  );
                },
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => checkForUpdate(context, 'teacher', manual: true),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.lock_reset_outlined,
                color: Colors.indigo,
              ),
              title: const Text('Password পরিবর্তন'),
              subtitle: const Text('নতুন দিলেই পুরনোটা বদলে যাবে'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _changePasswordDialog(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _ProfileStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: color.withValues(alpha: .12)),
    ),
    child: Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: color.withValues(alpha: .1),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
