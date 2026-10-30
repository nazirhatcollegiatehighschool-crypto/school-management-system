class RoutineRosterTarget {
  final int classId;
  final String label;

  const RoutineRosterTarget({required this.classId, required this.label});
}

Map? routineEntryForId(List entries, int? routineId) {
  if (routineId == null) return null;
  for (final entry in entries) {
    if (entry is Map && int.tryParse('${entry['id']}') == routineId) {
      return entry;
    }
  }
  return null;
}

List<RoutineRosterTarget> routineRosterTargets(Map? routine) {
  if (routine == null) return [];

  final targets = <RoutineRosterTarget>[];
  final seenClassIds = <int>{};

  void addTargets(dynamic values, String nameKey) {
    if (values is! List) return;
    for (final value in values) {
      if (value is! Map) continue;
      final classId = int.tryParse('${value['class_id'] ?? ''}');
      if (classId == null || !seenClassIds.add(classId)) continue;
      final className = '${value['class_name'] ?? ''}'.trim();
      final groupName = '${value[nameKey] ?? ''}'.trim();
      final label = [
        if (className.isNotEmpty) className else 'Class $classId',
        if (groupName.isNotEmpty) '($groupName)',
      ].join(' ');
      targets.add(RoutineRosterTarget(classId: classId, label: label));
    }
  }

  addTargets(routine['sections'], 'section');
  addTargets(routine['groups'], 'group_name');
  return targets;
}
