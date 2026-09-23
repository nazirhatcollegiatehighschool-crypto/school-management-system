import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';
import 'sync_store.dart';

class Api {
  static String? token;
  static const Duration _timeout = Duration(seconds: 25);
  static const _tokenKey = 'auth_token';
  static const _cachePrefix = 'cache_';

  static final SyncStore sync = SyncStore.instance;

  static Future<void> init() async {
    sync.tokenProvider = () => token;
    await sync.init(base: Config.api);
  }

  static Future<void> saveToken(String t) async {
    token = t;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, t);
  }

  static Future<bool> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString(_tokenKey);
    if (t == null || t.isEmpty) return false;
    token = t;
    return true;
  }

  static Future<void> clearToken() async {
    token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await sync.clear();
  }

  static bool isNetworkError(Object e) {
    final s = e.toString();
    return e is SocketException || e is TimeoutException ||
        s.contains('SocketException') || s.contains('TimeoutException') ||
        s.contains('Connection refused') || s.contains('HandshakeException') ||
        s.contains('ClientException') || s.contains('connect failed');
  }

  static Future<void> cachePut(String key, dynamic data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cachePrefix + key, jsonEncode(data));
    } catch (_) {}
  }

  static Future<dynamic> cacheGet(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cachePrefix + key);
      return raw == null ? null : jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  static Future<dynamic> get(String path) async {
    try {
      final res = await http
          .get(Uri.parse(Config.api + path), headers: _headers)
          .timeout(_timeout);
      final data = _handle(res);
      unawaited(sync.cachePut(path, jsOne(data)));
      return data;
    } catch (e) {
      if (isNetworkError(e)) {
        final cached = sync.cacheGet(path);
        if (cached != null) return jsOne(cached);
      }
      rethrow;
    }
  }

  static Future<dynamic> post(String path, [Map<String, dynamic>? body]) async {
    try {
      final res = await http
          .post(Uri.parse(Config.api + path), headers: _headers, body: jsonEncode(body ?? {}))
          .timeout(_timeout);
      return _handle(res);
    } catch (e) {
      if (isNetworkError(e)) {
        await sync.enqueue('POST', path, body);
        return {'offline_queued': true};
      }
      rethrow;
    }
  }

  static Future<dynamic> put(String path, [Map<String, dynamic>? body]) async {
    try {
      final res = await http
          .put(Uri.parse(Config.api + path), headers: _headers, body: jsonEncode(body ?? {}))
          .timeout(_timeout);
      return _handle(res);
    } catch (e) {
      if (isNetworkError(e)) {
        await sync.enqueue('PUT', path, body);
        return {'offline_queued': true};
      }
      rethrow;
    }
  }

  static Future<Map<String, int>> flushOffline() => sync.flush();

  static dynamic _handle(http.Response res) {
    final data = res.body.isEmpty ? {} : jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    throw Exception(data['error'] ?? 'Request failed (${res.statusCode})');
  }
}

dynamic jsOne(dynamic v) {
  if (v == null) return null;
  try {
    return jsonDecode(jsonEncode(v));
  } catch (_) {
    return null;
  }
}

String friendlyError(Object e) {
  final s = e.toString();
  if (e is SocketException || e is TimeoutException || s.contains('SocketException') || s.contains('TimeoutException')) {
    return 'কানেকশন পাওয়া যায়নি। ইন্টারনেট চেক করে আবার চেষ্টা করুন।';
  }
  return s.replaceFirst('Exception: ', '').replaceFirst('HandshakeException', 'নিরাপদ কানেকশন ব্যর্থ');
}