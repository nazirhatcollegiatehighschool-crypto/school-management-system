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
    final hasToken = await Api.loadToken();
    if (!hasToken) {
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
      return;
    }
    Api.kickstartPreload(); // refresh stored essential data in the background
    try {
      final r = await Api.get('/guardian/profile');
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomeScreen(students: r['students'])));
    } catch (e) {
      // Only a REAL auth failure (401/403) invalidates the session. A
      // transient network blip OR a server 5xx (e.g. Vercel cold-start)
      // must NOT log the guardian out — offer in-app retry instead.
      if (Api.isAuthError(e)) {
        await Api.clearToken();
      }
      if (!mounted) return;
      setState(() { _message = Api.isAuthError(e) ? friendlyError(e) : 'সার্ভারে পৌঁছানো যায়নি। ইন্টারনেট চেক করে আবার চেষ্টা করুন।'; _failed = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _failed
            ? Padding(
                padding: const EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.cloud_off, color: Colors.indigo, size: 64),
                  const SizedBox(height: 16),
                  Text(_message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                      onPressed: _bootstrap,
                      icon: const Icon(Icons.refresh),
                      label: const Text('আবার চেষ্টা')),
                ]),
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}