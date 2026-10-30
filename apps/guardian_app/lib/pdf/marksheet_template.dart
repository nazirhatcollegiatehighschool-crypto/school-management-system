import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Certificate-style result sheet shared by the on-device PDF entry points.
class MarksheetTemplate {
  MarksheetTemplate._();

  static String _s(dynamic value) => value == null ? '' : value.toString();

  static bool _truthy(dynamic value) =>
      value == true || value == 1 || value == '1' || value == 'true';

  static String _marksValue(Map row) {
    if (_truthy(row['absent']) || _s(row['letter_grade']) == 'Absent') {
      return '-';
    }
    return '${_s(row['total'] ?? 0)} / ${_s(row['full'] ?? 0)}';
  }

  static String _date(dynamic value) {
    final raw = _s(value);
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
    return match == null
        ? raw
        : '${match.group(3)}/${match.group(2)}/${match.group(1)}';
  }

  static pw.Widget _patternedBorder() => pw.Positioned.fill(
    child: pw.CustomPaint(
      size: PdfPoint(PdfPageFormat.a4.width, PdfPageFormat.a4.height),
      painter: (canvas, size) {
        const band = 20.0;
        const mark = 5.0;
        const gap = 6.0;
        canvas.setStrokeColor(PdfColors.grey500);
        canvas.setLineWidth(0.25);
        for (var x = band; x < size.x - band; x += gap) {
          for (final y in [band, size.y - band - mark]) {
            canvas
              ..moveTo(x, y)
              ..lineTo(x + mark, y + mark)
              ..moveTo(x + mark, y)
              ..lineTo(x, y + mark);
          }
        }
        for (var y = band + mark; y < size.y - band - mark; y += gap) {
          for (final x in [band, size.x - band - mark]) {
            canvas
              ..moveTo(x, y)
              ..lineTo(x + mark, y + mark)
              ..moveTo(x + mark, y)
              ..lineTo(x, y + mark);
          }
        }
        canvas.strokePath();
      },
    ),
  );

  static Future<pw.MemoryImage> loadLogo() async {
    final data = await rootBundle.load('assets/school_logo.png');
    return pw.MemoryImage(data.buffer.asUint8List());
  }

  static Future<pw.MemoryImage> loadWatermark() async {
    final data = await rootBundle.load('assets/school-watermark.png');
    return pw.MemoryImage(data.buffer.asUint8List());
  }

  static Future<pw.Font> loadScriptFont() async {
    final data = await rootBundle.load('assets/fonts/MTCORSVA.TTF');
    return pw.Font.ttf(data);
  }

