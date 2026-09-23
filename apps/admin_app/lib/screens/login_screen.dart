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
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => checkForUpdate(context, 'admin'));
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
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.admin_panel_settings, size: 72, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text('Admin Panel', textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 32),
              if (_error != null)
                Padding(padding: const EdgeInsets.only(bottom: 16),
                    child: Text(_error!, style: const TextStyle(color: Colors.red))),
              TextField(controller: _user, decoration: const InputDecoration(
                  labelText: 'Username', border: OutlineInputBorder())),
              const SizedBox(height: 16),
              TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(
                  labelText: 'Password', border: OutlineInputBorder())),
              const SizedBox(height: 24),
              FilledButton(onPressed: _loading ? null : _login,
                child: Padding(padding: const EdgeInsets.all(14),
                    child: _loading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Login'))),
            ],
          ),
        ),
      ),
    );
  }
}
