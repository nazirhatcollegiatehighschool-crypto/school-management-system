import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import '../api.dart';
import '../pdf_helper.dart';

class HomeworkScreen extends StatefulWidget {
  final dynamic teacher;
  const HomeworkScreen({super.key, required this.teacher});
  @override
  State<HomeworkScreen> createState() => _HomeworkScreenState();
}

class _HomeworkScreenState extends State<HomeworkScreen> {
  List _homework = [];
  List _classes = [];
  List _subjects = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadClasses();
    _load();
  }

  Future<void> _loadClasses() async {
    try {
      final r = await Api.get('/teacher/profile');
      if (!mounted) return;
      final classes = <int, Map>{};
      for (final c in (r['classes'] as List? ?? [])) {
        final id = int.tryParse('${c['id']}');
        if (id != null) {
          classes[id] = {
            ...Map<String, dynamic>.from(c as Map),
            'class_name': c['class_name'] ?? c['name'],
          };
        }
      }
      for (final s in (r['subjects'] as List? ?? [])) {
        final id = int.tryParse('${s['class_id']}');
        if (id != null) {
          classes.putIfAbsent(
            id,
            () => {
              'id': id,
              'class_name': s['class_name'],
              'section': s['section'],
            },
          );
        }
      }
      setState(() {
        _classes = classes.values.toList();
        _subjects = List.from(r['subjects'] ?? const []);
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      await Api.loadCachedFirst('/teacher/homework', (r) {
        if (!mounted) return;
        setState(() {
          _homework = r;
          _loading = false;
          _error = null;
        });
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _createHomework() async {
    if (_classes.isEmpty) return;
    final descCtrl = TextEditingController();
    int? classId = _classes.first['id'] as int;
    int? subjectId;
    subjectId = _subjectForClass(classId)?['id'] as int?;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setCtx) {
            return AlertDialog(
              title: const Text('আজকের পড়া যোগ করুন'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: classId,
                      decoration: const InputDecoration(labelText: 'Class'),
                      items: _classes
                          .map(
                            (c) => DropdownMenuItem(
                              value: c['id'] as int,
                              child: Text(
                                '${c['class_name']} (${c['section']})',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setCtx(() {
                        classId = v;
                        subjectId = _subjectForClass(v)?['id'] as int?;
                      }),
                    ),
                    DropdownButtonFormField<int>(
                      initialValue: subjectId,
                      decoration: const InputDecoration(labelText: 'বিষয়'),
                      items: _subjects
                          .where((s) => '${s['class_id']}' == '$classId')
                          .map(
                            (s) => DropdownMenuItem<int>(
                              value: s['id'] as int,
                              child: Text('${s['name']}'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setCtx(() => subjectId = v),
                    ),
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(
                        labelText: 'আজ কী পড়িয়েছেন?',
                        hintText:
                            'অধ্যায়, পৃষ্ঠা, বিষয়বস্তু বা classwork লিখুন',
                      ),
                      minLines: 4,
                      maxLines: 7,
                      autofocus: true,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'তারিখ আজকের তারিখ হিসেবে নিজে থেকে যুক্ত হবে।',
                      style: TextStyle(
                        color: Colors.blueGrey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('বাতিল'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (descCtrl.text.trim().isEmpty || subjectId == null) {
                      return;
                    }
                    Navigator.pop(ctx);
                    try {
                      final r = await Api.post('/teacher/homework', {
                        'class_id': classId,
                        'subject_id': subjectId,
                        'title': 'আজকের পড়া',
                        'description': descCtrl.text.trim(),
                      });
                      _load();
                      if (!mounted) return;
                      if (Api.isQueued(r)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: Colors.orange,
                            content: Text(
                              'ইন্টারনেট নেই — homework ফোনে সেভ আছে, online হলেই যাবে',
                            ),
                          ),
                        );
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'আজকের পড়া অভিভাবক অ্যাপে পাঠানো হয়েছে',
                          ),
                        ),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: Colors.red,
                          content: Text(
                            e.toString().replaceFirst('Exception: ', ''),
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text('অভিভাবককে পাঠান'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Map? _subjectForClass(int? classId) {
    for (final subject in _subjects) {
      if ('${subject['class_id']}' == '$classId') return subject as Map;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('আজকের পড়া')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createHomework,
        icon: const Icon(Icons.edit_note),
        label: const Text('আজকের পড়া যোগ করুন'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _homework.length,
                itemBuilder: (_, i) {
                  final h = _homework[i];
                  final attachments = (h['attachments'] as List?) ?? [];
                  final hasDue = h['due_date'] != null;

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.grey.withValues(alpha: 0.12),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () async {
                          await showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => _HomeworkFilesSheet(
                              homework: h,
                              onChanged: _load,
                            ),
                          );
                          _load();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      h['title'] ?? '',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                  ),
                                  if (hasDue)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFEF3C7),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: const Color(0xFFFDE68A),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.schedule_rounded,
                                            size: 12,
                                            color: Color(0xFFB45309),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Due ${h['due_date'].toString().substring(0, 10)}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFFB45309),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFECFDF5),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: const Color(0xFFA7F3D0),
                                      ),
                                    ),
                                    child: Text(
                                      '${h['class_name']} (${h['section']})',
                                      style: const TextStyle(
                                        color: Color(0xFF065F46),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (h['subject_name'] != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEFF6FF),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: const Color(0xFFBFDBFE),
                                        ),
                                      ),
                                      child: Text(
                                        h['subject_name'].toString(),
                                        style: const TextStyle(
                                          color: Color(0xFF1D4ED8),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  if (attachments.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '📎 ${attachments.length} ফাইল',
                                        style: TextStyle(
                                          color: Colors.grey.shade700,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if ((h['description'] ?? '')
                                  .toString()
                                  .isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  h['description'].toString(),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.blueGrey.shade700,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// Homework file manager: view/open attachments, add photo (camera/gallery)
/// or document (PDF), delete own files. Works online; uploads need internet.
class _HomeworkFilesSheet extends StatefulWidget {
  final Map homework;
  final VoidCallback onChanged;
  const _HomeworkFilesSheet({required this.homework, required this.onChanged});

  @override
  State<_HomeworkFilesSheet> createState() => _HomeworkFilesSheetState();
}

class _HomeworkFilesSheetState extends State<_HomeworkFilesSheet> {
  List _files = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.get(
        '/teacher/homework/${widget.homework['id']}/attachments',
      );
      if (!mounted) return;
      setState(() {
        _files = r is List ? r : [];
        _loading = false;
      });
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  bool _isImg(String name, String mime) {
    final n = name.toLowerCase();
    return mime.startsWith('image/') ||
        n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.png') ||
        n.endsWith('.webp') ||
        n.endsWith('.gif');
  }

  String _size(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  Future<void> _upload(String filePath) async {
    setState(() => _busy = true);
    try {
      await Api.uploadFile(
        '/teacher/homework/${widget.homework['id']}/attachments',
        filePath,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.green,
          content: Text('ফাইল যোগ হয়েছে ✓'),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            Api.isNetworkError(e)
                ? 'ইন্টারনেট নেই — ফাইল আপলোডের জন্য online থাকতে হবে'
                : e.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickPhoto() async {
    final src = await showDialog<ImageSource>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ছবি যোগ করুন'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery থেকে'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera দিয়ে তুলুন'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (src == null) return;
    try {
      final x = await ImagePicker().pickImage(
        source: src,
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (x != null) await _upload(x.path);
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

  Future<void> _pickDoc() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      );
      if (files.isNotEmpty && files.single.path != null) {
        await _upload(files.single.path!);
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

  Future<void> _deleteFile(dynamic a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ফাইল মুছবেন?'),
        content: Text('"${a['file_name']}" মুছে ফেলা হবে।'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('মুছুন'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.delete('/teacher/homework/attachments/${a['id']}');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('ফাইল মোছা হয়েছে')));
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

  @override
  Widget build(BuildContext context) {
    final h = widget.homework;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${h['title']}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            Text(
              '${h['class_name']} (${h['section']})${h['subject_name'] != null ? ' • ${h['subject_name']}' : ''}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: const Text('ছবি', style: TextStyle(fontSize: 13)),
                    onPressed: _busy ? null : _pickPhoto,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const Text(
                      'PDF/ফাইল',
                      style: TextStyle(fontSize: 13),
                    ),
                    onPressed: _busy ? null : _pickDoc,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_busy) const LinearProgressIndicator(),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_files.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'কোনো ফাইল নেই — উপরে বাটনে ফাইল যোগ করুন',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _files.length,
                  itemBuilder: (_, i) {
                    final a = _files[i];
                    final mime = '${a['mime_type'] ?? ''}';
                    final img = _isImg('${a['file_name'] ?? ''}', mime);
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          img
                              ? Icons.image_outlined
                              : Icons.picture_as_pdf_outlined,
                          color: img ? Colors.teal : Colors.red,
                        ),
                        title: Text(
                          '${a['file_name']}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          _size(a['file_size'] as int?),
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.visibility_outlined,
                                size: 20,
                              ),
                              tooltip: 'দেখুন',
                              onPressed: () => PdfHelper.download(
                                context,
                                '/uploads/homework/${a['file_path']}',
                                '${a['file_name']}',
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: Colors.red,
                              ),
                              tooltip: 'মুছুন',
                              onPressed: () => _deleteFile(a),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