  static pw.PageTheme pageTheme({
    required pw.MemoryImage watermark,
    double margin = 32,
  }) => pw.PageTheme(
    pageFormat: PdfPageFormat.a4,
    margin: pw.EdgeInsets.all(margin),
    buildBackground: (_) => pw.FullPage(
      ignoreMargins: true,
      child: pw.Stack(
        children: [
          pw.Positioned.fill(child: pw.Container(color: PdfColors.white)),
          pw.Center(
            child: pw.Opacity(
              opacity: 0.10,
              child: pw.Image(
                watermark,
                width: 410,
                height: 370,
                fit: pw.BoxFit.contain,
              ),
            ),
          ),
          _patternedBorder(),
          pw.Positioned.fill(
            child: pw.Container(
              margin: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey800, width: 0.8),
              ),
              child: pw.Container(
                margin: const pw.EdgeInsets.all(4),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey600, width: 0.4),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  static List<pw.Widget> buildActivitiesPage({
    required pw.Font banglaFont,
    required String schoolName,
    required String eventName,
    required Map student,
    required Map activities,
    Map? activityPeriod,
  }) {
    final sections = <String, List>{
      'উপস্থিতি': activities['attendance'] is List
          ? activities['attendance'] as List
          : const [],
      'দৈনিক পড়া ও অগ্রগতি': activities['daily_reports'] is List
          ? activities['daily_reports'] as List
          : const [],
      'স্কুল ইউনিফর্ম — আনেনি ${activities['uniform_missing_count'] ?? 0} দিন':
          activities['uniform_reports'] is List
          ? activities['uniform_reports'] as List
          : const [],
      'অন্যান্য পরীক্ষা': activities['class_tests'] is List
          ? activities['class_tests'] as List
          : const [],
      'বাড়ির কাজ': activities['homework'] is List
          ? activities['homework'] as List
          : const [],
    };
    String value(Map row, List<String> keys) {
      for (final key in keys) {
        final v = row[key];
        if (v != null && '$v'.trim().isNotEmpty) return '$v';
      }
      return '—';
    }

    String display(String raw) => switch (raw) {
      'p5_stayed' => '৫ম পিরিয়ড পর্যন্ত ছিলেন',
      'early_departure_with_leave' => 'ছুটি নিয়ে প্রস্থান',
      'early_departure_no_leave' => 'ছুটি ছাড়া প্রস্থান',
      'present' => 'উপস্থিত',
      'absent' => 'অনুপস্থিত',
      'late' => 'দেরি',
      'leave' => 'ছুটি',
      _ => raw,
    };
    final rows = <pw.Widget>[
      pw.Center(
        child: pw.Text(
          schoolName,
          style: pw.TextStyle(
            font: banglaFont,
            fontSize: 17,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
      pw.SizedBox(height: 3),
      pw.Center(
        child: pw.Text(
          'শিক্ষার্থীর কার্যক্রম / Student Activity',
          style: pw.TextStyle(
            font: banglaFont,
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
      pw.Center(
        child: pw.Text(
          '${_s(student['name'])}  |  রোল ${_s(student['roll'])}  |  $eventName',
          style: pw.TextStyle(font: banglaFont, fontSize: 9),
        ),
      ),
      if ((activityPeriod?['from'] ?? activities['from']) != null)
        pw.Center(
          child: pw.Text(
            '${_date(activityPeriod?['from'] ?? activities['from'])} – ${_date(activityPeriod?['to'] ?? activities['to'])}',
            style: pw.TextStyle(
              font: banglaFont,
              fontSize: 8,
              color: PdfColors.grey700,
            ),
          ),
        ),
      pw.SizedBox(height: 10),
    ];
    for (final entry in sections.entries) {
      rows.add(
        pw.Text(
          '${entry.key} (${entry.value.length})',
          style: pw.TextStyle(
            font: banglaFont,
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      );
      rows.add(pw.SizedBox(height: 3));
      if (entry.value.isEmpty) {
        rows.add(
          pw.Text(
            'কোনো রেকর্ড নেই',
            style: pw.TextStyle(
              font: banglaFont,
              fontSize: 8,
              color: PdfColors.grey700,
            ),
          ),
        );
      } else {
        final selected = entry.value;
        rows.add(
          pw.TableHelper.fromTextArray(
            headers: const ['তারিখ', 'বিবরণ'],
            data: [
              for (final raw in selected)
                if (raw is Map)
                  [
                    value(raw, ['date', 'report_date', 'due_date']),
                    [
                      value(raw, [
                        'session',
                        'subject_name',
                        'exam_name',
                        'title',
                      ]),
                      display(
                        value(raw, [
                          'status',
                          'final_state',
                          'learning_status',
                          'performance',
                        ]),
                      ),
                      value(raw, ['homework_status', 'description', 'note']),
                    ].where((v) => v != '—').join(' · '),
                  ],
            ],
            headerStyle: pw.TextStyle(
              font: banglaFont,
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            ),
            cellStyle: pw.TextStyle(font: banglaFont, fontSize: 9),
            border: pw.TableBorder.all(color: PdfColors.grey400, width: .4),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 5,
              vertical: 4,
            ),
            columnWidths: {0: const pw.FixedColumnWidth(70)},
          ),
        );
      }
      rows.add(pw.SizedBox(height: 7));
    }
    return rows;
  }

  static pw.Widget build({
    required pw.Font banglaFont,
    required pw.Font scriptFont,
    required pw.MemoryImage logo,
    required String schoolName,
    required String schoolAddress,
    required String eventName,
    required Map student,
    required Map event,
    required Map result,
    required List families,
    String serialNo = '',
    String attendanceText = '',
    String positionText = '',
    String classHighestGpa = '',
    String remarks = '',
    String promotionText = '',
    Map? signatures,
  }) {
    final className = _s(student['class_name']);
    final groupName = _s(student['group_name']);
    final section = _s(student['section']);
    final classLabel = [
      className,
      if (groupName.isNotEmpty) groupName,
      if (section.isNotEmpty && section != groupName) section,
    ].where((v) => v.isNotEmpty).join(' / ');
    final rows = families.whereType<Map>().toList();
    final totalMarks = _s(result['total_marks']);
    final totalFull = _s(result['total_full']);
    final status = _s(result['result_status']);
    final finalGpa = _s(result['final_gpa']);
    final withoutFourth = _s(result['total_gpa_without_4th']);

    pw.TextStyle latin(double size, {bool bold = false, bool italic = false}) =>
        pw.TextStyle(
          font: italic
              ? pw.Font.timesItalic()
              : (bold ? pw.Font.timesBold() : pw.Font.times()),
          fontFallback: [banglaFont],
          fontSize: size,
          color: PdfColors.black,
        );

    pw.Widget field(String label, String value, {bool script = false}) =>
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(width: 76, child: pw.Text(label, style: latin(7.2))),
            pw.Text(': ', style: latin(8)),
            pw.Expanded(
              child: pw.Text(
                value.isEmpty ? '-' : value,
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
                style: script
                    ? pw.TextStyle(font: scriptFont, fontSize: 12)
                    : latin(9, italic: true),
              ),
            ),
          ],
        );

    final scale = <List<String>>[
      ['Letter Grade', 'Class Interval (%)', 'Grade Point'],
      ['A+', '80-100', '5.0'],
      ['A', '70-79', '4.0'],
      ['A-', '60-69', '3.5'],
      ['B', '50-59', '3.0'],
      ['C', '40-49', '2.0'],
      ['D', '33-39', '1.0'],
      ['F', '00-32', '0.0'],
    ];

    List<String> subjectRow(Map row, int index) => [
      '$index',
      _s(row['subject']),
      _marksValue(row),
      _s(row['letter_grade']),
      _s(row['grade_point']),
    ];
    final subjectRows = <List<String>>[];
    final optionalRows = <List<String>>[];
    for (var i = 0; i < rows.length; i++) {
      if (_truthy(rows[i]['is_optional'])) {
        optionalRows.add(subjectRow(rows[i], 0));
      } else {
        subjectRows.add(subjectRow(rows[i], subjectRows.length + 1));
      }
    }
    for (var i = 0; i < optionalRows.length; i++) {
      optionalRows[i][0] = '${subjectRows.length + i + 1}';
    }
    pw.Widget subjectsTable(List<List<String>> data) =>
        pw.TableHelper.fromTextArray(
          headers: const [
            'Sl. No.',
            'Name of Subjects',
            'Marks',
            'Letter Grade',
            'Grade Point',
          ],
          data: data,
          border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.5),
          cellAlignment: pw.Alignment.center,
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 3,
          ),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          headerStyle: AppFontStyle.bold(banglaFont, 7.2),
          cellStyle: pw.TextStyle(font: banglaFont, fontSize: 7.4),
          columnWidths: const {
            0: pw.FixedColumnWidth(31),
            1: pw.FlexColumnWidth(3.6),
            2: pw.FlexColumnWidth(1.3),
            3: pw.FlexColumnWidth(1.25),
            4: pw.FlexColumnWidth(1.15),
          },
        );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          schoolName.toUpperCase(),
          textAlign: pw.TextAlign.center,
          style: latin(15, bold: true),
        ),
        pw.Text(
          'ACADEMIC TRANSCRIPT  |  SCHOOL RESULT',
          textAlign: pw.TextAlign.center,
          style: latin(9.5, bold: true),
        ),
        if (schoolAddress.isNotEmpty)
          pw.Text(
            schoolAddress.toUpperCase(),
            textAlign: pw.TextAlign.center,
            style: latin(7, italic: true),
          ),
        pw.SizedBox(height: 5),
        pw.Center(
          child: pw.Container(
            width: 45,
            height: 45,
            padding: const pw.EdgeInsets.all(2),
            decoration: pw.BoxDecoration(
              shape: pw.BoxShape.circle,
              border: pw.Border.all(color: PdfColors.grey800, width: 0.8),
            ),
            child: pw.Image(logo, fit: pw.BoxFit.contain),
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          eventName.toUpperCase(),
          textAlign: pw.TextAlign.center,
          style: latin(9, bold: true),
        ),
        pw.SizedBox(height: 8),
        pw.Container(height: 0.7, color: PdfColors.black),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Text(
            'ACADEMIC MARKSHEET',
            textAlign: pw.TextAlign.center,
            style: latin(11, bold: true),
          ),
        ),
        pw.Container(height: 0.7, color: PdfColors.black),
        pw.SizedBox(height: 7),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Padding(
                padding: const pw.EdgeInsets.only(top: 6),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Serial No.   ${serialNo.isEmpty ? '-' : serialNo}',
                      style: latin(7.5),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      'Candidate Record No.   ${_s(student['student_code'])}',
                      style: latin(7.5),
                    ),
                  ],
                ),
              ),
            ),
            pw.SizedBox(
              width: 190,
              child: pw.TableHelper.fromTextArray(
                data: scale,
                border: pw.TableBorder.all(
                  color: PdfColors.grey700,
                  width: 0.45,
                ),
                cellAlignment: pw.Alignment.center,
                cellPadding: const pw.EdgeInsets.symmetric(
                  horizontal: 2,
                  vertical: 2,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                ),
                headerStyle: latin(5.4, bold: true),
                cellStyle: latin(6.2),
                columnWidths: const {
                  0: pw.FlexColumnWidth(0.8),
                  1: pw.FlexColumnWidth(1.1),
                  2: pw.FlexColumnWidth(0.8),
                },
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                children: [
                  field('Name of Student', _s(student['name']), script: true),
                  field(
                    "Father's Name",
                    _s(student['father_name']),
                    script: true,
                  ),
                  field(
                    "Mother's Name",
                    _s(student['mother_name']),
                    script: true,
                  ),
                  field('Name of Institution', schoolName),
                  field('Roll No.', _s(student['roll'])),
                  field('Group', groupName),
                  field('Class / Section', classLabel),
                ],
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: pw.Column(
                children: [
                  field(
                    'Birth Registration No.',
                    _s(student['birth_cert_no'] ?? student['registration_no']),
                  ),
                  field('Type', _s(student['student_type'])),
                  field('Date of Birth', _date(student['dob'])),
                  field(
                    'Academic Session',
                    _s(event['session_name'] ?? event['year'] ?? event['name']),
                  ),
                  field('Student ID', _s(student['student_code'])),
                  field('Attendance Record', attendanceText),
                  field('Merit Position', positionText),
                ],
              ),
            ),
          ],
        ),
        if (classHighestGpa.isNotEmpty)
          pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: field('Class Highest GPA', classHighestGpa),
          ),
        pw.SizedBox(height: 7),
        if (subjectRows.isNotEmpty) subjectsTable(subjectRows),
        if (optionalRows.isNotEmpty) ...[
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 3, bottom: 2),
            child: pw.Text('Optional Subject', style: latin(7, bold: true)),
          ),
          subjectsTable(optionalRows),
        ],
        pw.SizedBox(height: 7),
        pw.Container(
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            border: pw.Border.all(color: PdfColors.grey700, width: 0.5),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Result: ${status.isEmpty ? '-' : status}',
                style: latin(8, bold: true),
              ),
              pw.Text(
                'Total Marks: ${totalMarks.isEmpty ? '-' : totalMarks}/${totalFull.isEmpty ? '-' : totalFull}',
                style: latin(8, bold: true),
              ),
              if (withoutFourth.isNotEmpty)
                pw.Text(
                  'GPA (Without 4th): $withoutFourth',
                  style: latin(8, bold: true),
                ),
              pw.Text(
                'GPA (With 4th) - Final: ${finalGpa.isEmpty ? '-' : finalGpa}',
                style: latin(8, bold: true),
              ),
            ],
          ),
        ),
        if (promotionText.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Text(
              'Promotion: $promotionText',
              style: latin(8, italic: true),
            ),
          ),
        if (remarks.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 5),
            child: pw.Text(
              "Teacher's Remarks: $remarks",
              style: latin(8, italic: true),
            ),
          ),
        if (_s(event['result_date'] ?? event['published_at']).isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 5),
            child: pw.Text(
              'Date of Publication of Result: ${_date(event['result_date'] ?? event['published_at'])}',
              style: pw.TextStyle(font: scriptFont, fontSize: 10),
            ),
          ),
        pw.Spacer(),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            _signature(
              banglaFont,
              signatures?['class_teacher'],
              'Class Teacher',
            ),
            pw.SizedBox(width: 24),
            _signature(
              banglaFont,
              signatures?['head_teacher'],
              'Headmaster / Principal',
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _signature(pw.Font bn, dynamic signer, String fallback) {
    final data = signer is Map ? signer : const {};
    final name = _s(data['name']);
    final title = _s(data['designation']).isEmpty
        ? fallback
        : _s(data['designation']);
    pw.Widget? stamp;
    final encoded = _s(data['data_base64']);
    if (encoded.isNotEmpty) {
      try {
        stamp = pw.Image(
          pw.MemoryImage(base64Decode(encoded)),
          width: 95,
          height: 22,
          fit: pw.BoxFit.contain,
        );
      } catch (_) {}
    }
    return pw.Expanded(
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.SizedBox(height: 22, child: stamp ?? pw.SizedBox()),
          pw.Container(width: 110, height: 0.6, color: PdfColors.black),
          if (name.isNotEmpty)
            pw.Text(name, style: pw.TextStyle(font: bn, fontSize: 7)),
          pw.Text(
            title,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: bn, fontSize: 7),
          ),
        ],
      ),
    );
  }
}

class AppFontStyle {
  static pw.TextStyle bold(pw.Font font, double size) =>
      pw.TextStyle(font: font, fontSize: size, fontWeight: pw.FontWeight.bold);
}
