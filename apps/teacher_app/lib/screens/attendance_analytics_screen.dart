import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../api.dart';

class AttendanceAnalyticsScreen extends StatefulWidget {
  const AttendanceAnalyticsScreen({super.key});
  @override
  State<AttendanceAnalyticsScreen> createState() => _AttendanceAnalyticsScreenState();
}

class _AttendanceAnalyticsScreenState extends State<AttendanceAnalyticsScreen> {
  List _records = [];
  bool _loading = true;
  String? _error;
  List<DateTime> _days = [];
  Map<DateTime, Map<String, int>> _perDay = {};
  Map<String, int> _totals = {'present': 0, 'absent': 0, 'late': 0};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.get('/teacher/attendance');
      final rows = r is List ? r : [];
      final perDay = <DateTime, Map<String, int>>{};
      final totals = {'present': 0, 'absent': 0, 'late': 0};
      final days = <DateTime>[];
      for (final row in rows) {
        final status = row['status']?.toString() ?? '';
        if (!totals.containsKey(status)) continue;
        totals[status] = (totals[status] ?? 0) + 1;
        final dateStr = row['date']?.toString() ?? '';
        if (dateStr.length >= 10) {
          final d = DateTime.tryParse(dateStr.substring(0, 10));
          if (d != null) {
            final key = DateTime(d.year, d.month, d.day);
            (perDay[key] ??= {'present': 0, 'absent': 0, 'late': 0})[status] =
                (perDay[key]![status] ?? 0) + 1;
            if (!days.contains(key)) days.add(key);
          }
        }
      }
      days.sort();
      final recent = days.length > 10 ? days.sublist(days.length - 10) : days;
      setState(() {
        _records = rows;
        _perDay = perDay;
        _totals = totals;
        _days = recent;
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance Analytics'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _records.isEmpty
                  ? const Center(child: Text('এখনো কোনো attendance রেকর্ড নেই'))
                  : ListView(padding: const EdgeInsets.all(12), children: [
                      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
                        const Text('মোট রেকর্ড', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text(_records.length.toString(), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                      ]))),
                      const SizedBox(height: 8),
                      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
                        _legendRow(Colors.green, 'Present', _totals['present'] ?? 0),
                        _legendRow(Colors.red, 'Absent', _totals['absent'] ?? 0),
                        _legendRow(Colors.orange, 'Late', _totals['late'] ?? 0),
                        const Divider(),
                        const SizedBox(height: 8),
                        SizedBox(height: 240, child: BarChart(BarChartData(
                          maxY: _maxY(),
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          barTouchData: BarTouchData(touchTooltipData: BarTouchTooltipData(
                            getTooltipItem: (group, i, rod, rodIndex) {
                              final day = _days[group.x];
                              return BarTooltipItem(
                                  '${day.day}/${day.month}\n${rod.toY.toStringAsFixed(0)}',
                                  const TextStyle(color: Colors.white));
                            },
                          )),
                          titlesData: FlTitlesData(
                            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (v, meta) {
                                if (v.toInt() < 0 || v.toInt() >= _days.length) return const SizedBox.shrink();
                                final d = _days[v.toInt()];
                                return Padding(padding: const EdgeInsets.only(top: 6),
                                    child: Text('${d.day}/${d.month}', style: const TextStyle(fontSize: 10)));
                              },
                            )),
                          ),
                          barGroups: [
                            for (var i = 0; i < _days.length; i++)
                              BarChartGroupData(x: i, barRods: [
                                BarChartRodData(
                                  toY: (_perDay[_days[i]]?['present'] ?? 0).toDouble(),
                                  color: Colors.green,
                                  width: 8,
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                ),
                                BarChartRodData(
                                  toY: (_perDay[_days[i]]?['absent'] ?? 0).toDouble(),
                                  color: Colors.red,
                                  width: 8,
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                ),
                                BarChartRodData(
                                  toY: (_perDay[_days[i]]?['late'] ?? 0).toDouble(),
                                  color: Colors.orange,
                                  width: 8,
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                ),
                              ]),
                          ],
                        ))),
                        const SizedBox(height: 8),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const SonarDot(Colors.green), const SizedBox(width: 4), const Text('Present', style: TextStyle(fontSize: 10)),
                          const SizedBox(width: 12),
                          const SonarDot(Colors.red), const SizedBox(width: 4), const Text('Absent', style: TextStyle(fontSize: 10)),
                          const SizedBox(width: 12),
                          const SonarDot(Colors.orange), const SizedBox(width: 4), const Text('Late', style: TextStyle(fontSize: 10)),
                        ]),
                      ]))),
                      const SizedBox(height: 8),
                      const Text('সাম্প্রতিক রেকর্ড', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      for (final row in _records.take(20))
                        ListTile(
                          dense: true,
                          leading: Icon(Icons.circle, size: 12, color: _statusColor(row['status']?.toString() ?? '')),
                          title: Text('${row['student_name'] ?? ''} (${row['class_name'] ?? ''} ${row['section'] ?? ''})'),
                          trailing: Text((row['date']?.toString() ?? '').substring(0, 10)),
                          subtitle: row['remark'] != null ? Text(row['remark'].toString()) : null,
                        ),
                    ]),
    );
  }

  double _maxY() {
    var m = 1.0;
    for (final d in _days) {
      final dd = _perDay[d] ?? {};
      final total = ((dd['present'] ?? 0) + (dd['absent'] ?? 0) + (dd['late'] ?? 0)).toDouble();
      if (total > m) m = total;
    }
    return m + 1;
  }

  Widget _legendRow(Color color, String label, int count) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
      Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 8),
      Expanded(child: Text(label)),
      Text(count.toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
    ]));
  }

  Color _statusColor(String s) =>
      s == 'present' ? Colors.green : s == 'absent' ? Colors.red : Colors.orange;
}

class SonarDot extends StatelessWidget {
  final Color color;
  const SonarDot(this.color, {super.key});
  @override
  Widget build(BuildContext context) => Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}