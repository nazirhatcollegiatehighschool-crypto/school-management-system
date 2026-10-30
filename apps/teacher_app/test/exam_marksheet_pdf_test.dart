import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_app/pdf/teacher_pdfs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'subject marksheet renders a class larger than one 35-student page',
    () async {
      final students = List.generate(
        36,
        (index) => {
          'id': index + 1,
          'roll': index + 1,
          'name': 'Student ${index + 1}',
        },
      );
      final marks = students
          .map(
            (student) => {
              'student_id': student['id'],
              'cq': 45,
              'mcq': 20,
              'marks': 65,
            },
          )
          .toList();

      final bytes = await TeacherPdfs.examMarksheet({
        'exam': {
          'event_name': 'Annual Examination 2026',
          'session_name': '2026',
          'class_name': 'Class 6',
          'section': 'A',
          'subject_name': 'Mathematics',
          'full_marks': 100,
          'entry_status': 'draft',
          'mark_structure': {
            'components': [
              {'key': 'cq', 'label': 'Creative', 'full': 70},
              {'key': 'mcq', 'label': 'MCQ', 'full': 30},
            ],
          },
        },
        'settings': {
          'school_name': 'Audit School',
          'school_address': 'Dhaka, Bangladesh',
        },
        'students': students,
        'marks': marks,
        'marks_entered_by': {'name': 'Audit Teacher'},
      });

      expect(bytes, isNotEmpty);
      final pageObjects = RegExp(r'/Type\s*/Page\b')
          .allMatches(latin1.decode(bytes, allowInvalid: true))
          .length;
      expect(pageObjects, 2);
      final outputPath = Platform.environment['AUDIT_PDF_OUTPUT'];
      if (outputPath != null && outputPath.isNotEmpty) {
        final output = File(outputPath);
        await output.parent.create(recursive: true);
        await output.writeAsBytes(bytes, flush: true);
      }
    },
  );

  test(
    'student result PDF paginates an extended daily activity history',
    () async {
      final activities = List.generate(
        150,
        (index) => {
          'report_date':
              '2026-01-${((index % 28) + 1).toString().padLeft(2, '0')}',
          'subject_name': 'Activity ${index + 1}',
          'learning_status': 'সম্পন্ন',
          'description': 'ACTIVITY-${(index + 1).toString().padLeft(3, '0')}',
        },
      );
      final bytes = await TeacherPdfs.marksheet({
        'student': {'id': 1, 'name': 'Audit Student', 'roll': 1},
        'event': {'name': 'Annual Examination 2026', 'year': 2026},
        'result': {'families': []},
        'settings': {
          'school_name': 'Audit School',
          'school_address': 'Dhaka, Bangladesh',
        },
        'signatures': {},
        'activities': {'daily_reports': activities},
        'activity_period': {'from': '2026-01-01', 'to': '2026-06-30'},
      });

      expect(bytes, isNotEmpty);
      final outputPath = Platform.environment['AUDIT_ACTIVITY_PDF_OUTPUT'];
      if (outputPath != null && outputPath.isNotEmpty) {
        final output = File(outputPath);
        await output.parent.create(recursive: true);
        await output.writeAsBytes(bytes, flush: true);
      }
    },
  );
}
