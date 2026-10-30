import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'app_pdf.dart';
import 'marksheet_template.dart';
import '../nctb_grading.dart';

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

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static String _englishDate(dynamic value) {
    final raw = _s(value).trim();
    final date = DateTime.tryParse(raw);
    if (date == null) return raw;
    return '${date.day} ${_months[date.month - 1]} ${date.year}';
  }

  static String _numberText(dynamic value) {
    final n = num.tryParse(_s(value));
    if (n == null) return _s(value);
    return n == n.roundToDouble()
        ? '${n.toInt()}'
        : n
              .toStringAsFixed(2)
              .replaceFirst(RegExp(r'0+$'), '')
              .replaceFirst(RegExp(r'\.$'), '');
  }

  // ------------------------------------------------------ EXAM (SUBJECT) MARKSHEET
  /// `/teacher/exams/:id` payload -> whole-class marks sheet for ONE subject
  /// exam. The previous build pointed at `/teacher/exams/:id/marksheet.pdf`,
  /// a route that never existed, so this button always failed. It is now
  /// rendered entirely on the phone from the JSON this screen already loads.
  static Future<Uint8List> examMarksheet(Map data) async {
    final bn = await AppPdf.banglaFont();
    final logo = await MarksheetTemplate.loadLogo();
    final watermark = await MarksheetTemplate.loadWatermark();
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
    final components = _asList(structure['components'])
        .whereType<Map>()
        .toList();
    final fullMarks = num.tryParse(_s(exam['full_marks'])) ?? 100;
    final tableComponents = components.isNotEmpty
        ? components
        : [
            {'key': 'marks', 'label': 'Marks', 'full': fullMarks},
          ];
    String componentLabel(Map component) {
      final key = _s(component['key']).toLowerCase();
      final label = switch (key) {
        'cq' => 'CQ',
        'mcq' => 'MCQ',
        'practical' => 'Practical',
        'written' => 'Written',
        'ca' => 'CA',
        _ => _s(
          component['label'],
        ).replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim(),
      };
      final componentFull = component['full'] ?? component['full_marks'];
      return componentFull == null
          ? label
          : '$label / ${_numberText(componentFull)}';
    }

    num? totalFor(Map? mark) {
      if (mark == null) return null;
      final stored = num.tryParse(_s(mark['marks']));
      if (stored != null) return stored;
      final values = tableComponents
          .map((c) => num.tryParse(_s(mark[_s(c['key'])])))
          .whereType<num>()
          .toList();
      return values.isEmpty ? null : values.fold<num>(0, (a, b) => a + b);
    }

    final classTotals = <num>[];
    final studentRows = <List<String>>[];
    for (var index = 0; index < students.length; index++) {
      final student = _asMap(students[index]);
      final mark = byStudent[_s(student['id'])];
      final absent = _isAbsent(mark);
      final total = totalFor(mark);
      if (!absent && total != null) classTotals.add(total);
      final row = <String>[
        '${index + 1}',
        _s(student['roll']),
        _s(student['name']),
        for (final component in tableComponents)
          absent ? '—' : _cell(mark, _s(component['key'])),
        absent ? '—' : (total == null ? '—' : _numberText(total)),
        absent || total == null
            ? '—'
            : NctbGrade.fromMarks(total, fullMarks).letter,
        absent ? 'Absent' : (mark == null ? 'Not entered' : ''),
      ];
      studentRows.add(row);
    }
    final average = classTotals.isEmpty
        ? '—'
        : _numberText(classTotals.reduce((a, b) => a + b) / classTotals.length);
    final headers = <String>[
      'No.',
      'Roll',
      'Student Name',
      for (final component in tableComponents) componentLabel(component),
      'Total',
      'Grade',
      'Status',
    ];
    final entryStatus = _s(exam['entry_status']).toLowerCase();
    final statusLabel = switch (entryStatus) {
      'submitted' => 'Submitted',
      'approved' => 'Approved',
      'published' => 'Published',
      _ => 'Draft',
    };
    final examName = _s(exam['event_name']).isNotEmpty
        ? _s(exam['event_name'])
        : (_s(exam['name']).isNotEmpty
              ? _s(exam['name'])
              : _s(data['exam_name']));
    final academicSession = _s(exam['session_name']).isNotEmpty
        ? _s(exam['session_name'])
        : _s(exam['event_year']);
    final classSection = [
      _s(exam['class_name']),
      if (_s(exam['section']).isNotEmpty) _s(exam['section']),
      if (_s(exam['group_name']).isNotEmpty &&
          _s(exam['group_name']) != _s(exam['section']))
        _s(exam['group_name']),
    ].where((part) => part.isNotEmpty).join(' / ');
    final enteredCount = students
        .where((student) => byStudent.containsKey(_s(_asMap(student)['id'])))
        .length;
    final writer = _asMap(data['marks_entered_by']);
    final writerName = _s(writer['name']).isNotEmpty
        ? _s(writer['name'])
        : _s(data['teacher_name']);
    pw.MemoryImage? writerSignature;
    final signatureData = _s(writer['signature_base64']);
    if (signatureData.isNotEmpty) {
      try {
        writerSignature = pw.MemoryImage(base64Decode(signatureData));
      } catch (_) {}
    }
    pw.TextStyle englishStyle(
      double size, {
      bool bold = false,
      PdfColor color = PdfColors.black,
    }) => pw.TextStyle(
      font: bold ? pw.Font.helveticaBold() : pw.Font.helvetica(),
      fontFallback: [bn],
      fontSize: size,
      color: color,
    );
    pw.Widget meta(String label, String value) => pw.Expanded(
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 92,
            child: pw.Text('$label:', style: englishStyle(9)),
          ),
          pw.Expanded(
            child: pw.Text(
              value.isEmpty ? '—' : value,
              style: englishStyle(9, bold: true),
            ),
          ),
        ],
      ),
    );
    pw.Widget pageHeader() => pw.Column(
      children: [
        pw.Center(
          child: pw.Image(logo, width: 47, height: 47, fit: pw.BoxFit.contain),
        ),
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text(
            _school(settings).toUpperCase(),
            textAlign: pw.TextAlign.center,
            style: englishStyle(16, bold: true),
          ),
        ),
        if (_addr(settings).isNotEmpty)
          pw.Center(
            child: pw.Text(
              _addr(settings).toUpperCase(),
              textAlign: pw.TextAlign.center,
              style: englishStyle(8.5, color: PdfColors.grey700),
            ),
          ),
        pw.SizedBox(height: 3),
        pw.Center(
          child: pw.Text(
            'Subjectwise Marksheet',
            textAlign: pw.TextAlign.center,
            style: englishStyle(14, bold: true),
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Center(
          child: pw.Text(
            examName.toUpperCase(),
            textAlign: pw.TextAlign.center,
            style: englishStyle(11, bold: true),
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Container(height: .8, color: PdfColors.grey800),
        pw.SizedBox(height: 8),
        pw.Row(
          children: [
            meta('Class / Section', classSection),
            pw.SizedBox(width: 12),
            meta('Subject', _s(exam['subject_name'])),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Row(
          children: [
            meta('Academic Session', academicSession),
            pw.SizedBox(width: 12),
            meta('Full Marks', _numberText(fullMarks)),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Row(
          children: [
            meta('Exam Date', _englishDate(exam['exam_date'])),
            pw.SizedBox(width: 12),
            meta('Entry Status', statusLabel),
          ],
        ),
        pw.SizedBox(height: 8),
      ],
    );
    pw.Widget marksTable(
      List<List<String>> rows,
    ) => pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerHeight: 21,
      headerPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      cellHeight: 16,
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      border: pw.TableBorder.all(color: PdfColors.grey700, width: .5),
      headerStyle: englishStyle(7.7, bold: true),
      headerDecoration: const pw.BoxDecoration(
        color: PdfColor(.91, .91, .91, .88),
      ),
      cellStyle: englishStyle(8.2, color: PdfColors.grey900),
      cellAlignment: pw.Alignment.center,
      cellAlignments: {2: pw.Alignment.centerLeft},
      cellDecoration: (column, value, row) => pw.BoxDecoration(
        color: row.isOdd
            ? const PdfColor(.95, .95, .95, .70)
            : const PdfColor(1, 1, 1, .70),
      ),
      columnWidths: {
        0: const pw.FixedColumnWidth(24),
        1: const pw.FixedColumnWidth(35),
        2: const pw.FlexColumnWidth(3),
        for (var i = 0; i < tableComponents.length; i++)
          3 + i: const pw.FlexColumnWidth(1),
        3 + tableComponents.length: const pw.FixedColumnWidth(39),
        4 + tableComponents.length: const pw.FixedColumnWidth(35),
        5 + tableComponents.length: const pw.FixedColumnWidth(50),
      },
    );

    final doc = pw.Document();
    final pageCount = students.isEmpty ? 1 : (students.length / 35).ceil();
    for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
      final start = pageIndex * 35;
      final end = (start + 35).clamp(0, students.length).toInt();
      final pageRows = studentRows.sublist(start, end);
      final isLast = pageIndex == pageCount - 1;
      final statusFooter = statusLabel == 'Draft'
          ? 'DRAFT COPY'
          : '$statusLabel COPY';
      doc.addPage(
        pw.MultiPage(
          maxPages: 20,
          pageTheme: MarksheetTemplate.pageTheme(
            watermark: watermark,
            margin: 28,
            watermarkOpacity: .18,
            watermarkWidth: 500,
            watermarkHeight: 470,
          ),
          footer: isLast
              ? (context) => pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    pw.SizedBox(
                      width: 180,
                      child: pw.Column(
                        mainAxisSize: pw.MainAxisSize.min,
                        children: [
                          pw.SizedBox(
                            height: 24,
                            child: writerSignature == null
                                ? pw.SizedBox()
                                : pw.Image(
                                    writerSignature,
                                    width: 110,
                                    height: 24,
                                    fit: pw.BoxFit.contain,
                                  ),
                          ),
                          pw.Container(height: .7, color: PdfColors.grey800),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            writerName,
                            textAlign: pw.TextAlign.center,
                            style: englishStyle(8.5, bold: true),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : null,
          build: (_) => [
            pageHeader(),
            marksTable(pageRows),
            if (isLast) ...[
              pw.SizedBox(height: 8),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: pw.BoxDecoration(
                  color: const PdfColor(.93, .93, .93, .82),
                  border: pw.Border.all(color: PdfColors.grey700, width: .5),
                  borderRadius: pw.BorderRadius.circular(3),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Students: ${students.length}',
                      style: englishStyle(9, bold: true),
                    ),
                    pw.Text(
                      'Entered: $enteredCount / ${students.length}',
                      style: englishStyle(9, bold: true),
                    ),
                    pw.Text(
                      'Class Average: $average',
                      style: englishStyle(9, bold: true),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 7),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Generated on: ${_englishDate(DateTime.now().toIso8601String())}',
                    style: englishStyle(8.5, color: PdfColors.grey700),
                  ),
                  pw.Text(
                    statusFooter,
                    style: englishStyle(
                      9,
                      bold: true,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }
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
    final bn = await AppPdf.banglaFont();
    final script = await MarksheetTemplate.loadScriptFont();
    final logo = await MarksheetTemplate.loadLogo();
    final watermark = await MarksheetTemplate.loadWatermark();
    final student = _asMap(data['student']);
    final event = _asMap(data['event']);
    final result = _asMap(data['result']);
    final settings = _asMap(data['settings']);
    final signatures = _asMap(data['signatures']);
    final families = _asList(result['families']);
    final attendance = _attendanceLabel(data['attendance']);
    final position = _positionLabel(data['dual_position'], data['position']);

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
          schoolName: _school(settings),
          schoolAddress: _addr(settings),
          eventName: _s(event['name']),
          student: student,
          event: event,
          result: result,
          families: families,
          serialNo: _s(data['serial_no']),
          attendanceText: attendance,
          positionText: position,
          classHighestGpa: _s(data['class_highest_gpa']),
          remarks: _s(data['remarks']),
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
          schoolName: _school(settings),
          eventName: _s(event['name']),
          student: student,
          activities: _asMap(data['activities']),
          activityPeriod: _asMap(data['activity_period']),
        ),
      ),
    );
    return doc.save();
  }

  /// `/teacher/events/:id/result?class_id=...` payload -> one certificate-style
  /// marksheet per student. The endpoint already limits subject teachers to
  /// their assigned subjects; class teachers receive the full grading result.
  static Future<Uint8List> classResultCards(Map data) async {
    final bn = await AppPdf.banglaFont();
    final script = await MarksheetTemplate.loadScriptFont();
    final logo = await MarksheetTemplate.loadLogo();
    final watermark = await MarksheetTemplate.loadWatermark();
    final event = _asMap(data['event']);
    final cls = _asMap(data['class']);
    final settings = _asMap(data['settings']);
    final signatures = _asMap(data['signatures']);
    final subjects = _asList(data['subjects']);
    final rows = _asList(data['rows']);
    var highestGpa = double.negativeInfinity;
    for (final raw in rows) {
      final value = num.tryParse(_s(_asMap(raw)['final_gpa']));
      if (value != null && value > highestGpa) highestGpa = value.toDouble();
    }
    final classHighestGpa = highestGpa.isFinite
        ? highestGpa.toStringAsFixed(2)
        : '';
    final classLabel = [
      _s(cls['name']),
      _s(cls['group_name']).isNotEmpty
          ? _s(cls['group_name'])
          : _s(cls['section']),
    ].where((value) => value.isNotEmpty).join(' / ');

    final doc = pw.Document();
    for (final raw in rows) {
      final row = _asMap(raw);
      final familyMap = _asMap(row['families']);
      final families = <Map>[
        for (final subject in subjects)
          if (_asMap(familyMap[_s(subject)]).isNotEmpty)
            {..._asMap(familyMap[_s(subject)]), 'subject': _s(subject)},
      ];
      final student = <String, dynamic>{
        'name': row['name'],
        'roll': row['roll'],
        'student_code': row['student_code'],
        'father_name': row['father_name'],
        'mother_name': row['mother_name'],
        'dob': row['dob'],
        'birth_cert_no': row['birth_cert_no'],
        'class_name': cls['name'],
        'section': cls['section'],
        'group_name': cls['group_name'],
      };
      final result = <String, dynamic>{
        'result_status': row['result_status'],
        'final_gpa': row['final_gpa'],
        'total_marks': row['total_marks'],
        'total_full': row['total_full'],
        'total_gpa_without_4th': row['total_gpa_without_4th'],
      };
      final rank = row['position'] == null ? '' : '${row['position']}';
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
            schoolName: _school(settings),
            schoolAddress: _addr(settings),
            eventName: [
              _s(event['name']),
              if (classLabel.isNotEmpty) classLabel,
            ].where((part) => part.isNotEmpty).join(' | '),
            student: student,
            event: event,
            result: result,
            families: families,
            serialNo: _s(row['student_code']),
            positionText: rank,
            classHighestGpa: classHighestGpa,
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
            schoolName: _school(settings),
            eventName: _s(event['name']),
            student: student,
            activities: _asMap(row['activities']),
            activityPeriod: _asMap(row['activity_period']),
          ),
        ),
      );
    }
    return doc.save();
  }

  static String _attendanceLabel(dynamic raw) {
    if (raw is Map) {
      if (raw['percentage'] != null) {
        return '${_s(raw['percentage'])}% (${_s(raw['present_days'])}/${_s(raw['total_days'])} days)';
      }
      return '';
    }
    if (raw is! List) return '';
    var present = 0;
    var total = 0;
    for (final item in raw) {
      final row = _asMap(item);
      final count = int.tryParse(_s(row['c'] ?? row['cnt'])) ?? 0;
      total += count;
      if (_s(row['status']) == 'present') present = count;
    }
    return total == 0 ? '' : '$present / $total days';
  }

  static String _positionLabel(dynamic dual, dynamic fallback) {
    if (dual is Map && (dual['section'] != null || dual['combined'] != null)) {
      return 'Section ${_s(dual['section'] ?? '-')}/${_s(dual['section_of'] ?? '-')} | All sections ${_s(dual['combined'] ?? '-')}/${_s(dual['combined_of'] ?? '-')}';
    }
    if (fallback is Map) return '${_s(fallback['rank'])}/${_s(fallback['of'])}';
    return _s(fallback);
  }

  // ------------------------------------------------------------------ SEAT PLAN
  /// `/teacher/events/:id/seat-plan` payload -> individual 6×3.5 inch seat tickets.
  static Future<Uint8List> seatPlan(Map data) async {
    final pw.Font bn = await AppPdf.banglaFont();
    final event = _asMap(data['event']);
    final cls = _asMap(data['class']);
    final settings = _asMap(data['settings']);
    final rooms = _asList(data['rooms']);

    final doc = pw.Document();
    final ticketSize = PdfPageFormat(
      6 * PdfPageFormat.inch,
      3.5 * PdfPageFormat.inch,
    );
    for (final room in rooms) {
      final rm = _asMap(room);
      final seats = _asList(rm['seats']);
      for (var desk = 0; desk < seats.length; desk++) {
        final pair = _asList(seats[desk]);
        for (var side = 0; side < pair.length; side++) {
          if (pair[side] == null) continue;
          final seat = _asMap(pair[side]);
          doc.addPage(
            pw.Page(
              pageFormat: ticketSize,
              margin: const pw.EdgeInsets.all(18),
              build: (_) => pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey700, width: 1.2),
                ),
                padding: const pw.EdgeInsets.all(14),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Text(
                      _school(settings),
                      textAlign: pw.TextAlign.center,
                      style: AppPdf.bn(
                        bn,
                        size: 15,
                        weight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Seat Plan • ${_s(event['name'])}',
                      textAlign: pw.TextAlign.center,
                      style: AppPdf.bn(
                        bn,
                        size: 10,
                        weight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Divider(),
                    pw.Text(
                      _s(seat['name']),
                      textAlign: pw.TextAlign.center,
                      style: AppPdf.bn(
                        bn,
                        size: 18,
                        weight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 5),
                    pw.Text(
                      'Student ID: ${_s(seat['student_code'])}',
                      textAlign: pw.TextAlign.center,
                      style: AppPdf.bn(bn, size: 10),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'Class: ${_s(cls['name'])}  •  Roll: ${_s(seat['roll'])}',
                      textAlign: pw.TextAlign.center,
                      style: AppPdf.bn(bn, size: 11),
                    ),
                    pw.Text(
                      'Room: ${_s(rm['room'])}  •  Desk: ${desk + 1}  •  ${side == 0 ? 'Left' : 'Right'} seat',
                      textAlign: pw.TextAlign.center,
                      style: AppPdf.bn(bn, size: 11),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      }
    }
    return doc.save();
  }

  // ------------------------------------------------------------------ ADMIT CARDS
  /// `/teacher/events/:id/admit-cards` payload -> one A4 page per student.
  static Future<Uint8List> admitCards(Map data) async {
    final pw.Font bn = await AppPdf.banglaFont();
    final event = _asMap(data['event']);
    final cls = _asMap(data['class']);
    final settings = _asMap(data['settings']);
    final students = _asList(data['students']);
    final subjects = _asList(data['subjects']);
    final signatures = _asMap(data['signatures']);

    final clsLabel =
        '${_s(cls['name'])}'
        '${_s(cls['group_name']).isNotEmpty ? ' (${_s(cls['group_name'])})' : ' (${_s(cls['section'])})'}';

    pw.Widget card(Map s) {
      return pw.Container(
        height: 300,
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey800, width: 1.0),
          borderRadius: pw.BorderRadius.circular(2),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Text(
                _school(settings),
                style: pw.TextStyle(
                  font: pw.Font.timesBold(),
                  fontSize: 12,
                  color: PdfColors.black,
                ),
              ),
            ),
            if (_addr(settings).isNotEmpty)
              pw.Center(
                child: pw.Text(
                  _addr(settings),
                  style: AppPdf.bn(bn, size: 7.5, color: PdfColors.grey600),
                ),
              ),
            pw.Center(child: AppPdf.logoMark(width: 42)),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                'ADMIT CARD - ${_s(event['name'])}',
                style: AppPdf.bn(bn, size: 10, weight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 8),
            _kv(bn, 'Name', _s(s['name'])),
            _kv(bn, 'Student ID', _s(s['student_code'])),
            _kv(bn, 'Class', clsLabel),
            _kv(bn, 'Roll', _s(s['roll'])),
            _kv(
              bn,
              'DOB',
              _s(s['dob']).isEmpty
                  ? '-'
                  : _s(s['dob']).substring(0, _s(s['dob']).length.clamp(0, 10)),
            ),
            if (subjects.isNotEmpty) ...[
              pw.SizedBox(height: 6),
              pw.Text(
                'Subjects:',
                style: AppPdf.bn(
                  bn,
                  size: 8.5,
                  weight: pw.FontWeight.bold,
                  color: PdfColors.grey900,
                ),
              ),
              for (final sb in subjects.take(8))
                pw.Bullet(
                  text:
                      '${_s(_asMap(sb)['subject_name'])}'
                      '${_s(_asMap(sb)['exam_date']).isEmpty ? '' : '  (${_s(_asMap(sb)['exam_date']).substring(0, _s(_asMap(sb)['exam_date']).length.clamp(0, 10))})'}',
                  style: AppPdf.bn(bn, size: 7.5),
                ),
            ],
            pw.Spacer(),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                AppPdf.signatoryBlock(
                  bn,
                  signatures['class_teacher'] as Map?,
                  'শ্রেণি শিক্ষক',
                ),
                pw.SizedBox(width: 12),
                AppPdf.signatoryBlock(
                  bn,
                  signatures['head_teacher'] as Map?,
                  'প্রধান শিক্ষক',
                ),
              ],
            ),
          ],
        ),
      );
    }

    final doc = pw.Document();
    for (var i = 0; i < students.length; i++) {
      final a = _asMap(students[i]);
      doc.addPage(
        pw.Page(
          pageTheme: AppPdf.paperTheme(margin: 28),
          build: (_) => pw.Column(children: [card(a), pw.Spacer()]),
        ),
      );
    }
    return doc.save();
  }

  static pw.Widget _kv(pw.Font bn, String k, String v) {
    return pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$k: ',
            style: AppPdf.bn(bn, size: 9, weight: pw.FontWeight.bold),
          ),
          pw.TextSpan(text: v, style: AppPdf.bn(bn, size: 9)),
        ],
      ),
    );
  }
}
