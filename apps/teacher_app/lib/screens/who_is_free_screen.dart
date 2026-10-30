import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import 'routine_screen.dart';

String _slotDisplayName(String? l0) {
  final l = (l0 ?? '').toString().trim();
  final m = RegExp(r'^CLASS_(\d)$', caseSensitive: false).firstMatch(l);
  if (m != null) {
    const bn = <String, String>{
      '1': '১ম',
      '2': '২য়',
      '3': '৩য়',
      '4': '৪র্থ',
      '5': '৫ম',
      '6': '৬ষ্ঠ',
      '7': '৭ম',
    };
    return '${bn[m.group(1)!] ?? m.group(1)} Period';
  }
  final lw = l.toLowerCase();
  if (lw == 'assembly') return 'সমাবেশ';
  if (lw == 'leisure') return 'অবসর';
  return l0?.toString() ?? '';
}

class WhoIsFreeScreen extends StatefulWidget {
  final dynamic teacher;
  const WhoIsFreeScreen({super.key, required this.teacher});
  @override
  State<WhoIsFreeScreen> createState() => _WhoIsFreeScreenState();
}

class _WhoIsFreeScreenState extends State<WhoIsFreeScreen> {
  static const _ink = Color(0xFF102A43);
  static const _teal = Color(0xFF087F8C);
  static const _canvas = Color(0xFFF3F6FA);
  static const _days = [
    'রবিবার',
    'সোমবার',
    'মঙ্গলবার',
    'বুধবার',
    'বৃহস্পতিবার',
  ];
  bool _loading = true;
  String? _error;
  String _bdTime = '';
  String _day = '';
  int? _selectedDay;
  List _teachers = [];
  String _selectedPeriod = '1';

  bool _hasClassInSelectedPeriod(dynamic teacher) {
    final periods = teacher['periods_today'] as List? ?? const [];
    return periods.any(
      (period) => RegExp(
        '^CLASS_${_selectedPeriod}\$',
        caseSensitive: false,
      ).hasMatch((period['slot_label']?.toString() ?? '').trim()),
    );
  }

