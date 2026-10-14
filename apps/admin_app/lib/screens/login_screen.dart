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
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => checkForUpdate(context, 'admin'));
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await Api.post('/auth/login', {
        'username': _user.text.trim(),
        'password': _pass.text,
      });
      if (r['user']['role'] != 'admin') throw Exception('Admin only');
      await Api.saveToken(r['token']);
      registerDeviceToken();
      if (!mounted) return;
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const HomeScreen()));
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo / Header Icon
                  Center(
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [primaryColor, const Color(0xFF1E40AF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: primaryColor.withValues(alpha: 0.35),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.admin_panel_settings_rounded,
                        size: 46,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Title & Subtitle
                  Text(
                    'Admin Portal',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Sign in to manage the school management system',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.blueGrey.shade600,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Login Card Container
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Error Alert Banner
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
                          const SizedBox(height: 18),
                        ],

                        // Username Field
                        Text(
                          'Username',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _user,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            hintText: 'Enter username',
                            prefixIcon: Icon(Icons.person_outline_rounded, color: primaryColor, size: 20),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Password Field
                        Text(
                          'Password',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _pass,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _loading ? null : _login(),
                          decoration: InputDecoration(
                            hintText: 'Enter password',
                            prefixIcon: Icon(Icons.lock_outline_rounded, color: primaryColor, size: 20),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                color: Colors.grey.shade600,
                                size: 20,
                              ),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Login Action Button
                        FilledButton(
                          onPressed: _loading ? null : _login,
                          style: FilledButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                            shadowColor: primaryColor.withValues(alpha: 0.4),
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
                                  'Sign In',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                        ),
                        // Server URL Dialog button — lets the app follow the
                        // LAN IP / ngrok URL change without a rebuild.
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
                  const SizedBox(height: 28),

                  // Footer info
                  Center(
                    child: Text(
                      'School Management Administration System',
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
