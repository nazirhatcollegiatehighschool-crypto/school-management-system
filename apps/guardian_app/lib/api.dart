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
    sync.onReconnected = () {
      // Re-connect: re-pull the essential data so the local cache gets updated.
      unawaited(preloadEssential());
    };
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

  /// True when a mutation was stored on-device (offline) instead of sent.
  static bool isQueued(dynamic r) => r is Map && r['offline_queued'] == true;

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

  /// Connectivity probe for the Server-URL setting: raw GET, no auth/cache.
  static Future<bool> testHealth(String base) async {
    try {
      final res = await http
          .get(Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}/api/health'))
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<dynamic> get(String path) async {
    // Offline-first: serve the locally stored copy immediately instead of
    // waiting for a slow network timeout.
    if (sync.isOffline) {
      final cached = sync.cacheGet(path);
      if (cached != null) return jsOne(cached);
    }
    // Server known-down (recent probe failed): don't hang 25s, serve cache.
    // Manual refresh paths use refreshCache(), which always re-probes.
    if (!sync.isOffline && sync.serverKnownDown()) {
      final cached = sync.cacheGet(path);
      if (cached != null) return jsOne(cached);
    }
    try {
      final res = await http
          .get(Uri.parse(Config.api + path), headers: _headers)
          .timeout(_timeout);
      final data = _handle(res);
      sync.markRequestOk();
      // keep a copy for offline reads
      unawaited(sync.cachePut(path, jsOne(data)));
      return data;
    } catch (e) {
      if (isNetworkError(e)) {
        sync.markRequestFailed();
        final cached = sync.cacheGet(path);
        if (cached != null) return jsOne(cached);
      }
      rethrow;
    }
  }

  /// Accurate user-facing message for a failed mutation: distinguishes
  /// "no internet on the phone" from "internet OK but school server
  /// unreachable (laptop off / URL changed)".
  static String failureMessage({required String queuedAction}) {
    if (sync.isOffline) {
      return 'ইন্টারনেট নেই — $queuedAction ফোনে সেভ আছে, online হলেই server-এ যাবে';
    }
    return 'Server-এ পৌঁছানো যাচ্ছে না (ইন্টারনেট আছে) — $queuedAction ফোনে সেভ আছে; laptop server / Server URL ঠিক করে আবার চেষ্টা করুন';
  }

  static Future<dynamic> post(String path, [Map<String, dynamic>? body]) async {
    try {
      final res = await http
          .post(Uri.parse(Config.api + path), headers: _headers, body: jsonEncode(body ?? {}))
          .timeout(_timeout);
      final data = _handle(res);
      sync.markRequestOk();
      return data;
    } catch (e) {
      if (isNetworkError(e)) {
        sync.markRequestFailed();
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
      final data = _handle(res);
      sync.markRequestOk();
      return data;
    } catch (e) {
      if (isNetworkError(e)) {
        sync.markRequestFailed();
        await sync.enqueue('PUT', path, body);
        return {'offline_queued': true};
      }
      rethrow;
    }
  }

  static Future<dynamic> delete(String path) async {
    try {
      final res = await http
          .delete(Uri.parse(Config.api + path), headers: _headers)
          .timeout(_timeout);
      final data = _handle(res);
      sync.markRequestOk();
      return data;
    } catch (e) {
      if (isNetworkError(e)) {
        sync.markRequestFailed();
        await sync.enqueue('DELETE', path, null);
        return {'offline_queued': true};
      }
      rethrow;
    }
  }

  /// Fire-and-forget entry point for screens: preload essential datasets.
  static void kickstartPreload() => unawaited(preloadEssential());

  static Future<Map<String, int>> flushOffline() => sync.flush();

  static bool _preloading = false;

  /// Download & store the essential datasets (profile, every child's exam
  /// events + latest published marksheet/result-card, routine, notifications)
  /// into the offline cache. Runs on first login, on app start, and again
  /// whenever connectivity returns. Errors are ignored — cached data is used
  /// as the offline fallback.
  static Future<void> preloadEssential() async {
    if (_preloading || token == null) return;
    _preloading = true;
    try {
      final profile = await get('/guardian/profile').catchError((_) {});
      final students = (profile != null && profile is Map && profile['students'] is List)
          ? (profile['students'] as List)
          : const <dynamic>[];
      for (final st in students.take(4)) {
        final id = (st is Map ? st['id'] : st)?.toString();
        if (id == null) continue;
        try {
          final events = await get('/guardian/student/$id/exam-events');
          if (events is List && events.isNotEmpty) {
            final eid = events.first['id'].toString();
            unawaited(get('/guardian/student/$id/marksheet?event_id=$eid').catchError((_) {}));
            unawaited(get('/guardian/student/$id/result-card?event_id=$eid').catchError((_) {}));
          }
        } catch (_) {}
      }
      await Future.wait([
        get('/routine/student').catchError((_) {}),
        get('/guardian/notifications').catchError((_) {}),
      ]);
    } finally {
      _preloading = false;
    }
  }

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