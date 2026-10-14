// NCTB (Bangladesh) grading — shared, client-side, mirrors backend/grading.js.
// Percentage → letter grade → grade point. Used for real-time display while
// a teacher types marks; the server recomputes authoritative values.

class NctbGrade {
  final String letter;
  final double point;
  const NctbGrade(this.letter, this.point);

  static const _scale = <List<dynamic>>[
    [80, 'A+', 5.00],
    [70, 'A', 4.00],
    [60, 'A-', 3.50],
    [50, 'B', 3.00],
    [40, 'C', 2.00],
    [33, 'D', 1.00],
    [0, 'F', 0.00],
  ];

  /// Grade from a percentage (0-100).
  static NctbGrade fromPercent(num percent) {
    final p = percent.toDouble().clamp(0, 100);
    for (final row in _scale) {
      if (p >= (row[0] as num)) {
        return NctbGrade(row[1] as String, (row[2] as num).toDouble());
      }
    }
    return const NctbGrade('F', 0.0);
  }

  /// Grade from raw marks over a full-mark total.
  static NctbGrade fromMarks(num marks, num full) {
    final f = full <= 0 ? 100 : full.toDouble();
    return fromPercent(marks.toDouble() / f * 100);
  }
}
