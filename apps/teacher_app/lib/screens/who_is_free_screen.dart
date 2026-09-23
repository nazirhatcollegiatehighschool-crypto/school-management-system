import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';

String _slotName(String? raw) {
  final l = (raw ?? '').trim();
  final m = RegExp(r'^CLASS_(\d)$', caseSensitive: false).firstMatch(l);
  if (m != null) {
    const bn = <String, String>{
      '1': '\u09E7\u09AE', '2': '\u09E8\u09DF', '3': '\u09E9\u09DF',
      '4': '\u09EA\u09F0\u09CD\u09A5', '5': '\u09EB\u09AE',
      '6': '\u09EC\u09B7\u09CD\u09A0', '7': '\u09ED\u09AE',
    };
    return '${bn[m.group(1)!] ?? m.group(1)} Period';
  }
  if (l.toLowerCase() == 'assembly') return '\u09B8\u09AE\u09BE\u09AC\u09C7\u09B6';
  if (l.toLowerCase() == 'leisure') return '\u0985\u09AC\u09B8\u09B0';
  return raw?.toString() ?? '';
}
String _slotDisplayName(String? l0) {
  final l = (l0 ?? '').toString().trim();
  final m = RegExp(r'^CLASS_(\d)$', caseSensitive: false).firstMatch(l);
  if (m != null) {
    const bn = <String, String>{'1': '১ম', '2': '২য়', '3': '৩য়', '4': '৪ৰ্থ', '5': '৫ম', '6': '৬ষ্ঠ', '7': '৭ম'};
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

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await Api.get('/teacher/directory');
      setState(() {
        _bdTime = r['bd_time'] ?? '';
        _day = r['day'] != null ? const ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'][r['day']] : '';
        _teachers = r['teachers'] is List ? r['teachers'] : [];
        _loading = false;
      });
    } catch (e) {
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
                    child: Text('$_day — বাংলাদেশ সময় $_bdTime\n${_day == 'Friday' || _day == 'Saturday' ? 'ছুটির দিন — সবাই ফ্রি' : 'এখন ক্লাস চলছে এমন teacher-এ “ব্যস্ত” চিহ্নিত'}',
                        style: const TextStyle(fontSize: 13)),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _teachers.length,
                      itemBuilder: (_, i) {
                        final t = _teachers[i];
                        final free = t['free'] == true;
                        final phone = '${t['phone'] ?? ''}';
                        final periods = t['periods_today'] as List? ?? [];
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
                              if (periods.isNotEmpty)
                                Text('Periods: ${periods.map((p) => '${_slotDisplayName(p['slot_label']?.toString())} ${p['subject_name']}').join(', ')}', style: const TextStyle(fontSize: 12)),
                              if (phone.isNotEmpty) Text('📞 $phone', style: const TextStyle(fontSize: 12)),
                            ]),
                            isThreeLine: true,
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              if (phone.isNotEmpty)
                                IconButton(icon: const Icon(Icons.phone, color: Colors.green), tooltip: 'কল করুন',
                                    onPressed: () => _call(phone)),
                              if (phone.isNotEmpty)
                                IconButton(icon: const Icon(Icons.chat, color: Color(0xFF128C7E)), tooltip: 'WhatsApp',
                                    onPressed: () => _whatsapp(phone)),
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
