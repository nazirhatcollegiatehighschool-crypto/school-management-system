import 'package:shared_preferences/shared_preferences.dart';

/// Server base URL. Build-time default via --dart-define=API_URL=...,
/// runtime-overridable from the app's Server settings (survives restarts,
/// so server URL changes never need a rebuild).
class Config {
  static const String productionUrl =
      'https://school-management-system-brown-mu.vercel.app';
  static const String _defined = String.fromEnvironment(
    'API_URL',
    defaultValue: productionUrl,
  );
  static const Set<String> _retiredUrls = {
    'https://school-management-system-mobile-api.vercel.app',
    'https://school-management-system-jewel-5c50.vercel.app',
  };
  static String _override = '';

  static String get serverUrl => _override.isNotEmpty ? _override : _defined;
  static bool get hasOverride => _override.isNotEmpty;
  static String get api => '$serverUrl/api';
  // Raw server root (no /api) — used for browser-opened file downloads
  // (class PDFs, result-card PDFs): launchUrl opens the real URL directly.
  static String get downloadBase => serverUrl;

  static const String _key = 'server_url_override';

  static Future<void> loadOverride() async {
    try {
      final p = await SharedPreferences.getInstance();
      final saved = (p.getString(_key) ?? '').trim().replaceAll(
        RegExp(r'/+$'),
        '',
      );
      if (_retiredUrls.contains(saved)) {
        await p.remove(_key);
        _override = '';
        return;
      }
      _override = saved == _defined ? '' : saved;
    } catch (_) {}
  }

  static Future<void> setOverride(String url) async {
    final saved = url.trim().replaceAll(RegExp(r'/+$'), '');
    final override = saved == _defined || saved == productionUrl ? '' : saved;
    try {
      final p = await SharedPreferences.getInstance();
      if (override.isEmpty) {
        await p.remove(_key);
      } else {
        await p.setString(_key, override);
      }
    } catch (_) {}
    _override = override;
  }
}
