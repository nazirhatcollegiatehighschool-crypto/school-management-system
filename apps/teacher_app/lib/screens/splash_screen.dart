import 'package:flutter/material.dart';
import '../api.dart';
import 'login_screen.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _failed = false;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() { _failed = false; _message = ''; });
    final hasToken = await Api.loadToken();
    if (!hasToken) {
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
      return;
    }
    try {
      final r = await Api.get('/teacher/profile');
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomeScreen(teacher: r['teacher'])));
    } catch (e) {
      // Only auth failures invalidate the session. A transient network blip
      // must NOT log the teacher out — offer in-app retry instead.
      if (!Api.isNetworkError(e)) {
        await Api.clearToken();
      }
      if (!mounted) return;
      setState(() {
        _failed = true;
        _message = Api.isNetworkError(e)
            ? 'সার্ভারে পৌঁছানো যায়নি। ইন্টারনেট চেক করে "আবার চেষ্টা" চাপুন।'
            : friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.indigo,
      body: Center(
        child: _failed
            ? Padding(
                padding: const EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.cloud_off, color: Colors.white70, size: 64),
                  const SizedBox(height: 16),
                  Text(_message, textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 15)),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                      onPressed: _bootstrap,
                      icon: const Icon(Icons.refresh),
                      label: const Text('আবার চেষ্টা')),
                ]),
              )
            : const CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}
