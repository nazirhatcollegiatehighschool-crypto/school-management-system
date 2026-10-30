import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../api.dart';
import '../pdf/marksheet_template.dart';

class MarksheetScreen extends StatefulWidget {
  final int studentId;
  final String studentName;
  const MarksheetScreen({
    super.key,
    required this.studentId,
    required this.studentName,
  });
  @override
  State<MarksheetScreen> createState() => _MarksheetScreenState();
}

class _MarksheetScreenState extends State<MarksheetScreen> {
  List? _events;
  Map? _data;
  List? _families;
  String? _selectedEventId;
  String? _error;
  bool _loadingMarksheet = false;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    try {
      final events = await Api.get(
        '/guardian/student/${widget.studentId}/exam-events',
      );
      setState(() {
        _events = events is List ? events : [];
        if (_events!.isNotEmpty) {
          _selectedEventId = _events![0]['id'].toString();
        }
      });
      if (_selectedEventId != null) _loadMarksheet();
    } catch (e) {
      setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _loadMarksheet() async {
    if (_selectedEventId == null) return;
    setState(() => _loadingMarksheet = true);
    try {
      final data = await Api.get(
        '/guardian/student/${widget.studentId}/result-card?event_id=$_selectedEventId',
      );
      setState(() {
        _data = data;
        // Q8: a conditional / not-all-pass student receives result:null — the
        // detail is withheld server-side, so there are no families to show.
        _families = data['result']?['families'] is List
            ? (data['result']!['families'] as List)
            : [];
        _error = null;
        _loadingMarksheet = false;
      });
    } catch (e) {
      setState(() {
        _error = friendlyError(e);
        _loadingMarksheet = false;
      });
    }
  }

  String _promotionLabel(Map promotion) {
    if (promotion.isEmpty) return '';
    final parts = <String>[];
    final status = '${promotion['status_bn'] ?? ''}'.trim();
    if (status.isNotEmpty) parts.add(status);
    final target = '${promotion['to_class'] ?? ''}'.trim();
    if (target.isNotEmpty) parts.add(target);
    final roll = '${promotion['promoted_roll'] ?? ''}'.trim();
    if (roll.isNotEmpty) parts.add('New roll $roll');
    return parts.join(' • ');
  }

  Future<void> _downloadPdf() async {
    if (_data == null) return;
    final data = _data!;
    final student = data['student'] is Map ? data['student'] as Map : const {};
    final event = data['event'] is Map ? data['event'] as Map : const {};
    final settings = data['settings'] is Map
        ? data['settings'] as Map
        : const {};
    final promotion = data['promotion'] is Map
        ? data['promotion'] as Map
        : const {};
    final signatures = data['signatures'] is Map
        ? data['signatures'] as Map
        : const {};
    final hidden = data['marksheet_hidden'] == true;
    final result = !hidden && data['result'] is Map
        ? data['result'] as Map
        : const {};
    final families = hidden
        ? <dynamic>[]
        : (result['families'] is List
              ? result['families'] as List
              : <dynamic>[]);
    final attendance = data['attendance'] is Map
        ? data['attendance'] as Map
        : const {};
    final position = data['position'] is Map
        ? data['position'] as Map
        : const {};
    final dual = data['dual_position'] is Map
        ? data['dual_position'] as Map
        : const {};
    String attendanceText = '';
    if (attendance['percentage'] != null) {
      attendanceText =
          '${attendance['percentage']}% (${attendance['present_days']}/${attendance['total_days']} days)';
    }
    String positionText = '';
    if (dual.isNotEmpty &&
        (dual['section'] != null || dual['combined'] != null)) {
      positionText =
          'Section ${dual['section'] ?? '-'}/${dual['section_of'] ?? '-'} | All sections ${dual['combined'] ?? '-'}/${dual['combined_of'] ?? '-'}';
    } else if (position.isNotEmpty) {
      positionText = '${position['rank'] ?? '-'}/${position['of'] ?? '-'}';
    }

    final bnData = await rootBundle.load('assets/fonts/Kalpurush.ttf');
    final bn = pw.Font.ttf(bnData);
    final logoData = await rootBundle.load('assets/school_logo.png');
    final logo = pw.MemoryImage(logoData.buffer.asUint8List());
    final watermark = await MarksheetTemplate.loadWatermark();
    final script = await MarksheetTemplate.loadScriptFont();
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageTheme: MarksheetTemplate.pageTheme(
          watermark: watermark,
          margin: 32,
        ),
        build: (_) => MarksheetTemplate.build(
          banglaFont: bn,
          scriptFont: script,
          logo: logo,
          schoolName:
              '${settings['school_name'] ?? 'Nazirhat Collegiate High School'}',
          schoolAddress:
              '${settings['school_address'] ?? settings['address'] ?? ''}',
          eventName: '${event['name'] ?? ''}',
          student: student,
          event: event,
          result: result,
          families: families,
          serialNo: '${data['serial_no'] ?? ''}',
          attendanceText: attendanceText,
          positionText: positionText,
          classHighestGpa: '${data['class_highest_gpa'] ?? ''}',
          remarks: '${data['remarks'] ?? ''}',
          promotionText: _promotionLabel(promotion),
          signatures: signatures,
        ),
      ),
    );
    doc.addPage(
      pw.MultiPage(
        maxPages: 200,
        pageTheme: MarksheetTemplate.pageTheme(
          watermark: watermark,
          margin: 32,
        ),
        build: (_) => MarksheetTemplate.buildActivitiesPage(
          banglaFont: bn,
          schoolName:
              '${settings['school_name'] ?? 'Nazirhat Collegiate High School'}',
          eventName: '${event['name'] ?? ''}',
          student: student,
          activities: data['activities'] is Map
              ? data['activities'] as Map
              : const {},
          activityPeriod: data['activity_period'] is Map
              ? data['activity_period'] as Map
              : const {},
        ),
      ),
    );
    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: 'resultcard_${event['name'] ?? 'exam'}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('সেশনভিত্তিক ফলাফল'),
        actions: [
          if (_data != null)
            IconButton(
              icon: const Icon(Icons.description_outlined),
              tooltip: 'Result Card',
              onPressed: () => _showResultCard(),
            ),
          if (_data != null)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: 'PDF',
              onPressed: () async {
                try {
                  await _downloadPdf();
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('PDF error: $e')));
                }
              },
            ),
        ],
      ),
      body: _error != null && _data == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(_error!),
              ),
            )
          : Column(
              children: [
                if (_events != null && _events!.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Row(
                      children: [
                        Icon(Icons.archive_outlined, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'আগের সেশনের প্রকাশিত ফল, মার্কশিট ও কার্যক্রমের রেকর্ড',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_events != null && _events!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedEventId,
                      decoration: const InputDecoration(
                        labelText: 'সেশন / শ্রেণি / পরীক্ষা নির্বাচন করুন',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final ev in _events!)
                          DropdownMenuItem(
                            value: ev['id'].toString(),
                            child: Text(
                              '${ev['session_name'] ?? ev['year'] ?? ''} • '
                              '${ev['result_class_name'] ?? ''} '
                              '${ev['result_section'] ?? ''} • ${ev['name'] ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        setState(() => _selectedEventId = v);
                        _loadMarksheet();
                      },
                    ),
                  ),
                Expanded(
                  child: _loadingMarksheet
                      ? const Center(child: CircularProgressIndicator())
                      : _data == null
                      ? const Center(
                          child: Text('নির্বাচন করার মতো পরীক্ষা নেই'),
                        )
                      : _buildMarksheet(),
                ),
              ],
            ),
    );
  }

  Widget _buildMarksheet() {
    final student = _data!['student'] ?? {};
    final event = _data!['event'] ?? {};
    final result = _data!['result'] ?? {};
    final promotion = _data!['promotion'];
    final position = _data!['position'];
    final dual = _data!['dual_position'];
    final attendance = _data!['attendance'];
    final hidden = _data!['marksheet_hidden'] == true;
    final activities = _data!['activities'] is Map
        ? _data!['activities'] as Map
        : const {};
    // Q9 dual merit: section position AND combined class position.
    final secPos = dual?['section'];
    final combPos = dual?['combined'];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.school, color: Colors.indigo),
            title: Text(student['name']?.toString() ?? ''),
            subtitle: Text(
              '${event['result_class_name'] ?? student['class_name'] ?? ''} '
              '(${event['result_section'] ?? student['section'] ?? ''}) • '
              'Roll ${event['result_roll'] ?? student['roll'] ?? promotion?['promoted_roll'] ?? ''}\n'
              '${event['session_name'] ?? event['year'] ?? ''} • ${event['name'] ?? ''}',
            ),
            isThreeLine: true,
          ),
        ),
        if (hidden)
          Card(
            color: Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline, color: Colors.orange),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'এই ফলাফলের বিস্তারিত মার্কশিট এখনো প্রকাশ করা হয়নি। শুধু ফলাফল দেখা যাবে।',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Interactive Result Card summary: GPA + rank + attendance.
        Card(
          color: Colors.indigo.shade50,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ফাইনাল GPA',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    Text(
                      result['final_gpa']?.toString() ?? (hidden ? '--' : '--'),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 26,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.emoji_events,
                          size: 16,
                          color: Colors.amber,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          (combPos != null || secPos != null)
                              ? 'মেধা: ${secPos ?? '-'} / ${dual['section_of'] ?? '-'} (নিজ শাখা) • ${combPos ?? '-'} / ${dual['combined_of'] ?? '-'} (সব শাখা)'
                              : (position != null
                                    ? 'মেধা স্থান: ${position['rank']}/${position['of']}'
                                    : 'মেধা স্থান: —'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_month,
                          size: 16,
                          color: Colors.indigo,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          attendance != null && attendance['percentage'] != null
                              ? 'উপস্থিতি: ${attendance['percentage']}% (${attendance['present_days']}/${attendance['total_days']})'
                              : 'উপস্থিতি: —',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (promotion != null) ...[
          const SizedBox(height: 8),
          Card(
            color: promotion['promoted'] == true
                ? ((promotion['conditional'] == true)
                      ? Colors.amber.shade50
                      : Colors.green.shade50)
                : Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    promotion['promoted'] == true
                        ? ((promotion['conditional'] == true)
                              ? Icons.warning_amber
                              : Icons.celebration)
                        : Icons.info_outline,
                    color: promotion['promoted'] == true
                        ? ((promotion['conditional'] == true)
                              ? Colors.amber.shade900
                              : Colors.green.shade800)
                        : Colors.orange.shade900,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (promotion['status_bn']?.toString() ?? '').isEmpty
                              ? 'উত্তীর্ণ'
                              : promotion['status_bn'].toString(),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: promotion['promoted'] == true
                                ? ((promotion['conditional'] == true)
                                      ? Colors.amber.shade900
                                      : Colors.green.shade800)
                                : Colors.orange.shade900,
                          ),
                        ),
                        if (promotion['promoted'] == true &&
                            promotion['promoted_roll'] != null)
                          Text(
                            '${promotion['to_class'] ?? 'SSC Batch'} — নতুন রোল: ${promotion['promoted_roll']}${promotion['passing_year'] != null ? ' • SSC ${promotion['passing_year']}' : ''}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.green.shade800,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        if (!hidden) ...[
          for (final f in _families ?? [])
            Builder(
              builder: (_) {
                final hi = (_data!['subject_highest'] is Map)
                    ? (_data!['subject_highest']
                          as Map)[f['subject']?.toString() ?? '']
                    : null;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                f['subject']?.toString() ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if ((f['papers'] ?? []).length > 1)
                                Text(
                                  (f['papers'] as List).join(', '),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              if (hi != null)
                                Text(
                                  '🏆 Class highest: $hi',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.amber.shade800,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${f['total'] ?? 0}/${f['full'] ?? 0}  (${f['scaled'] ?? 0}%)',
                            ),
                            Text(
                              '${f['letter_grade'] ?? ''} — ${f['grade_point'] ?? 0.0}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color:
                                    f['letter_grade'] == 'F' ||
                                        f['letter_grade'] == 'Absent'
                                    ? Colors.red
                                    : Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text('ফলাফল', style: TextStyle(color: Colors.grey)),
                      const Spacer(),
                      Text(
                        result['result_status']?.toString() ?? '',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: result['result_status'] == 'PASSED'
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Text(
                        'ফাইনাল GPA',
                        style: TextStyle(color: Colors.grey),
                      ),
                      const Spacer(),
                      Text(
                        result['final_gpa']?.toString() ?? '--',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        if ((_data!['remarks'] ?? '') != '')
          Card(
            child: ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: const Text('শিক্ষকের মন্তব্য'),
              subtitle: Text('${_data!['remarks']}'),
            ),
          ),
        Card(
          child: ExpansionTile(
            leading: const Icon(Icons.timeline),
            title: const Text('এই সেশনের কার্যক্রম'),
            subtitle: Text(
              '${activities['from'] ?? ''} – ${activities['to'] ?? ''}',
            ),
            children: [
              for (final entry in [
                ['উপস্থিতি', 'attendance'],
                ['দৈনিক অগ্রগতি', 'daily_reports'],
                ['শ্রেণি পরীক্ষা', 'class_tests'],
                ['বাড়ির কাজ', 'homework'],
              ])
                if (activities[entry[1]] is List)
                  for (final item in (activities[entry[1]] as List).take(12))
                    if (item is Map)
                      ListTile(
                        dense: true,
                        title: Text(
                          '${item['subject_name'] ?? item['exam_name'] ?? item['title'] ?? entry[0]}',
                        ),
                        subtitle: Text(
                          '${item['date'] ?? item['report_date'] ?? item['due_date'] ?? ''} • ${item['final_state'] ?? item['status'] ?? item['learning_status'] ?? item['marks'] ?? ''}',
                        ),
                      ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            icon: const Icon(Icons.description_outlined),
            label: Text(
              hidden
                  ? 'ফলাফল ও কার্যক্রমের PDF দেখুন'
                  : 'Result Card দেখুন (PDF ডাউনলোড সহ)',
            ),
            onPressed: _showResultCard,
          ),
        ),
      ],
    );
  }

  Future<void> _showResultCard() async {
    if (_data == null) return;
    final student = _data!['student'] ?? {};
    final event = _data!['event'] ?? {};
    final result = _data!['result'] ?? {};
    final settings = _data!['settings'] ?? {};
    final promotion = _data!['promotion'];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        maxChildSize: 0.95,
        builder: (ctx, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              settings['school_name'] ?? 'Nazirhat Collegiate High School',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              settings['school_address'] ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const Divider(height: 18),
            Text(
              'Result Card — ${event['name'] ?? ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            if (promotion != null)
              Card(
                color: promotion['promoted'] == true
                    ? Colors.green.shade50
                    : Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Column(
                    children: [
                      Text(
                        (promotion['status_bn']?.toString() ?? '').isEmpty
                            ? '\u0989\u09A4\u09CD\u09A4\u09C0\u09B0\u09CD\u09A3'
                            : promotion['status_bn'].toString(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: promotion['promoted'] == true
                              ? Colors.green.shade800
                              : Colors.orange.shade900,
                        ),
                      ),
                      if (promotion['promoted'] == true &&
                          promotion['promoted_roll'] != null)
                        Text(
                          'SSC Batch — নতুন রোল: ${promotion['promoted_roll']}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.green.shade800,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    _rc('নাম', '${student['name'] ?? ''}'),
                    _rc(
                      'শ্রেণি',
                      '${student['class_name'] ?? ''} (${student['section'] ?? ''})',
                    ),
                    _rc('রোল', '${student['roll'] ?? ''}'),
                    _rc('পরীক্ষা', '${event['name'] ?? ''}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Table(
                  columnWidths: const {
                    0: FlexColumnWidth(3),
                    1: FlexColumnWidth(1.4),
                    2: FlexColumnWidth(1.6),
                    3: FlexColumnWidth(1.4),
                  },
                  border: TableBorder.all(color: Colors.grey.shade300),
                  children: [
                    for (final row in [
                      ['বিষয়', 'নম্বর', 'গ্রেড', 'GPA'],
                      for (final f in _families ?? [])
                        [
                          f['subject']?.toString() ?? '',
                          '${f['total'] ?? 0}/${f['full'] ?? 0}',
                          f['letter_grade']?.toString() ?? '',
                          f['grade_point']?.toString() ?? '',
                        ],
                    ])
                      TableRow(
                        decoration: row[0] == 'বিষয়'
                            ? BoxDecoration(color: Colors.indigo.shade50)
                            : null,
                        children: [
                          for (final c in row)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 5,
                              ),
                              child: Text(
                                c,
                                style: TextStyle(
                                  fontWeight: row[0] == 'বিষয়'
                                      ? FontWeight.bold
                                      : null,
                                  fontSize: 12.5,
                                  color: row[0] == 'বিষয়'
                                      ? Colors.indigo.shade800
                                      : null,
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text(
                          'ফলাফল',
                          style: TextStyle(color: Colors.grey),
                        ),
                        const Spacer(),
                        Text(
                          result['result_status']?.toString() ?? '',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: result['result_status'] == 'PASSED'
                                ? Colors.green
                                : Colors.red,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Text(
                          'ফাইনাল GPA',
                          style: TextStyle(color: Colors.grey),
                        ),
                        const Spacer(),
                        Text(
                          result['final_gpa']?.toString() ?? '--',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if ((_data!['remarks'] ?? '') != '')
              Card(
                child: ListTile(
                  leading: const Icon(Icons.chat_outlined),
                  title: const Text('শিক্ষকের মন্তব্য'),
                  subtitle: Text('${_data!['remarks']}'),
                ),
              ),
            const SizedBox(height: 6),
            FilledButton.icon(
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('PDF ডাউনলোড / শেয়ার করুন'),
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await _downloadPdf();
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('PDF error: $e')));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _rc(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(k, style: const TextStyle(color: Colors.grey)),
        ),
        Expanded(
          child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}
