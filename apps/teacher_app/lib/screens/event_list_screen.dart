import 'package:flutter/material.dart';
import '../api.dart';
import 'event_detail_screen.dart';

/// Exam events visible to this teacher (class-teacher classes or own exams),
/// with per-class coverage chips: কতজন entry / কত subject.
class EventListScreen extends StatefulWidget {
  final dynamic teacher;
  const EventListScreen({super.key, required this.teacher});
  @override
  State<EventListScreen> createState() => _EventListScreenState();
}

class _EventListScreenState extends State<EventListScreen> {
  List _events = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (_events.isEmpty) setState(() { _loading = true; _error = null; });
    try {
      await Api.loadCachedFirst('/teacher/events', (r) {
        if (!mounted) return;
        setState(() { _events = r is List ? r : []; _loading = false; });
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  String _kindLabel(dynamic kind) {
    switch ('$kind') {
      case 'half_yearly': return 'Half Yearly';
      case 'annual': return 'Annual';
      case 'pretest': return 'Pre-Test';
      case 'test': return 'Test';
      default: return 'Other';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exam Events & Results'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Padding(padding: const EdgeInsets.all(16),
                      child: Text(_error!, textAlign: TextAlign.center)),
                  FilledButton.tonal(onPressed: _load, child: const Text('আবার চেষ্টা করুন')),
                ]))
              : _events.isEmpty
                  ? const Center(child: Padding(padding: EdgeInsets.all(24),
                      child: Text('কোনো exam event নেই।\n\nAdmin-created exam শুধু সেই class-এর Class Teacher দেখতে পান।',
                          textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, height: 1.5))))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _events.length,
                      itemBuilder: (_, i) {
                        final e = _events[i];
                        final classes = (e['my_classes'] as List?) ?? const [];
                        final published = e['is_published'] == 1;
                        return Card(
                          child: InkWell(
                            onTap: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => EventDetailScreen(
                                    eventId: e['id'], eventName: '${e['name']}', event: e))),
                            child: Padding(padding: const EdgeInsets.all(12), child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Expanded(child: Text('${e['name']}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                                  Chip(
                                    backgroundColor: published ? Colors.green : Colors.orange,
                                    label: Text(published ? 'Published' : 'Running',
                                        style: const TextStyle(color: Colors.white, fontSize: 10)),
                                  ),
                                ]),
                                const SizedBox(height: 4),
                                Wrap(spacing: 6, children: [
                                  Chip(label: Text(_kindLabel(e['exam_kind']), style: const TextStyle(fontSize: 11))),
                                  if (e['promotion_linked'] == 1)
                                    const Chip(label: Text('Promotion জড়িত', style: TextStyle(fontSize: 11))),
                                ]),
                                const SizedBox(height: 6),
                                for (final c in classes)
                                  Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [
                                    Expanded(child: Text(
                                        '${c['class_name']} (${c['group_name'] ?? c['section']})',
                                        style: const TextStyle(fontSize: 13))),
                                    Text('${c['students_with_marks']}/${c['student_count']} জন',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    const SizedBox(width: 8),
                                    Text('${c['subjects_with_marks']}/${c['subject_count']} বিষয়',
                                        style: const TextStyle(fontSize: 12, color: Colors.teal)),
                                  ])),
                              ],
                            )),
                          ),
                        );
                      },
                    ),
    );
  }
}
