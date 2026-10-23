import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'app_pdf.dart';

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
    final pw.Font bn = await AppPdf.banglaFont();
    final student = _asMap(data['student']);
    final event = _asMap(data['event']);
    final result = _asMap(data['result']);
    final settings = _asMap(data['settings']);
    final signatures = _asMap(data['signatures']);
    final families = _asList(result['families']);

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageTheme: AppPdf.paperTheme(margin: 40),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            AppPdf.header(
              bn,
              _school(settings),
              _addr(settings),
              title: 'ACADEMIC MARKSHEET',
              subtitle: _s(event['name']),
            ),
            pw.SizedBox(height: 10),
            _kv(bn, 'নাম / Name', _s(student['name'])),
            pw.Row(
              children: [
                pw.Expanded(
                  child: _kv(bn, 'শ্রেণি / Class', _clsLabel(student)),
                ),
                pw.Expanded(child: _kv(bn, 'রোল / Roll', _s(student['roll']))),
                pw.Expanded(
                  child: _kv(bn, 'আইডি / ID', _s(student['student_code'])),
                ),
              ],
            ),
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
              headerStyle: AppPdf.bn(
                bn,
                size: 9,
                weight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey700,
              ),
              cellStyle: AppPdf.bn(bn, size: 9),
              cellPadding: const pw.EdgeInsets.all(6),
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              children: [
                pw.Expanded(
                  child: _kv(bn, 'ফলাফল', _s(result['result_status'])),
                ),
                pw.Expanded(child: _kv(bn, 'GPA', _s(result['final_gpa']))),
                pw.Expanded(
                  child: _kv(
                    bn,
                    'মোট নম্বর',
                    '${_s(result['total_marks'] ?? 0)}/${_s(result['total_full'] ?? 0)}',
                  ),
                ),
              ],
            ),
            if (_s(data['class_highest_gpa']).isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 4),
                child: _kv(
                  bn,
                  'শ্রেণির সর্বোচ্চ GPA',
                  _s(data['class_highest_gpa']),
                ),
              ),
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
                child: pw.Text(
                  'শিক্ষকের মন্তব্য: ${_s(data['remarks'])}',
                  style: AppPdf.bn(bn, size: 9.5),
                ),
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
                pw.SizedBox(width: 24),
                AppPdf.signatoryBlock(
                  bn,
                  signatures['head_teacher'] as Map?,
                  'প্রধান শিক্ষক',
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  // ------------------------------------------------- WHOLE-CLASS RESULT CARDS
  /// `/results/tabulation` payload + class/event/settings -> one A4 page per
  /// student, concatenated into a single PDF (same rule the server used: the
  /// class PDF is just N individual cards, so admin and guardian can never
  /// disagree about a child's result).
  static Future<Uint8List> classResultCards(
    Map tabulation, {
    required String eventName,
    required Map cls,
    required Map settings,
    Map? signatures,
  }) async {
    final pw.Font bn = await AppPdf.banglaFont();
    final subjects = _asList(tabulation['subjects']).map(_s).toList();
    final rows = _asList(tabulation['rows']);
    final clsLabel = _clsLabel(cls);

    final doc = pw.Document();
    for (final r in rows) {
      final row = _asMap(r);
      final families = _asMap(row['families']);
      doc.addPage(
        pw.Page(
          pageTheme: AppPdf.paperTheme(margin: 40),
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              AppPdf.header(
                bn,
                _school(settings),
                _addr(settings),
                title: 'ACADEMIC MARKSHEET',
                subtitle: '$eventName  •  $clsLabel',
              ),
              pw.SizedBox(height: 10),
              _kv(bn, 'নাম / Name', _s(row['name'])),
              pw.Row(
                children: [
                  pw.Expanded(child: _kv(bn, 'শ্রেণি / Class', clsLabel)),
                  pw.Expanded(child: _kv(bn, 'রোল / Roll', _s(row['roll']))),
                  pw.Expanded(
                    child: _kv(bn, 'আইডি / ID', _s(row['student_code'])),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.TableHelper.fromTextArray(
                headers: ['বিষয়', 'নম্বর', 'সর্বোচ্চ', 'গ্রেড', 'GPA'],
                data: [
                  for (final sub in subjects)
                    [
                      sub,
                      (() {
                        final f = _asMap(families[sub]);
                        if (f.isEmpty) return '—';
                        return '${_s(f['total'] ?? 0)}/${_s(f['full'] ?? 0)}';
                      })(),
                      (() {
                        final f = _asMap(families[sub]);
                        return f.isEmpty ? '—' : _s(f['highest'] ?? '—');
                      })(),
                      _s(_asMap(families[sub])['letter_grade']),
                      _s(_asMap(families[sub])['grade_point']),
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
                  color: PdfColors.grey700,
                ),
                cellStyle: AppPdf.bn(bn, size: 9),
                cellPadding: const pw.EdgeInsets.all(6),
              ),
              pw.SizedBox(height: 10),
              pw.Row(
                children: [
                  pw.Expanded(
                    child: _kv(bn, 'ফলাফল', _s(row['result_status'])),
                  ),
                  pw.Expanded(child: _kv(bn, 'GPA', _s(row['final_gpa']))),
                  pw.Expanded(
                    child: _kv(
                      bn,
                      'মোট নম্বর',
                      '${_s(row['total_marks'] ?? 0)}/${_s(row['total_full'] ?? 0)}',
                    ),
                  ),
                ],
              ),
              if (_s(row['position']).isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 4),
                  child: _kv(bn, 'মেধা স্থান', _s(row['position'])),
                ),
              pw.Spacer(),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  AppPdf.signatoryBlock(
                    bn,
                    signatures?['class_teacher'] as Map?,
                    'শ্রেণি শিক্ষক',
                  ),
                  pw.SizedBox(width: 24),
                  AppPdf.signatoryBlock(
                    bn,
                    signatures?['head_teacher'] as Map?,
                    'প্রধান শিক্ষক',
                  ),
                ],
              ),
            ],
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
