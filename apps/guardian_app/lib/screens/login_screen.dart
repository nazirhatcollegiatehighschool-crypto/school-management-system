import 'package:flutter/material.dart';
import '../api.dart';
import '../config.dart';
import '../fcm_service.dart';
import '../server_settings.dart';
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

  @override
  void dispose() {
    _code.dispose();
    _dob.dispose();
    _className.dispose();
    _section.dispose();
    _roll.dispose();
    _phone.dispose();
    super.dispose();
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
      if (r is! Map) {
        throw Exception('সার্ভার থেকে সঠিক উত্তর আসেনি। আবার চেষ্টা করুন।');
      }
      if (Api.isQueued(r)) {
        throw Exception('ইন্টারনেট নেই — login-এর জন্য online থাকতে হবে।');
      }
      final dynamic token = r['token'];
      if (token is! String || token.isEmpty) {
        throw Exception('Login ব্যর্থ হয়েছে। তথ্যগুলো ঠিক আছে কিনা দেখুন।');
      }
      Api.token = token;
      await Api.saveToken(token);
      registerDeviceToken();
      Api.kickstartPreload(); // auto-download essential data for offline use
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomeScreen(students: r['students'])),
      );
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indigo = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5FB),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Guardian / Family Crest Badge
                  Center(
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [indigo, const Color(0xFF4338CA)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: indigo.withValues(alpha: 0.35),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.family_restroom_rounded,
                        size: 46,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Title & Subtitle
                  Text(
                    'Guardian Portal',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1E1B4B),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Student-এর admission-এর তথ্য দিয়ে login করুন',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.blueGrey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 26),

                  // Login Form Card
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Error message banner
                        if (_error != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFFCA5A5)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(
                                      color: Color(0xFFB91C1C),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Student Unique ID
                        TextField(
                          controller: _code,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Student Unique ID *',
                            hintText: 'e.g. S-2026-001',
                            prefixIcon: Icon(Icons.qr_code_rounded, color: indigo, size: 20),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Date of Birth
                        TextField(
                          controller: _dob,
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: 'Date of Birth *',
                            hintText: 'YYYY-MM-DD',
                            prefixIcon: Icon(Icons.calendar_today_rounded, color: indigo, size: 18),
                            suffixIcon: const Icon(Icons.arrow_drop_down, size: 24),
                          ),
                          onTap: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: DateTime(2013),
                              firstDate: DateTime(1995),
                              lastDate: DateTime.now(),
                            );
                            if (d != null) {
                              _dob.text = d.toIso8601String().substring(0, 10);
                            }
                          },
                        ),
                        const SizedBox(height: 12),

                        // Class & Section Row
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _className,
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: 'Class *',
                                  hintText: 'e.g. 6',
                                  prefixIcon: Icon(Icons.school_outlined, color: indigo, size: 20),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _section,
                                textInputAction: TextInputAction.next,
                                textCapitalization: TextCapitalization.characters,
                                decoration: InputDecoration(
                                  labelText: 'Section/Group *',
                                  hintText: 'e.g. A',
                                  prefixIcon: Icon(Icons.meeting_room_outlined, color: indigo, size: 20),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Roll & Admission Phone Row
                        Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: TextField(
                                controller: _roll,
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: 'Roll *',
                                  hintText: '1',
                                  prefixIcon: Icon(Icons.tag_rounded, color: indigo, size: 20),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 6,
                              child: TextField(
                                controller: _phone,
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _loading ? null : _login(),
                                decoration: InputDecoration(
                                  labelText: 'Admission Phone *',
                                  hintText: '01XXXXXXXXX',
                                  prefixIcon: Icon(Icons.phone_outlined, color: indigo, size: 20),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),

                        // Submit Button
                        FilledButton(
                          onPressed: _loading ? null : _login,
                          style: FilledButton.styleFrom(
                            backgroundColor: indigo,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                            shadowColor: indigo.withValues(alpha: 0.4),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'লগইন করুন (Sign In)',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 12),

                        // Server URL Dialog button
                        Center(
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.blueGrey.shade600,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                            icon: const Icon(Icons.dns_outlined, size: 15),
                            label: Text(
                              Config.serverUrl,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                            ),
                            onPressed: () async {
                              await showServerUrlDialog(context);
                              if (mounted) setState(() {});
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // School Branding Footer
                  Center(
                    child: Text(
                      'Nazirhat Collegiate High School • Guardian Portal',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}