  List get _restingTeachers => _teachers
      .where((teacher) => !_hasClassInSelectedPeriod(teacher))
      .toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_teachers.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final dayQuery = _selectedDay == null ? '' : '?day=$_selectedDay';
      var redirectToWorkingDay = false;
      await Api.loadCachedFirst('/teacher/directory$dayQuery', (r) {
        if (!mounted || r is! Map) return;
        if (redirectToWorkingDay) return;
        final today = (r['today'] ?? r['day']) as int? ?? 0;
        if (_selectedDay == null && today >= 5) {
          setState(() {
            _selectedDay = 0;
            _loading = true;
          });
          redirectToWorkingDay = true;
          return;
        }
        setState(() {
          _bdTime = r['bd_time'] ?? '';
          _selectedDay ??= today;
          final day = r['day'] as int? ?? _selectedDay ?? 0;
          _day = _days[day];
          _teachers = r['teachers'] is List ? r['teachers'] : [];
          _loading = false;
        });
      });
      if (redirectToWorkingDay && mounted) await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _call(String phone) async {
    final p = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (p.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('এই teacher-এর ফোন নম্বর দেওয়া নেই')),
      );
      return;
    }
    final uri = Uri.parse('tel:$p');
    if (await canLaunchUrl(uri)) {
      if (mounted) await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Call launch ব্যর্থ')));
    }
  }

  Future<void> _whatsapp(String phone) async {
    final p = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (p.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('এই teacher-এর ফোন নম্বর দেওয়া নেই')),
        );
      }
      return;
    }
    final uri = Uri.parse('https://wa.me/$p');
    if (await canLaunchUrl(uri)) {
      if (mounted) await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('WhatsApp launch ব্যর্থ')));
    }
  }

  Future<void> _viewTeacherRoutine(int teacherId, String teacherName) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoutineScreen(
          teacher: widget.teacher,
          initialTeacherId: teacherId,
          initialTeacherName: teacherName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _canvas,
      appBar: AppBar(
        backgroundColor: _canvas,
        foregroundColor: _ink,
        elevation: 0,
        title: const Text(
          'Resting Teacher',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF102A43), Color(0xFF087F8C)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: _teal.withValues(alpha: .2),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .14),
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: const Icon(
                          Icons.event_available_rounded,
                          color: Colors.white,
                          size: 27,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _day,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'বাংলাদেশ সময়  $_bdTime',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: .82),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'নির্বাচিত period-এর Routine অনুযায়ী বিশ্রামে থাকা শিক্ষক',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: .9),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        children: [
                          Text(
                            '${_restingTeachers.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 27,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'বিশ্রামে',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .8),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Period filter
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: _ink.withValues(alpha: .04),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _selectedDay,
                            isExpanded: true,
                            hint: const Text('দিন বাছুন'),
                            items: [
                              for (var i = 0; i < _days.length; i++)
                                DropdownMenuItem(
                                  value: i,
                                  child: Text(_days[i]),
                                ),
                            ],
                            onChanged: (v) async {
                              if (v == null) return;
                              setState(() {
                                _selectedDay = v;
                                _loading = true;
                              });
                              await _load();
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedPeriod,
                            isExpanded: true,
                            items: [
                              for (int i = 1; i <= 7; i++)
                                DropdownMenuItem(
                                  value: '$i',
                                  child: Text(_slotDisplayName('CLASS_$i')),
                                ),
                            ],
                            onChanged: (v) =>
                                setState(() => _selectedPeriod = v ?? '1'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 7, 16, 2),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.people_alt_outlined,
                        size: 17,
                        color: _teal,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '$_day · ${_slotDisplayName('CLASS_$_selectedPeriod')} — Resting Teacher',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                          ),
                        ),
                      ),
                      Text(
                        '${_restingTeachers.length} জন',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _teal,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _restingTeachers.isEmpty ? 1 : _restingTeachers.length,
                    itemBuilder: (_, i) {
                      if (_restingTeachers.isEmpty) {
                        return SizedBox(
                          height: 260,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 76,
                                    height: 76,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFE5F2F3),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.event_busy_outlined,
                                      color: _teal,
                                      size: 34,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  const Text(
                                    'এই period-এ বিশ্রামে থাকা শিক্ষক নেই',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: _ink,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  const Text(
                                    'অন্য দিন বা period বেছে আবার দেখুন',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF617387),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }
                      final t = _restingTeachers[i];
                      final teacherName = '${t['name'] ?? ''}'.trim();
                      final periods = t['periods_today'] as List? ?? [];
                      final phoneNum = '${t['phone'] ?? ''}';
                      final periodLabels = periods
                          .map(
                            (p) =>
                                _slotDisplayName(p['slot_label']?.toString()),
                          )
                          .join(', ');
                      return Card(
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: const BorderSide(color: Color(0xFFE6ECF2)),
                        ),
                        margin: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 5,
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 9,
                          ),
                          leading: CircleAvatar(
                            radius: 25,
                            backgroundColor: const Color(0xFFE2F4F1),
                            child: Text(
                              teacherName.isEmpty
                                  ? 'শ'
                                  : teacherName.characters.first.toUpperCase(),
                              style: const TextStyle(
                                color: _teal,
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          title: Text(
                            '${t['name'] ?? ''}${t['designation'] != null && '${t['designation']}'.trim().isNotEmpty ? ' (${t['designation']})' : ''}',
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE7F7F0),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.check_circle,
                                          size: 13,
                                          color: Color(0xFF16845B),
                                        ),
                                        SizedBox(width: 5),
                                        Text(
                                          'বিশ্রামে',
                                          style: TextStyle(
                                            color: Color(0xFF16845B),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Text(
                                    '${periods.length}টি class',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF617387),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 7),
                              Text(
                                'Period: ${periodLabels.isEmpty ? 'নেই' : periodLabels}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF526579),
                                ),
                              ),
                              if (phoneNum.isNotEmpty)
                                Text(
                                  '☎  $phoneNum',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF526579),
                                  ),
                                ),
                            ],
                          ),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            icon: const Icon(
                              Icons.more_horiz_rounded,
                              color: Color(0xFF64748B),
                            ),
                            onSelected: (action) {
                              if (action == 'call') {
                                _call(phoneNum);
                              } else if (action == 'whatsapp') {
                                _whatsapp(phoneNum);
                              } else {
                                final id = int.tryParse('${t['id']}');
                                if (id != null)
                                  _viewTeacherRoutine(id, teacherName);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'call',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.phone_outlined,
                                      color: _teal,
                                      size: 19,
                                    ),
                                    SizedBox(width: 9),
                                    Text('কল করুন'),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'whatsapp',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.chat_bubble_outline,
                                      color: Color(0xFF128C7E),
                                      size: 19,
                                    ),
                                    SizedBox(width: 9),
                                    Text('WhatsApp'),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'routine',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.schedule_rounded,
                                      color: Colors.indigo,
                                      size: 19,
                                    ),
                                    SizedBox(width: 9),
                                    Text('Routine দেখুন'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
