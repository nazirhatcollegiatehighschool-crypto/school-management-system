import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// A single parsed routine period used by the alert engine.
class RoutineAlert {
  final int id;
  final int day; // 0=Sun..4=Thu
  final int startSec; // seconds from midnight
  final int endSec;
  final String subject;
  final String classLabel;
  final String slotLabel;
  final String room;

  RoutineAlert({
    required this.id,
    required this.day,
    required this.startSec,
    required this.endSec,
    required this.subject,
    required this.classLabel,
    required this.slotLabel,
    required this.room,
  });

  static int _hms(String t) {
    final p = t.split(':');
    if (p.length < 2) return 0;
    return int.parse(p[0]) * 3600 + int.parse(p[1]) * 60 + (p.length > 2 ? int.parse(p[2]) : 0);
  }

  static bool isNonPeriod(String slotLabel) {
    final l = slotLabel.toLowerCase();
    // Non-academic slots in the new named scheme: ASSEMBLY and LEISURE are
    // break periods; only CLASS_1..CLASS_7 are counted as periods.
    return l.contains('break') || l.contains('assembly') ||
        l.contains('leisure') || l.contains('tiffin');
  }

  /// Maps the backend CODE to the label shown to teachers so the UI keeps
  /// saying "Period 1..7" for CLASS_* slots and Break for ASSEMBLY/LEISURE.
  static String displayForSlot(String label) {
    final m = RegExp(r'^CLASS_(\d+)$', caseSensitive: false).firstMatch(label.trim());
    if (m != null) return 'Period ${m.group(1)}';
    final l = label.trim().toLowerCase();
    if (l == 'assembly') return 'সমাবেশ';
    if (l == 'leisure') return 'অবসর';
    return label;
  }
  static RoutineAlert? fromApi(Map<String, dynamic> e, {int idx = 0}) {
    final day = e['day'];
    if (day is! int || day < 0 || day > 4) return null;
    final st = e['start_time']?.toString() ?? '';
    final en = e['end_time']?.toString() ?? '';
    if (st.length < 5 || en.length < 5) return null;
    final slot = (e['slot_label'] ?? 'Period $idx').toString();
    if (isNonPeriod(slot)) return null;
    final sub = e['subject'];
    final sname = sub is Map ? (sub['name'] ?? '').toString() : (e['subject']?.toString() ?? '');
    final groups = (e['groups'] as List? ?? []).cast<Map>();
    final sections = (e['sections'] as List? ?? []).cast<Map>();
    final labels = <String>[
      ...groups.map((g) => '${g['class_name']} (${g['group_name']})'),
      ...sections.map((s) => '${s['class_name']} (${s['section']})'),
    ];
    return RoutineAlert(
      id: (e['id'] ?? idx).toString().isNotEmpty ? int.parse(e['id'].toString()) : idx,
      day: day,
      startSec: _hms(st),
      endSec: _hms(en),
      subject: sname,
      classLabel: labels.isEmpty ? '' : labels.join(', '),
      slotLabel: slot.replaceFirst(' Period', ''),
      room: (e['room'] ?? '').toString(),
    );
  }
}

/// Snapshot of the teacher's nearest class for the home card + beep engine.
class ClassAlertSnapshot {
  final RoutineAlert? routine;
  final String phase; // none | idle | countdown | live
  final int secondsLeft; // 0 when >24h away
  final bool isWeekend;
  final bool anyToday;

  const ClassAlertSnapshot({
    this.routine,
    this.phase = 'none',
    this.secondsLeft = 0,
    this.isWeekend = false,
    this.anyToday = false,
  });

  bool get hasCard => routine != null && phase != 'none';
}

class ClassAlertService {
  ClassAlertService._();
  static final ClassAlertService instance = ClassAlertService._();

  final _notifications = FlutterLocalNotificationsPlugin();
  final AudioPlayer _player = AudioPlayer();
  final ValueNotifier<ClassAlertSnapshot> snapshot = ValueNotifier(const ClassAlertSnapshot());
  bool _initOk = false;
  bool _channelsCreated = false;
  List<RoutineAlert> _all = [];
  Timer? _ticker;

