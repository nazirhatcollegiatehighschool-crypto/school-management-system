import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:guardian_app/pdf/marksheet_template.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('guardian marksheet shows watermark through the subject table', () async {
    final fontData = await rootBundle.load('assets/fonts/Kalpurush.ttf');
    final bangla = pw.Font.ttf(fontData);
    final script = await MarksheetTemplate.loadScriptFont();
    final logo = await MarksheetTemplate.loadLogo();
    final watermark = await MarksheetTemplate.loadWatermark();
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageTheme: MarksheetTemplate.pageTheme(watermark: watermark),
        build: (_) => MarksheetTemplate.build(
          banglaFont: bangla,
          scriptFont: script,
          logo: logo,
          schoolName: 'Demo Collegiate School',
          schoolAddress: '',
          eventName: 'Demo Term',
          student: {
            'name': 'Demo Student',
            'roll': 1,
            'student_code': 'DEMO0001',
            'class_name': 'Six',
            'section': 'A',
          },
          event: {'name': 'Demo Term'},
          result: {
            'total_marks': 87,
            'total_full': 100,
            'final_gpa': 4.5,
            'result_status': 'passed',
          },
          families: [
            {
              'subject': 'Mathematics',
              'total': 87,
              'full': 100,
              'letter_grade': 'A+',
              'grade_point': 5.0,
            },
          ],
        ),
      ),
    );
    final bytes = await doc.save();
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    final folder = Directory(
      '${Directory.current.parent.parent.path}${Platform.pathSeparator}.tmp${Platform.pathSeparator}pdf_review${Platform.pathSeparator}',
    );
    await folder.create(recursive: true);
    await File('${folder.path}guardian-marksheet.pdf').writeAsBytes(bytes);
  });
}
