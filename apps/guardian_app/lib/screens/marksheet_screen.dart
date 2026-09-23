import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../api.dart';

class MarksheetScreen extends StatefulWidget {
  final int studentId;
  final String studentName;
  const MarksheetScreen({super.key, required this.studentId, required this.studentName});
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
      final events = await Api.get('/guardian/student/${widget.studentId}/exam-events');
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
      final data = await Api.get('/guardian/student/${widget.studentId}/marksheet?event_id=$_selectedEventId');
      setState(() {
        _data = data;
        _families = data['result']?['families'] is List ? (data['result']!['families'] as List) : [];
        _error = null;
        _loadingMarksheet = false;
      });
    } catch (e) {
      setState(() { _error = friendlyError(e); _loadingMarksheet = false; });
    }
  }

  Future<void> _downloadPdf() async {
    if (_data == null) return;
    final doc = pw.Document();
    final student = _data!['student'] ?? {};
    final event = _data!['event'] ?? {};
    final result = _data!['result'] ?? {};
    final settings = _data!['settings'] ?? {};

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Center(child: pw.Text(settings['school_name'] ?? 'Nazirhat Collegiate High School',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
        pw.Center(child: pw.Text(settings['school_address'] ?? '')),
        pw.SizedBox(height: 6),
        pw.Divider(),
        pw.SizedBox(height: 4),
        pw.Center(child: pw.Text('Marksheet — ${event['name'] ?? ''}',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold))),
        pw.SizedBox(height: 8),
        pw.RichText(text: pw.TextSpan(
          children: [
            pw.TextSpan(text: 'Name: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.TextSpan(text: student['name']?.toString() ?? ''),
            pw.TextSpan(text: '   Class: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.TextSpan(text: '${student['class_name'] ?? ''} (${student['section'] ?? ''})'),
            pw.TextSpan(text: '   Roll: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.TextSpan(text: student['roll']?.toString() ?? ''),
          ],
        )),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: ['Subject', 'Total', 'Grade', 'GPA'],
          data: [
            for (final f in _families ?? [])
              [
                f['subject']?.toString() ?? '',
                f['total']?.toString() ?? '',
                f['letter_grade']?.toString() ?? '',
                f['grade_point']?.toString() ?? '',
              ],
          ],
          border: pw.TableBorder.all(),
          cellAlignment: pw.Alignment.centerLeft,
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: pw.BoxDecoration(color: PdfColors.blueGrey700),
          cellPadding: const pw.EdgeInsets.all(6),
        ),
        pw.SizedBox(height: 10),
        pw.RichText(text: pw.TextSpan(
          children: [
            pw.TextSpan(text: 'Result: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.TextSpan(text: result['result_status']?.toString() ?? ''),
            pw.TextSpan(text: '   GPA: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.TextSpan(text: result['final_gpa']?.toString() ?? ''),
          ],
        )),
        if ((_data!['remarks'] ?? '') != '')
          pw.Padding(padding: const pw.EdgeInsets.only(top: 8),
            child: pw.Text('Teacher Remarks: ${_data!['remarks']}')),
      ]),
    ));
    await Printing.sharePdf(bytes: await doc.save(), filename: 'marksheet_${event['name'] ?? 'exam'}.pdf');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Full Marksheet'),
        actions: [
          if (_data != null)
            IconButton(icon: const Icon(Icons.picture_as_pdf), tooltip: 'PDF',
                onPressed: () async {
                  try {
                    await _downloadPdf();
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF error: $e')));
                  }
                }),
        ],
      ),
      body: _error != null && _data == null
          ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!)))
          : Column(children: [
              if (_events != null && _events!.isNotEmpty)
                Padding(padding: const EdgeInsets.all(12),
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedEventId,
                    decoration: const InputDecoration(labelText: 'পরীক্ষা নির্বাচন করুন', border: OutlineInputBorder()),
                    items: [for (final ev in _events!) DropdownMenuItem(value: ev['id'].toString(), child: Text('${ev['name']}'))],
                    onChanged: (v) { setState(() => _selectedEventId = v); _loadMarksheet(); },
                  )),
              Expanded(child: _loadingMarksheet
                  ? const Center(child: CircularProgressIndicator())
                  : _data == null
                      ? const Center(child: Text('নির্বাচন করার মতো পরীক্ষা নেই'))
                      : _buildMarksheet()),
            ]),
    );
  }

  Widget _buildMarksheet() {
    final student = _data!['student'] ?? {};
    final event = _data!['event'] ?? {};
    final result = _data!['result'] ?? {};
    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(child: ListTile(
        leading: const Icon(Icons.school, color: Colors.indigo),
        title: Text(student['name']?.toString() ?? ''),
        subtitle: Text('${student['class_name'] ?? ''} (${student['section'] ?? ''}) • Roll ${student['roll'] ?? ''}\n${event['name'] ?? ''}'),
        isThreeLine: true,
      )),
      const SizedBox(height: 8),
      for (final f in _families ?? [])
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(f['subject']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
            if ((f['papers'] ?? []).length > 1)
              Text((f['papers'] as List).join(', '), style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${f['total'] ?? 0}/${f['full'] ?? 0}  (${f['scaled'] ?? 0}%)'),
            Text('${f['letter_grade'] ?? ''} — ${f['grade_point'] ?? 0.0}',
                style: TextStyle(fontWeight: FontWeight.bold,
                    color: f['letter_grade'] == 'F' || f['letter_grade'] == 'Absent'
                        ? Colors.red : Colors.green)),
          ]),
        ]))),
      const SizedBox(height: 8),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        Row(children: [
          const Text('ফলাফল', style: TextStyle(color: Colors.grey)),
          const Spacer(),
          Text(result['result_status']?.toString() ?? '',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16,
                  color: result['result_status'] == 'PASSED' ? Colors.green : Colors.red)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          const Text('ফাইনাল GPA', style: TextStyle(color: Colors.grey)),
          const Spacer(),
          Text(result['final_gpa']?.toString() ?? '--',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ]),
      ]))),
      if ((_data!['remarks'] ?? '') != '')
        Card(child: ListTile(
          leading: const Icon(Icons.chat_outlined),
          title: const Text('শিক্ষকের মন্তব্য'),
          subtitle: Text('${_data!['remarks']}'),
        )),
      const SizedBox(height: 8),
      Center(child: TextButton.icon(
        icon: const Icon(Icons.picture_as_pdf),
        label: const Text('PDF ডাউনলোড / শেয়ার করুন'),
        onPressed: () async {
          try {
            await _downloadPdf();
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF error: $e')));
          }
        },
      )),
    ]);
  }
}