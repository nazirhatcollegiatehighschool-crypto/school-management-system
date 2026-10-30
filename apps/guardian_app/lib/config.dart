import 'package:shared_preferences/shared_preferences.dart';

/// Server base URL. Build-time default via --dart-define=API_URL=...,
/// runtime-overridable from the app's Server settings (survives restarts,
/// so server URL changes never need a rebuild).
class Config {
  static const String _defined = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://school-management-system-mobile-api.vercel.app',
  );
  static const String _retiredUrl =
      'https://school-management-system-brown-mu.vercel.app';
  static String _override = '';

  static String get serverUrl => _override.isNotEmpty ? _override : _defined;
  static bool get hasOverride => _override.isNotEmpty;
  static String get api => '$serverUrl/api';

  static const String _key = 'server_url_override';

  static Future<void> loadOverride() async {
    try {
      final p = await SharedPreferences.getInstance();
      final saved = (p.getString(_key) ?? '').trim().replaceAll(
        RegExp(r'/+$'),
        '',
      );
      if (saved == _retiredUrl) {
        await p.remove(_key);
        _override = '';
        return;
      }
      _override = saved;
    } catch (_) {}
  }

  static Future<void> setOverride(String url) async {
    _override = url.trim().replaceAll(RegExp(r'/+$'), '');
    try {
      final p = await SharedPreferences.getInstance();
      if (_override.isEmpty) {
        await p.remove(_key);
      } else {
        await p.setString(_key, _override);
      }
    } catch (_) {}
  }
}