  // beep dedupe guards (per routine+date+event)
  final Map<String, int> _beepGuard = {};

  static int _schoolDayOf(DateTime d) {
    // DateTime.weekday: Mon=1..Sun=7 -> routines day Sun=0..Thu=4
    if (d.weekday == 7) return 0;
    return d.weekday; // Mon=1..Thu=4; Fri=5 Sat=6 -> off
  }

  Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      String name = 'Asia/Dhaka';
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        if (info.identifier.isNotEmpty) name = info.identifier;
      } catch (_) {}
      try {
        tz.setLocalLocation(tz.getLocation(name));
      } catch (_) {
        tz.setLocalLocation(tz.UTC);
      }
      const init = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      );
      await _notifications.initialize(settings: init);
      final android = _notifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      await _ensureChannels();
      _initOk = true;
    } catch (_) {
      _initOk = false;
    }
  }

  Future<void> _ensureChannels() async {
    if (_channelsCreated) return;
    AndroidFlutterLocalNotificationsPlugin? android;
    try {
      android = _notifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        'class_reminder',
        'Class Reminder',
        description: 'Bep — 5 minutes before a class starts',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('bep_single'),
      ));
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        'class_start',
        'Class Started',
        description: 'Bep-Bep — at the exact start of a class',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('bep_double'),
      ));
    } catch (_) {}
    _channelsCreated = true;
  }

  /// Call whenever routine data refreshes (dashboard load / routine changes).
  Future<void> updateRoutines(List<dynamic> entries) async {
    _all = [];
    int i = 0;
    for (final e in entries) {
      if (e is Map<String, dynamic>) {
        final ra = RoutineAlert.fromApi(e, idx: i);
        if (ra != null) _all.add(ra);
      }
      i++;
    }
    await _scheduleLocalNotifications();
    _tick();
  }

  List<RoutineAlert> get routines => _all;
  bool get ready => _initOk;

  /// Weekly, battery-friendly local notifications (background + killed state).
  Future<void> _scheduleLocalNotifications() async {
    if (!_initOk) return;
    try {
      await _notifications.cancelAll();
      int id = 100;
      final now = tz.TZDateTime.now(tz.local);
      for (final r in _all) {
        final weekday = r.day == 0 ? 7 : r.day; // DateTime.weekday
        final startH = r.startSec ~/ 3600;
        final startM = (r.startSec % 3600) ~/ 60;
        var start = tz.TZDateTime(tz.local, now.year, now.month, now.day, startH, startM);
        while (start.weekday != weekday || !start.isAfter(now)) {
          start = start.add(const Duration(days: 1));
        }
        final reminder = start.subtract(const Duration(minutes: 5));

        final detailsReminder = const NotificationDetails(
          android: AndroidNotificationDetails(
            'class_reminder',
            'Class Reminder',
            importance: Importance.high,
            priority: Priority.high,
            sound: RawResourceAndroidNotificationSound('bep_single'),
            category: AndroidNotificationCategory.reminder,
          ),
        );
        final detailsStart = const NotificationDetails(
          android: AndroidNotificationDetails(
            'class_start',
            'Class Started',
            importance: Importance.max,
            priority: Priority.high,
            sound: RawResourceAndroidNotificationSound('bep_double'),
          ),
        );

        final body = r.classLabel.isEmpty
            ? '${r.slotLabel} starts at ${_fmt(start)}${r.room.isNotEmpty ? ' • Room ${r.room}' : ''}'
            : '${r.classLabel} · ${r.slotLabel}${r.room.isNotEmpty ? ' • Room ${r.room}' : ''}';

        await _notifications.zonedSchedule(
          id: id++,
          title: '⏰ ${r.subject} in 5 minutes',
          body: body,
          scheduledDate: reminder,
          notificationDetails: detailsReminder,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          payload: '{"routine_id":${r.id},"event":"reminder"}',
        );
        await _notifications.zonedSchedule(
          id: id++,
          title: '🔴 ${r.subject} started now',
          body: body,
          scheduledDate: start,
          notificationDetails: detailsStart,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          payload: '{"routine_id":${r.id},"event":"start"}',
        );
      }
    } catch (_) {}
  }

  static String _fmt(tz.TZDateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// 1-second engine. Must be called from initState of the root home screen so
  /// the beeps + card stay live wherever the user lands.
  void start() {
    if (_ticker != null) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _tick();
  }

  void _tick() {
    final snap = _computeSnapshot(DateTime.now());
    snapshot.value = snap;
    _handleBeeps(snap);
  }

  ClassAlertSnapshot _computeSnapshot(DateTime now) {
    final sd = _schoolDayOf(now);
    final isWeekend = sd >= 5;
    final nowSec = now.hour * 3600 + now.minute * 60 + now.second;
    final today = _all.where((r) => r.day == sd).toList();

    if (!isWeekend) {
      // live period wins first
      for (final r in today) {
        if (nowSec >= r.startSec && nowSec < r.endSec) {
          return ClassAlertSnapshot(routine: r, phase: 'live', secondsLeft: 0, isWeekend: false, anyToday: true);
        }
      }
      // countdown (within 5 min before)
      RoutineAlert? cd;
      for (final r in today) {
        if (nowSec >= r.startSec - 300 && nowSec < r.startSec) {
          if (cd == null || r.startSec < cd.startSec) cd = r;
        }
      }
      if (cd != null) {
        return ClassAlertSnapshot(routine: cd, phase: 'countdown', secondsLeft: cd.startSec - nowSec, isWeekend: false, anyToday: true);
      }
      // earliest upcoming today
      RoutineAlert? next;
      for (final r in today) {
        if (r.startSec > nowSec) {
          if (next == null || r.startSec < next.startSec) next = r;
        }
      }
      if (next != null) {
        return ClassAlertSnapshot(routine: next, phase: 'idle', secondsLeft: next.startSec - nowSec, isWeekend: false, anyToday: true);
      }
    }
    // no more classes today (or weekend) -> next school day
    RoutineAlert? nr;
    final todayDate = DateTime(now.year, now.month, now.day);
    for (int d = 1; d <= 7; d++) {
      final candidate = todayDate.add(Duration(days: d));
      final csd = _schoolDayOf(candidate);
      if (csd >= 5) continue;
      final ra = _all.where((r) => r.day == csd).toList();
      if (ra.isEmpty) continue;
      ra.sort((a, b) => a.startSec.compareTo(b.startSec));
      nr = ra.first;
      break;
    }
    if (nr == null) {
      return ClassAlertSnapshot(phase: 'none', isWeekend: isWeekend);
    }
    return ClassAlertSnapshot(routine: nr, phase: 'idle', secondsLeft: -1, isWeekend: isWeekend, anyToday: !isWeekend);
  }

  Future<void> _handleBeeps(ClassAlertSnapshot snap) async {
    if (snap.routine == null) return;
    final today = _dateKey(DateTime.now());
    if (snap.phase == 'countdown') {
      final key = '$today:${snap.routine!.id}:reminder';
      if (!_beepGuard.containsKey(key)) {
        _beepGuard[key] = 1;
        await _playBeep(single: true);
      }
    } else if (snap.phase == 'live') {
      final key = '$today:${snap.routine!.id}:start';
      if (!_beepGuard.containsKey(key)) {
        _beepGuard[key] = 1;
        await _playBeep(single: false);
      }
    }
    if (_beepGuard.length > 80) {
      // keep only today's keys
      _beepGuard.removeWhere((k, _) => !k.startsWith(today));
    }
  }

  Future<void> _playBeep({required bool single}) async {
    try {
      await _player.setVolume(0.85);
      await _player.play(AssetSource(single ? 'sounds/bep_single.wav' : 'sounds/bep_double.wav'));
    } catch (_) {}
  }

  static String _dateKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    _player.dispose();
  }
}
