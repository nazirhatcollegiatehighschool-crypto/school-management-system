import 'package:flutter/material.dart';
import '../api.dart';
import '../fcm_service.dart';
import '../update_check.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _code = TextEditingController();
  final _dob = TextEditingController();
  final _className = TextEditingController();
  final _section = TextEditingController();
  final _roll = TextEditingController();
  final _phone = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => checkForUpdate(context, 'guardian'));
  }

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await Api.post('/auth/guardian-login', {
        'student_code': _code.text.trim(),
        'dob': _dob.text.trim(),
        'class_name': _className.text.trim(),
        'section': _section.text.trim(),
        'roll': num.tryParse(_roll.text.trim()) ?? 0,
        'phone': _phone.text.trim(),
      });
      Api.token = r['token'];
      await Api.saveToken(r['token']);
      registerDeviceToken();
      if (!mounted) return;
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => HomeScreen(students: r['students'])));
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.family_restroom, size: 64, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 10),
                Text('Guardian Login', textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                const Text('Student-এর admission-এর তথ্য দিয়ে login করুন',
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                TextField(controller: _code, decoration: const InputDecoration(
                    labelText: 'Student Unique ID *', hintText: 'S-2026-001', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: _dob, readOnly: true, decoration: const InputDecoration(
                    labelText: 'Date of Birth *', border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today)),
                  onTap: () async {
                    final d = await showDatePicker(context: context,
                        initialDate: DateTime(2013), firstDate: DateTime(1995), lastDate: DateTime.now());
                    if (d != null) _dob.text = d.toIso8601String().substring(0, 10);
                  }),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextField(controller: _className, keyboardType: TextInputType.number, decoration: const InputDecoration(
                      labelText: 'Class *', hintText: '6', border: OutlineInputBorder()))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: _section, decoration: const InputDecoration(
                      labelText: 'Section/Group *', hintText: 'A', border: OutlineInputBorder()))),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextField(controller: _roll, keyboardType: TextInputType.number, decoration: const InputDecoration(
                      labelText: 'Roll *', border: OutlineInputBorder()))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(
                      labelText: 'Admission Phone *', border: OutlineInputBorder()))),
                ]),
                const SizedBox(height: 20),
                if (_error != null)
                  Padding(padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error!, style: const TextStyle(color: Colors.red))),
                FilledButton(
                  onPressed: _loading ? null : _login,
                  child: Padding(padding: const EdgeInsets.all(14),
                      child: _loading
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Login')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}