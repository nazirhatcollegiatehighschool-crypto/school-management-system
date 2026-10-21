import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'app_pdf.dart';

/// PDFs rendered **on the phone** from JSON the teacher app already has.
/// No server PDF endpoint is involved, so a slow/blocked network never
/// prevents a teacher from printing a marksheet, seat plan or admit card.
class TeacherPdfs {
  TeacherPdfs._();

  static String _s(dynamic v) => v == null ? '' : v.toString();

  static Map _asMap(dynamic v) => v is Map ? v : const {};
  static List _asList(dynamic v) => v is List ? v : const [];

  static String _school(Map settings) =>
      _s(settings['school_name'] ?? settings['school'] ?? 'School');
  static String _addr(Map settings) =>
      _s(settings['school_address'] ?? settings['address'] ?? '');

  // ------------------------------------------------------ EXAM (SUBJECT) MARKSHEET
  /// `/teacher/exams/:id` payload -> whole-class marks sheet for ONE subject
  /// exam. The previous build pointed at `/teacher/exams/:id/marksheet.pdf`,
  /// a route that never existed, so this button always failed. It is now
  /// rendered entirely on the phone from the JSON this screen already loads.
  static Future<Uint8List> examMarksheet(Map data) async {
    final pw.Font bn = await AppPdf.banglaFont();
    final exam = _asMap(data['exam']);
    final settings = _asMap(data['settings']);
    final students = _asList(data['students']);
    final marks = _asList(data['marks']);

    final byStudent = <String, Map>{};
    for (final m in marks) {
      final mm = _asMap(m);
      byStudent[_s(mm['student_id'])] = mm;
    }

    final structure = _asMap(exam['mark_structure']);
    final components = _asList(structure['components']);
    final full = _s(exam['full_marks'] ?? 100);

    final headers = <String>['রোল', 'নাম'];
    for (final c in components) {
      headers.add(_s(_asMap(c)['label']));
    }
    headers.addAll(['মোট', 'অনুপস্থিত']);

    final rows = <List<String>>[
      headers,
      for (final s in students)
        [
          _s(_asMap(s)['roll']),
          _s(_asMap(s)['name']),
          for (final c in components)
            _cell(byStudent[_s(_asMap(s)['id'])], _s(_asMap(c)['key'])),
          _cell(byStudent[_s(_asMap(s)['id'])], 'total'),
          _isAbsent(byStudent[_s(_asMap(s)['id'])]) ? 'হ্যাঁ' : '',
        ],
    ];

    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (_) => [
        AppPdf.header(
          bn,
          _school(settings),
          _addr(settings),
          title: 'মার্কশিট / Marks Sheet',
          subtitle: '${_s(exam['subject_name'])}  •  ${_s(exam['class_name'] ?? '')}'
              '${_s(exam['section']).isNotEmpty ? ' (${_s(exam['section'])})' : ''}'
              '${_s(exam['group_name']).isNotEmpty ? ' (${_s(exam['group_name'])})' : ''}'
              '${_s(exam['name']).isNotEmpty ? '  •  ${_s(exam['name'])}' : ''}'
              '${full.isEmpty ? '' : '  •  পূর্ণমান $full'}',
        ),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          data: rows,
          border: pw.TableBorder.all(),
          headerStyle: AppPdf.bn(bn, size: 8.5, weight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
          cellStyle: AppPdf.bn(bn, size: 8.5),
          cellAlignment: pw.Alignment.center,
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          cellAlignments: {1: pw.Alignment.centerLeft},
        ),
        pw.SizedBox(height: 14),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('___________________', style: AppPdf.bn(bn, size: 9)),
          pw.Text('___________________', style: AppPdf.bn(bn, size: 9)),
        ]),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('বিষয় শিক্ষকের স্বাক্ষর', style: AppPdf.bn(bn, size: 8)),
          pw.Text('প্রধান শিক্ষকের স্বাক্ষর', style: AppPdf.bn(bn, size: 8)),
        ]),
      ],
    ));
    return doc.save();
  }

  static bool _isAbsent(Map? m) {
    if (m == null) return false;
    final v = m['absent'];
    return v == true || v == 1 || v == '1';
  }

  static String _cell(Map? m, String key) {
    if (m == null) return '';
    final v = m[key];
    if (v == null) return '';
    if (v is num) return v == v.roundToDouble() ? '${v.toInt()}' : '$v';
    return _s(v);
  }

  // ------------------------------------------------------------------ MARKSHEET
  /// `/results/marksheet/:studentId/:eventId` payload -> full marksheet PDF.
  static Future<Uint8List> marksheet(Map data) async {
    final pw.Font bn = await AppPdf.banglaFont();
    final student = _asMap(data['student']);
    final event = _asMap(data['event']);
    final result = _asMap(data['result']);
    final settings = _asMap(data['settings']);
    final families = _asList(result['families']);
    final attendance = _asList(data['attendance']);

    int attOf(String status) {
      for (final a in attendance) {
        final m = _asMap(a);
        if (_s(m['status']) == status) return int.tryParse(_s(m['c'] ?? m['cnt'])) ?? 0;
      }
      return 0;
    }

    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          AppPdf.header(
            bn,
            _school(settings),
            _addr(settings),
            title: 'মার্কশিট / Marks Sheet',
            subtitle: _s(event['name']),
          ),
          pw.SizedBox(height: 8),
          pw.Row(children: [
            pw.Expanded(child: _kv(bn, 'নাম / Name', _s(student['name']))),
            pw.Expanded(child: _kv(bn, 'রোল / Roll', _s(student['roll']))),
          ]),
          pw.Row(children: [
            pw.Expanded(child: _kv(bn, 'শ্রেণি / Class',
                '${_s(student['class_name'])} (${_s(student['section'])})')),
            pw.Expanded(child: _kv(bn, 'আইডি / ID', _s(student['student_code']))),
          ]),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: ['বিষয়', 'নম্বর', 'সর্বোচ্চ', 'গ্রেড', 'GPA'],
            data: [
              for (final f in families)
                [
                  _s(_asMap(f)['subject']),
                  '${_s(_asMap(f)['total'] ?? 0)}/${_s(_asMap(f)['full'] ?? 0)}',
                  _s(_asMap(f)['highest'] ?? '—'),
                  _s(_asMap(f)['letter_grade']),
                  _s(_asMap(f)['grade_point']),
                ],
            ],
            border: pw.TableBorder.all(),
            cellAlignment: pw.Alignment.centerLeft,
            headerStyle: AppPdf.bn(bn, size: 9, weight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
            cellStyle: AppPdf.bn(bn, size: 9),
            cellPadding: const pw.EdgeInsets.all(5),
          ),
          pw.SizedBox(height: 10),
          pw.Row(children: [
            pw.Expanded(child: _kv(bn, 'ফলাফল', _s(result['result_status']))),
            pw.Expanded(child: _kv(bn, 'GPA', _s(result['final_gpa']))),
            pw.Expanded(child: _kv(bn, 'মোট নম্বর',
                '${_s(result['total_marks'] ?? 0)}/${_s(result['total_full'] ?? 0)}')),
          ]),
          pw.SizedBox(height: 6),
          pw.Row(children: [
            pw.Expanded(
                child: _kv(bn, 'উপস্থিতি',
                    'P ${attOf('present')}  A ${attOf('absent')}  L ${attOf('late')}  Lv ${attOf('leave')}')),
            pw.Expanded(child: _kv(bn, 'সিরিয়াল', _s(data['serial_no']))),
          ]),
          if (_s(data['remarks']).isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text('শিক্ষকের মন্তব্য: ${_s(data['remarks'])}',
                  style: AppPdf.bn(bn, size: 9.5)),
            ),
          ],
          pw.Spacer(),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('___________________', style: AppPdf.bn(bn, size: 9)),
            pw.Text('___________________', style: AppPdf.bn(bn, size: 9)),
          ]),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('শিক্ষকের স্বাক্ষর', style: AppPdf.bn(bn, size: 8)),
            pw.Text('প্রধান শিক্ষকের স্বাক্ষর', style: AppPdf.bn(bn, size: 8)),
          ]),
        ],
      ),
    ));
    return doc.save();
  }

  // ------------------------------------------------------------------ SEAT PLAN
  /// `/teacher/events/:id/seat-plan` payload -> seat plan PDF.
  static Future<Uint8List> seatPlan(Map data) async {
    final pw.Font bn = await AppPdf.banglaFont();
    final event = _asMap(data['event']);
    final cls = _asMap(data['class']);
    final settings = _asMap(data['settings']);
    final rooms = _asList(data['rooms']);

    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (ctx) {
        final widgets = <pw.Widget>[
          AppPdf.header(
            bn,
            _school(settings),
            _addr(settings),
            title: 'Seat Plan — ${_s(event['name'])}',
            subtitle: '${_s(cls['name'])}'
                '${_s(cls['group_name']).isNotEmpty ? ' (${_s(cls['group_name'])})' : ' (${_s(cls['section'])})'}'
                '  •  মোট ${_s(data['total'])} জন',
          ),
          pw.SizedBox(height: 10),
        ];

        for (final r in rooms) {
          final rm = _asMap(r);
          final seats = _asList(rm['seats']);
          int count = 0;
          for (final s in seats) {
            final pair = _asList(s);
            count += pair.length;
          }
          widgets.add(pw.SizedBox(height: 6));
          widgets.add(pw.Text('${_s(rm['room'])} ($count students)',
              style: AppPdf.bn(bn, size: 11, weight: pw.FontWeight.bold, color: PdfColors.blue800)));
          widgets.add(pw.SizedBox(height: 4));

          final rows = <List<String>>[
            ['Desk', 'Left Seat', 'Right Seat'],
            for (var i = 0; i < seats.length; i++)
              [
                '${i + 1}',
                _seatLabel(_asList(seats[i]), 0),
                _seatLabel(_asList(seats[i]), 1),
              ],
          ];
          widgets.add(pw.TableHelper.fromTextArray(
            data: rows,
            border: pw.TableBorder.all(),
            headerStyle: AppPdf.bn(bn, size: 8.5, weight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue800),
            cellStyle: AppPdf.bn(bn, size: 8.5),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            cellAlignments: {0: pw.Alignment.center},
          ));
        }
        return widgets;
      },
    ));
    return doc.save();
  }

  static String _seatLabel(List pair, int i) {
    if (i >= pair.length || pair[i] == null) return '—';
    final s = _asMap(pair[i]);
    return '${_s(s['roll'])}. ${_s(s['name'])}';
  }

  // ------------------------------------------------------------------ ADMIT CARDS
  /// `/teacher/events/:id/admit-cards` payload -> admit cards PDF
  /// (2 cards per A4 page, bordered, with subject+date list).
  static Future<Uint8List> admitCards(Map data) async {
    final pw.Font bn = await AppPdf.banglaFont();
    final event = _asMap(data['event']);
    final cls = _asMap(data['class']);
    final settings = _asMap(data['settings']);
    final students = _asList(data['students']);
    final subjects = _asList(data['subjects']);

    final clsLabel = '${_s(cls['name'])}'
        '${_s(cls['group_name']).isNotEmpty ? ' (${_s(cls['group_name'])})' : ' (${_s(cls['section'])})'}';

    pw.Widget card(Map s) {
      return pw.Container(
        height: 300,
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.blue800, width: 1.2),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Center(
              child: pw.Text(_school(settings),
                  style: AppPdf.bn(bn, size: 12, weight: pw.FontWeight.bold, color: PdfColors.blue900))),
          if (_addr(settings).isNotEmpty)
            pw.Center(child: pw.Text(_addr(settings), style: AppPdf.bn(bn, size: 7.5, color: PdfColors.grey600))),
          pw.SizedBox(height: 4),
          pw.Center(
              child: pw.Text('ADMIT CARD — ${_s(event['name'])}',
                  style: AppPdf.bn(bn, size: 10, weight: pw.FontWeight.bold))),
          pw.SizedBox(height: 8),
          _kv(bn, 'Name', _s(s['name'])),
          _kv(bn, 'Student ID', _s(s['student_code'])),
          _kv(bn, 'Class', clsLabel),
          _kv(bn, 'Roll', _s(s['roll'])),
          _kv(bn, 'DOB', _s(s['dob']).isEmpty ? '-' : _s(s['dob']).substring(0, _s(s['dob']).length.clamp(0, 10))),
          if (subjects.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text('Subjects:', style: AppPdf.bn(bn, size: 8.5, weight: pw.FontWeight.bold, color: PdfColors.blue800)),
            for (final sb in subjects.take(8))
              pw.Bullet(
                  text: '${_s(_asMap(sb)['subject_name'])}'
                      '${_s(_asMap(sb)['exam_date']).isEmpty ? '' : '  (${_s(_asMap(sb)['exam_date']).substring(0, _s(_asMap(sb)['exam_date']).length.clamp(0, 10))})'}',
                  style: AppPdf.bn(bn, size: 7.5)),
          ],
          pw.Spacer(),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text("Guardian's Signature", style: AppPdf.bn(bn, size: 7.5)),
            pw.Text('Headmaster', style: AppPdf.bn(bn, size: 7.5)),
          ]),
        ]),
      );
    }

    final doc = pw.Document();
    for (var i = 0; i < students.length; i += 2) {
      final a = _asMap(students[i]);
      final b = i + 1 < students.length ? _asMap(students[i + 1]) : null;
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (_) => pw.Column(children: [
          card(a),
          pw.SizedBox(height: 12),
          if (b != null) card(b) else pw.Spacer(),
        ]),
      ));
    }
    return doc.save();
  }

  static pw.Widget _kv(pw.Font bn, String k, String v) {
    return pw.RichText(
      text: pw.TextSpan(children: [
        pw.TextSpan(text: '$k: ', style: AppPdf.bn(bn, size: 9, weight: pw.FontWeight.bold)),
        pw.TextSpan(text: v, style: AppPdf.bn(bn, size: 9)),
      ]),
    );
  }
}
