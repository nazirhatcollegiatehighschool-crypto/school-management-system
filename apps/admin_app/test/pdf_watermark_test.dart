import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:admin_app/pdf/admin_pdfs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final output = File(
    '${Directory.current.parent.parent.path}${Platform.pathSeparator}.tmp${Platform.pathSeparator}pdf_review${Platform.pathSeparator}',
  );

  Future<void> savePdf(String name, List<int> bytes) async {
    final folder = Directory(output.path);
    await folder.create(recursive: true);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    await File('${folder.path}$name.pdf').writeAsBytes(bytes);
  }

  test(
    'admin roster and reports retain a watermark under their tables',
    () async {
      final settings = {
        'school_name': 'Demo Collegiate School',
        'school_address': 'Demo Road, Bangladesh',
      };
      await savePdf(
        'admin-roster',
        await AdminPdfs.teacherRoster([
          {
            'active': true,
            'name': 'Demo Teacher',
            'teacher_degree': 'MSc',
            'phone': '01700000000',
          },
        ], settings: settings),
      );
      await savePdf(
        'admin-promotion',
        await AdminPdfs.promotionReport(
          [
            {
              'status': 'promoted',
              'roll': 1,
              'name': 'Demo Student',
              'from_class_name': 'Six',
              'target_class_name': 'Seven',
              'final_gpa': 4.5,
            },
            {
              'status': 'retained',
              'roll': 2,
              'name': 'Demo Student Two',
              'from_class_name': 'Six',
              'final_gpa': 3.2,
            },
          ],
          settings: settings,
          sessionName: '2026',
        ),
      );
      await savePdf(
        'admin-marksheet',
        await AdminPdfs.resultCard({
          'school_name': settings['school_name'],
          'settings': settings,
          'student': {
            'name': 'Demo Student',
            'roll': 1,
            'student_code': 'DEMO0001',
            'class_name': 'Six',
            'section': 'A',
          },
          'event': {'name': 'Demo Term', 'year': 2026},
          'result': {
            'total_marks': 87,
            'total_full': 100,
            'final_gpa': 4.5,
            'result_status': 'passed',
            'families': [
              {
                'subject': 'Mathematics',
              'total': 87,
              'full': 100,
                'letter_grade': 'A+',
                'grade_point': 5.0,
              },
            ],
          },
        }),
      );
    },
  );
}
