import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardian_app/widgets/routine_view.dart';

void main() {
  testWidgets('shows the selected sibling class and teacher call action', (
    tester,
  ) async {
    const days = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];
    final routines = [
      {
        'student': {'id': 1, 'class_name': 'Class 2', 'section': 'A'},
        'routine': [
          for (final day in days)
            {
              'day_name': day,
              'start_time': '00:00',
              'end_time': '24:00',
              'slot_label': 'CLASS_1',
              'subject': {'name': 'বাংলা'},
              'teacher_name': 'প্রথম শিক্ষক',
              'teacher_phone': '01700000001',
            },
        ],
      },
      {
        'student': {'id': 2, 'class_name': 'Class 9', 'section': 'B'},
        'routine': [
          for (final day in days)
            {
              'day_name': day,
              'start_time': '00:00',
              'end_time': '24:00',
              'slot_label': 'CLASS_2',
              'subject': {'name': '$day গণিত'},
              'teacher_name': 'দ্বিতীয় শিক্ষক',
              'teacher_phone': '01700000002',
            },
        ],
      },
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CurrentClassBanner(routines: routines, studentId: 2),
        ),
      ),
    );

    final nowInBangladesh = DateTime.now().toUtc().add(
      const Duration(hours: 6),
    );
    final today = days[nowInBangladesh.weekday % 7];
    expect(find.text('চলমান ক্লাস • $today গণিত'), findsOneWidget);
    expect(find.textContaining('Class 9 B'), findsOneWidget);
    expect(find.text('শিক্ষক: দ্বিতীয় শিক্ষক'), findsOneWidget);
    expect(find.text('কল করুন'), findsOneWidget);
    expect(find.text('Class 2 A'), findsNothing);
  });
}
