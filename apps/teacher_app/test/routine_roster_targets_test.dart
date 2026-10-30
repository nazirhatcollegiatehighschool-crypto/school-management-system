import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_app/routine_roster_targets.dart';

void main() {
  test('routine roster targets preserve their exact sections and groups', () {
    final targets = routineRosterTargets({
      'sections': [
        {'class_id': '12', 'class_name': 'Class 8', 'section': 'A'},
        {'class_id': 4, 'class_name': 'Class 7', 'section': 'B'},
        {'class_id': '12', 'class_name': 'Class 8', 'section': 'A'},
        {'class_id': null, 'class_name': 'Invalid', 'section': 'X'},
      ],
      'groups': [
        {'class_id': 21, 'class_name': 'Class 10', 'group_name': 'Science'},
      ],
    });

    expect(targets.map((target) => (target.classId, target.label)).toList(), [
      (12, 'Class 8 (A)'),
      (4, 'Class 7 (B)'),
      (21, 'Class 10 (Science)'),
    ]);
  });

  test('missing routine targets return an empty list', () {
    expect(routineRosterTargets(null), isEmpty);
    expect(routineRosterTargets({'sections': 'invalid'}), isEmpty);
  });

  test('active routine ID resolves only its own class targets', () {
    final entries = [
      {
        'id': 10,
        'sections': [
          {'class_id': 1, 'class_name': 'Class 6', 'section': 'A'},
        ],
      },
      {
        'id': '11',
        'sections': [
          {'class_id': 2, 'class_name': 'Class 7', 'section': 'B'},
        ],
      },
    ];

    final activeEntry = routineEntryForId(entries, 11);

    expect(
      routineRosterTargets(activeEntry)
          .map((target) => target.classId)
          .toList(),
      [2],
    );
    expect(routineEntryForId(entries, 12), isNull);
  });
}
