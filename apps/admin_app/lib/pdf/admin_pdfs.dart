import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'app_pdf.dart';
import 'marksheet_template.dart';

/// PDFs rendered **on the phone** from JSON the admin app already has.
///
/// The previous build opened server URLs (`/results/class-pdf`,
/// `/guardian/student/:id/result-card.pdf`) in a browser. Those need a working
/// network AND a reachable server; both fail on mobile carriers. Everything is
/// now built locally from the tabulation / marksheet JSON.
class AdminPdfs {
  AdminPdfs._();

  static String _s(dynamic v) => v == null ? '' : v.toString();
  static Map _asMap(dynamic v) => v is Map ? v : const {};
  static List _asList(dynamic v) => v is List ? v : const [];

  static String _school(Map settings) =>
      _s(settings['school_name'] ?? settings['school'] ?? 'School');
  static String _addr(Map settings) =>
      _s(settings['school_address'] ?? settings['address'] ?? '');

  static Future<Uint8List> teacherRoster(
    List<Map> teachers, {
    required Map settings,
  }) async {
    final bn = await AppPdf.banglaFont();
    final active = teachers
        .where((teacher) => teacher['active'] == true || teacher['active'] == 1)
        .toList();
    final doc = pw.Document();
    pw.Widget cell(
      String text, {
      bool bold = false,
      pw.Alignment alignment = pw.Alignment.centerLeft,
    }) => pw.Container(
      height: 34,
      alignment: alignment,
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: pw.Text(
        text,
        maxLines: 2,
        style: AppPdf.bn(bn, size: 8, weight: bold ? pw.FontWeight.bold : null),
      ),
    );
    doc.addPage(
      pw.MultiPage(
        pageTheme: AppPdf.paperTheme(
          margin: 28,
          pageFormat: PdfPageFormat.a4.landscape,
        ),
        header: (_) => AppPdf.header(
          bn,
          _school(settings),
          _addr(settings),
          title: 'শিক্ষক তথ্য ও স্বাক্ষর তালিকা',
          subtitle:
              'EIIN: ${_s(settings['school_eiin']).trim().isEmpty ? '104417' : settings['school_eiin']}   •   প্রতিষ্ঠিত: ১৯৫৪',
        ),
        build: (_) => [
          pw.SizedBox(height: 10),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey700, width: .6),
            columnWidths: {
              0: const pw.FixedColumnWidth(28),
              1: const pw.FlexColumnWidth(2.1),
              2: const pw.FlexColumnWidth(1.6),
              3: const pw.FlexColumnWidth(1.25),
              4: const pw.FlexColumnWidth(1.3),
              5: const pw.FlexColumnWidth(1.8),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.indigo800),
                children: [
                  cell('নং', bold: true, alignment: pw.Alignment.center),
                  cell('শিক্ষকের নাম', bold: true),
                  cell('ডিগ্রি', bold: true),
                  cell('ফোন নম্বর', bold: true),
                  cell('স্বাক্ষর', bold: true),
                  cell('মন্তব্য', bold: true),
                ],
              ),
              for (var i = 0; i < active.length; i++)
                pw.TableRow(
                  children: [
                    cell('${i + 1}', alignment: pw.Alignment.center),
                    cell(_s(active[i]['name'])),
                    cell(_s(active[i]['teacher_degree'])),
                    cell(_s(active[i]['phone'])),
                    cell(''),
                    cell(''),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 42),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Column(
                  children: [
                    pw.Container(width: 190, height: 1, color: PdfColors.black),
                    pw.SizedBox(height: 5),
                    pw.Text(
                      'প্রধান শিক্ষক',
                      style: AppPdf.bn(bn, size: 9, weight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              ),
              pw.Expanded(
                child: pw.Column(
                  children: [
                    pw.Container(width: 190, height: 1, color: PdfColors.black),
                    pw.SizedBox(height: 5),
                    pw.Text(
                      'সহকারী প্রধান শিক্ষক',
                      style: AppPdf.bn(bn, size: 9, weight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return doc.save();
  }

  static String _clsLabel(Map cls) {
    final base = _s(cls['name']);
    final extra = _s(cls['group_name']).isNotEmpty
        ? _s(cls['group_name'])
        : _s(cls['section']);
    return extra.isEmpty ? base : '$base ($extra)';
  }

  static String _date(dynamic v) {
    final d = _s(v);
    return d.length >= 10 ? d.substring(0, 10) : d;
  }

  // ------------------------------------------------------------- ONE RESULT CARD
  /// `/results/marksheet/:studentId/:eventId` payload -> one-page result card.
  static Future<Uint8List> resultCard(Map data) async {
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

  // ------------------------------------------------- WHOLE-CLASS RESULT CARDS
  /// `/results/tabulation` payload + class/event/settings -> one A4 page per
  /// student, concatenated into a single PDF (same rule the server used: the
  /// class PDF is just N individual cards, so admin and guardian can never
  /// disagree about a child's result).
  static Future<Uint8List> classResultCards(
    Map tabulation, {
    required String eventName,
    Map? event,
    required Map cls,
    required Map settings,
    Map? signatures,
  }) async {
    final pw.Font bn = await AppPdf.banglaFont();
    final script = await MarksheetTemplate.loadScriptFont();
    final logo = await MarksheetTemplate.loadLogo();
    final watermark = await MarksheetTemplate.loadWatermark();
    final subjects = _asList(tabulation['subjects']).map(_s).toList();
    final rows = _asList(tabulation['rows']);
    final clsLabel = _clsLabel(cls);
    final doc = pw.Document();

    for (final rawRow in rows) {
      final row = _asMap(rawRow);
      final familyMap = _asMap(row['families']);
      final familyRows = <Map>[
        for (final subject in subjects)
          if (_asMap(familyMap[subject]).isNotEmpty)
            {..._asMap(familyMap[subject]), 'subject': subject},
      ];
      final student = <String, dynamic>{
        'name': row['name'],
        'roll': row['roll'],
        'student_code': row['student_code'],
        'birth_cert_no': row['birth_cert_no'],
        'father_name': row['father_name'],
        'mother_name': row['mother_name'],
        'dob': row['dob'],
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
      final positionText =
          row['section_position'] != null || row['combined_position'] != null
          ? 'Section ${_s(row['section_position'] ?? '-')}/${_s(row['section_of'] ?? '-')} | All sections ${_s(row['combined_position'] ?? '-')}/${_s(row['combined_of'] ?? '-')}'
          : _s(row['position']);
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
            eventName: '$eventName • $clsLabel',
            student: student,
            event: event ?? {'name': eventName},
            result: result,
            families: familyRows,
            positionText: positionText,
            classHighestGpa: _s(row['class_highest_gpa']),
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
            eventName: eventName,
            student: student,
            activities: _asMap(row['activities']),
            activityPeriod: _asMap(row['activity_period']),
          ),
        ),
      );
    }
    return doc.save();
  }

  /// Q14: Promoted/retained student list handed out by the school.
  static Future<Uint8List> promotedList(
    Map data, {
    required Map settings,
  }) async {
    final pw.Font bn = await AppPdf.banglaFont();
    final promoted = _asList(data['promoted']);
    final retained = _asList(data['retained']);
    final toCls = _asMap(data['to_class']);
    final destName = _s(toCls['name']);
    final clsName = _s(data['class_name']);
    final eventName = _s(data['event_name']);

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            AppPdf.header(
              bn,
              _school(settings),
              _addr(settings),
              title: 'উত্তীর্ণ শিক্ষার্থীর তালিকা / Promoted Student List',
              subtitle:
                  '$eventName  •  $clsName${destName.isNotEmpty ? ' → $destName' : ''}',
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'উত্তীর্ণ: ${promoted.length} জন    |    উত্তীর্ণ নয়: ${retained.length} জন',
              style: AppPdf.bn(bn, size: 10, weight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: ['ক্রম', 'রোল', 'নাম', 'মোট নম্বর', 'GPA', 'ফলাফল'],
              data: [
                for (var i = 0; i < promoted.length; i++)
                  [
                    '${i + 1}',
                    _s(_asMap(promoted[i])['old_roll']),
                    _s(_asMap(promoted[i])['name']),
                    _s(_asMap(promoted[i])['total_marks_obtained']),
                    _s(_asMap(promoted[i])['final_gpa']),
                    _s(_asMap(promoted[i])['status_bn']),
                  ],
              ],
              border: pw.TableBorder.all(),
              cellAlignment: pw.Alignment.centerLeft,
              headerStyle: AppPdf.bn(
                bn,
                size: 9,
                weight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.green800,
              ),
              cellStyle: AppPdf.bn(bn, size: 9),
              cellPadding: const pw.EdgeInsets.all(5),
            ),
            if (retained.isNotEmpty) ...[
              pw.SizedBox(height: 14),
              pw.Text(
                'উত্তীর্ণ নয় (Retained): ${retained.length} জন',
                style: AppPdf.bn(
                  bn,
                  size: 11,
                  weight: pw.FontWeight.bold,
                  color: PdfColors.red900,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.TableHelper.fromTextArray(
                headers: ['ক্রম', 'রোল', 'নাম', 'মোট নম্বর', 'GPA'],
                data: [
                  for (var i = 0; i < retained.length; i++)
                    [
                      '${i + 1}',
                      _s(_asMap(retained[i])['old_roll']),
                      _s(_asMap(retained[i])['name']),
                      _s(_asMap(retained[i])['total_marks_obtained']),
                      _s(_asMap(retained[i])['final_gpa']),
                    ],
                ],
                border: pw.TableBorder.all(),
                headerStyle: AppPdf.bn(
                  bn,
                  size: 9,
                  weight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.red800,
                ),
                cellStyle: AppPdf.bn(bn, size: 9),
                cellPadding: const pw.EdgeInsets.all(5),
              ),
            ],
            pw.Spacer(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('___________________', style: AppPdf.bn(bn, size: 9)),
                pw.Text('___________________', style: AppPdf.bn(bn, size: 9)),
              ],
            ),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'শ্রেণি শিক্ষকের স্বাক্ষর',
                  style: AppPdf.bn(bn, size: 8),
                ),
                pw.Text(
                  'প্রধান শিক্ষকের স্বাক্ষর',
                  style: AppPdf.bn(bn, size: 8),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  /// exam_date / result_date come back as ISO strings — show only the day part.
  static String eventDate(Map event, String key) => _date(event[key]);

  /// Promotion report — on-device PDF for the completed promotion run.
  ///
  /// The JSON comes from `/admin/promotion/report?session_id=X` and contains
  /// one row per student with from_class, target_class, status, decision, GPA.
  /// This mirrors the old server-side CSV export but renders a nice PDF on the
  /// phone so the admin can share it immediately.
  static Future<Uint8List> promotionReport(
    List<Map> rows, {
    required Map settings,
    required String sessionName,
  }) async {
    final pw.Font bn = await AppPdf.banglaFont();
    final promoted = rows
        .where(
          (r) =>
              (r['status'] == 'promoted' ||
              r['status'] == 'approved' ||
              r['decision'] == 'promoted'),
        )
        .toList();
    final retained = rows
        .where(
          (r) => (r['status'] == 'retained' || r['decision'] == 'retained'),
        )
        .toList();

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            AppPdf.header(
              bn,
              _school(settings),
              _addr(settings),
              title: 'প্রমোশন রিপোর্ট / Promotion Report',
              subtitle: 'সেশন: $sessionName',
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'উত্তীর্ণ: ${promoted.length} জন    |    উত্তীর্ণ নয়: ${retained.length} জন    |    মোট: ${rows.length} জন',
              style: AppPdf.bn(bn, size: 10, weight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            if (promoted.isNotEmpty) ...[
              pw.Text(
                'উত্তীর্ণ শিক্ষার্থীর তালিকা',
                style: AppPdf.bn(
                  bn,
                  size: 11,
                  weight: pw.FontWeight.bold,
                  color: PdfColors.green900,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.TableHelper.fromTextArray(
                headers: [
                  'ক্রম',
                  'রোল',
                  'নাম',
                  'শ্রেণি',
                  'গন্তব্য শ্রেণি',
                  'GPA',
                  'ফলাফল',
                ],
                data: [
                  for (var i = 0; i < promoted.length; i++)
                    [
                      '${i + 1}',
                      _s(_asMap(promoted[i])['roll']),
                      _s(_asMap(promoted[i])['name']),
                      _s(_asMap(promoted[i])['from_class_name']),
                      _s(_asMap(promoted[i])['target_class_name']),
                      _s(_asMap(promoted[i])['final_gpa']),
                      _s(_asMap(promoted[i])['status']),
                    ],
                ],
                border: pw.TableBorder.all(),
                cellAlignment: pw.Alignment.centerLeft,
                headerStyle: AppPdf.bn(
                  bn,
                  size: 9,
                  weight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.green800,
                ),
                cellStyle: AppPdf.bn(bn, size: 9),
                cellPadding: const pw.EdgeInsets.all(5),
              ),
            ],
            if (retained.isNotEmpty) ...[
              pw.SizedBox(height: 14),
              pw.Text(
                'উত্তীর্ণ নয় (Retained): ${retained.length} জন',
                style: AppPdf.bn(
                  bn,
                  size: 11,
                  weight: pw.FontWeight.bold,
                  color: PdfColors.red900,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.TableHelper.fromTextArray(
                headers: ['ক্রম', 'রোল', 'নাম', 'শ্রেণি', 'GPA', 'ফলাফল'],
                data: [
                  for (var i = 0; i < retained.length; i++)
                    [
                      '${i + 1}',
                      _s(_asMap(retained[i])['roll']),
                      _s(_asMap(retained[i])['name']),
                      _s(_asMap(retained[i])['from_class_name']),
                      _s(_asMap(retained[i])['final_gpa']),
                      _s(_asMap(retained[i])['status']),
                    ],
                ],
                border: pw.TableBorder.all(),
                headerStyle: AppPdf.bn(
                  bn,
                  size: 9,
                  weight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.red800,
                ),
                cellStyle: AppPdf.bn(bn, size: 9),
                cellPadding: const pw.EdgeInsets.all(5),
              ),
            ],
            pw.Spacer(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('___________________', style: AppPdf.bn(bn, size: 9)),
                pw.Text('___________________', style: AppPdf.bn(bn, size: 9)),
              ],
            ),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'শ্রেণি শিক্ষকের স্বাক্ষর',
                  style: AppPdf.bn(bn, size: 8),
                ),
                pw.Text(
                  'প্রধান শিক্ষকের স্বাক্ষর',
                  style: AppPdf.bn(bn, size: 8),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }
}
