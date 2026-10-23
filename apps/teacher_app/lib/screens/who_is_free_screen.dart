import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import 'routine_screen.dart';

String _slotDisplayName(String? l0) {
  final l = (l0 ?? '').toString().trim();
  final m = RegExp(r'^CLASS_(\d)$', caseSensitive: false).firstMatch(l);
  if (m != null) {
    const bn = <String, String>{'1': '১ম', '2': '২য়', '3': '৩য়', '4': '৪র্থ', '5': '৫ম', '6': '৬ষ্ঠ', '7': '৭ম'};
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
  bool _loading = true;
  String? _error;
  String _bdTime = '';
  String _day = '';
  List _teachers = [];
  String _selectedPeriod = 'all'; // 'all', '1', '2', '3', '4', '5', '6', '7'

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (_teachers.isEmpty) setState(() { _loading = true; _error = null; });
    try {
      await Api.loadCachedFirst('/teacher/directory', (r) {
        if (!mounted || r is! Map) return;
        setState(() {
          _bdTime = r['bd_time'] ?? '';
          _day = r['day'] != null ? const ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'][r['day']] : '';
          _teachers = r['teachers'] is List ? r['teachers'] : [];
          _loading = false;
        });
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _call(String phone) async {
    final p = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (p.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('এই teacher-এর ফোন নম্বর দেওয়া নেই')));
      return;
    }
    final uri = Uri.parse('tel:$p');
    if (await canLaunchUrl(uri)) {
      if (mounted) await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Call launch ব্যর্থ')));
    }
  }

  Future<void> _whatsapp(String phone) async {
    final p = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (p.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('এই teacher-এর ফোন নম্বর দেওয়া নেই')));
      }
      return;
    }
    final uri = Uri.parse('https://wa.me/$p');
    if (await canLaunchUrl(uri)) {
      if (mounted) await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('WhatsApp launch ব্যর্থ')));
    }
  }

  Future<void> _viewTeacherRoutine(int teacherId, String teacherName) async {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => RoutineScreen(
        teacher: widget.teacher,
        initialTeacherId: teacherId,
        initialTeacherName: teacherName,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('কে ফ্রি? (Who is Free)'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Container(
                    margin: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _day == 'Friday' || _day == 'Saturday' ? Colors.orange.shade50 : Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$_day — বাংলাদেশ সময় $_bdTime\n${_day == 'Friday' || _day == 'Saturday' ? 'ছুটির দিন — সবাই ফ্রি' : 'এখন ক্লাস চলছে এমন teacher-এ "ব্যস্ত" চিহ্নিত'}',
                        style: const TextStyle(fontSize: 13)),
                  ),
                  // Period filter
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedPeriod,
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem(value: 'all', child: Text('সব পিরিয়ড')),
                          for (int i = 1; i <= 7; i++)
                            DropdownMenuItem(value: '$i', child: Text(_slotDisplayName('CLASS_$i'))),
                        ],
                        onChanged: (v) => setState(() => _selectedPeriod = v ?? 'all'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _teachers.length,
                      itemBuilder: (_, i) {
                        final t = _teachers[i];
                        final periods = t['periods_today'] as List? ?? [];
                        final filteredPeriods = _selectedPeriod == 'all'
                            ? periods
                            : periods.where((p) => RegExp(r'^CLASS_' + _selectedPeriod + r'$', caseSensitive: false).hasMatch((p['slot_label']?.toString() ?? '').trim())).toList();
                        final hasClassInPeriod = _selectedPeriod == 'all' || filteredPeriods.isNotEmpty;
                        if (!hasClassInPeriod && _selectedPeriod != 'all') {
                          return const SizedBox.shrink();
                        }
                        final free = t['free'] == true;
                        final phoneNum = '${t['phone'] ?? ''}';
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: free ? Colors.green.shade100 : Colors.red.shade100,
                              child: Icon(free ? Icons.check : Icons.school, color: free ? Colors.green : Colors.red),
                            ),
                            title: Text('${t['name'] ?? ''}${t['designation'] != null && '${t['designation']}'.trim().isNotEmpty ? ' (${t['designation']})' : ''}'),
                            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(free
                                  ? 'ফ্রি'
                                  : (t['is_escape'] == true || t['is_escape'] == 1 || t['is_escape'] == '1'
                                          ? 'বাঙ্ক (ক্লাস-ফাঁকি) — ${t['current_class']?['subject_name'] ?? ''} (${_slotDisplayName(t['current_class']?['slot_label']?.toString())})'
                                          : 'ব্যস্ত — ${t['current_class']?['subject_name'] ?? ''} (${_slotDisplayName(t['current_class']?['slot_label']?.toString())})'),
                                      style: TextStyle(color: free ? Colors.green.shade700 : Colors.red.shade700, fontWeight: FontWeight.w600)),
                              if (filteredPeriods.isNotEmpty)
                                Text('Periods: ${filteredPeriods.map((p) => '${_slotDisplayName(p['slot_label']?.toString())} ${p['subject_name']}').join(', ')}', style: const TextStyle(fontSize: 12)),
                              if (phoneNum.isNotEmpty) Text('📞 $phoneNum', style: const TextStyle(fontSize: 12)),
                            ]),
                            isThreeLine: true,
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              if (phoneNum.isNotEmpty)
                                IconButton(icon: const Icon(Icons.phone, color: Colors.green), tooltip: 'কল করুন',
                                    onPressed: () => _call(phoneNum)),
                              if (phoneNum.isNotEmpty)
                                IconButton(icon: const Icon(Icons.chat, color: Color(0xFF128C7E)), tooltip: 'WhatsApp',
                                    onPressed: () => _whatsapp(phoneNum)),
                              IconButton(icon: const Icon(Icons.schedule, color: Colors.indigo), tooltip: 'Routine দেখুন',
                                  onPressed: () => _viewTeacherRoutine(t['id'] as int, t['name'] as String)),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
                ]),
    );
  }

}
