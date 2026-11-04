import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:teacher_app/pdf/teacher_pdfs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> savePdf(String name, List<int> bytes) async {
    final folder = Directory(
      '${Directory.current.parent.parent.path}${Platform.pathSeparator}.tmp${Platform.pathSeparator}pdf_review${Platform.pathSeparator}',
    );
    await folder.create(recursive: true);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    await File('${folder.path}$name.pdf').writeAsBytes(bytes);
  }

  test(
    'teacher marksheet and seat tickets include the school watermark',
    () async {
      await savePdf(
        'teacher-marksheet',
        await TeacherPdfs.examMarksheet({
          'exam': {
            'id': 91,
            'name': 'Demo Term',
            'event_name': 'Demo Term',
            'class_name': 'Six',
            'section': 'A',
            'subject_name': 'Mathematics',
            'full_marks': 100,
            'entry_status': 'submitted',
            'session_name': '2026',
          },
          'settings': {'school_name': 'Demo Collegiate School'},
          'teacher_name': 'Demo Teacher',
          'students': [
            {'id': 1, 'roll': 1, 'name': 'Demo Student'},
          ],
          'marks': [
            {'student_id': 1, 'marks': 87},
          ],
        }),
      );
      await savePdf(
        'teacher-seat-ticket',
        await TeacherPdfs.seatPlan({
          'event': {'name': 'Demo Term'},
          'class': {'name': 'Six', 'section': 'A'},
          'settings': {'school_name': 'Demo Collegiate School'},
          'rooms': [
            {
              'room': 'Room 1',
              'seats': [
                [
                  {
                    'name': 'Demo Student',
                    'student_code': 'DEMO0001',
                    'roll': 1,
                  },
                  null,
                ],
              ],
            },
          ],
        }),
      );
    },
  );
}
