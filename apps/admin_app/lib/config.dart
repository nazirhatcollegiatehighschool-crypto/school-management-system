import 'package:shared_preferences/shared_preferences.dart';

/// Server base URL. Build-time default via --dart-define=API_URL=...,
/// runtime-overridable from the app's Server settings (survives restarts,
/// so LAN IP / tunnel URL changes never need a rebuild).
class Config {
  static const String _defined = String.fromEnvironment('API_URL', defaultValue: 'https://alphabet-stardust-exceeding.ngrok-free.dev');
  static String _override = '';

  static String get serverUrl => _override.isNotEmpty ? _override : _defined;
  static String get api => '$serverUrl/api';
  // Raw server root (no /api) — used for browser-opened file downloads
  // (class PDFs, result-card PDFs): launchUrl opens the real URL, and the
  // ngrok warning is a browser page the user can pass, unlike in-app JSON.
  static String get downloadBase => serverUrl;

  static const String _key = 'server_url_override';

  static Future<void> loadOverride() async {
    try {
      final p = await SharedPreferences.getInstance();
      _override = (p.getString(_key) ?? '').trim().replaceAll(RegExp(r'/+$'), '');
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
