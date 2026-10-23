import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';
import 'sync_store.dart';

class Api {
  static String? token;
  static const Duration _timeout = Duration(seconds: 30);
  static const _tokenKey = 'auth_token';

  /// Raw server root for browser-opened downloads (PDFs). See Config.
  static String get downloadBase => Config.downloadBase;

  /// Offline read/write layer. Every successful GET is cached; every mutation
  /// that fails on the network is queued and replayed when connectivity returns.
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
    await sync.clear(); // cached data belongs to the previous session
  }

  static bool isNetworkError(Object e) {
    final s = e.toString();
    return e is SocketException || e is TimeoutException ||
        s.contains('SocketException') || s.contains('TimeoutException') ||
        s.contains('Connection refused') || s.contains('HandshakeException') ||
        s.contains('ClientException') || s.contains('connect failed');
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
          .timeout(const Duration(seconds: 20));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<dynamic> get(String path, {Map<String, String>? queryParams}) async {
    final uri = Uri.parse(Config.api + path).replace(queryParameters: queryParams);
    final cachePath = queryParams == null || queryParams.isEmpty
        ? path
        : '$path?${(queryParams.keys.toList()..sort()).map((k) => '${Uri.encodeQueryComponent(k)}=${Uri.encodeQueryComponent(queryParams[k]!)}').join('&')}';
    // Offline-first: serve the locally stored copy immediately instead of
    // waiting for a slow network timeout.
    if (sync.isOffline) {
      final cached = sync.cacheGet(cachePath);
      if (cached != null) return jsOne(cached);
    }
    // Server known-down (recent probe failed): don't hang 25s, serve cache.
    // Manual refresh paths use refreshCache(), which always re-probes.
    if (!sync.isOffline && sync.serverKnownDown()) {
      final cached = sync.cacheGet(cachePath);
      if (cached != null) return jsOne(cached);
    }
    try {
      http.Response res;
      try {
        res = await http
            .get(uri, headers: _conditionalHeaders(cachePath))
            .timeout(_timeout);
      } catch (e) {
        if (!isNetworkError(e)) rethrow;
        // transient: wait ~1.2s (+jitter) then retry exactly once
        await Future.delayed(Duration(
            milliseconds: 1000 + (DateTime.now().microsecond % 400)));
        res = await http
            .get(uri, headers: _conditionalHeaders(cachePath))
            .timeout(_timeout);
      }
      if (res.statusCode == 304) {
        sync.markRequestOk();
        final cached = sync.cacheGet(cachePath);
        if (cached != null) return jsOne(cached);
        // A validator without its payload can occur after storage cleanup;
        // retry once unconditionally so the UI never receives an empty 304.
        res = await http.get(uri, headers: _headers).timeout(_timeout);
      }
      final data = _handle(res);
      sync.markRequestOk();
      // keep a copy for offline reads
      unawaited(sync.cachePut(cachePath, jsOne(data), etag: res.headers['etag']));
      return data;
    } catch (e) {
      if (isNetworkError(e)) {
        sync.markRequestFailed();
        final cached = sync.cacheGet(cachePath);
        if (cached != null) return jsOne(cached);
      }
      rethrow;
    }
  }

  static Map<String, String> _conditionalHeaders(String path) {
    final etag = sync.etagFor(path);
    return etag == null ? _headers : {..._headers, 'If-None-Match': etag};
  }

  /// Accurate user-facing message for a failed mutation: distinguishes
  /// "no internet on the phone" from "internet OK but school server
  /// unreachable (laptop off / URL changed)".
  static String failureMessage({required String queuedAction}) {
    if (sync.isOffline) {
      return 'ইন্টারনেট নেই — $queuedAction ফোনে সেভ আছে, online হলেই server-এ যাবে';
    }
    return 'Server-এ পৌঁছানো যাচ্ছে না (ইন্টারনেট আছে) — $queuedAction ফোনে সেভ আছে; একটু পরে আবার চেষ্টা করুন';
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

  static Future<dynamic> delete(String path, {Map<String, dynamic>? body}) async {
    try {
      final res = await http
          .delete(Uri.parse(Config.api + path), headers: _headers,
              body: body == null ? null : jsonEncode(body))
          .timeout(_timeout);
      final data = _handle(res);
      sync.markRequestOk();
      return data;
    } catch (e) {
      if (isNetworkError(e)) {
        sync.markRequestFailed();
        await sync.enqueue('DELETE', path, body);
        return {'offline_queued': true};
      }
      rethrow;
    }
  }

  /// Replay queued offline changes against the server.
  static Future<Map<String, int>> flushOffline() => sync.flush();

  /// Fire-and-forget entry point for screens: preload essential datasets.
  static void kickstartPreload() => unawaited(preloadEssential());

  static bool _preloading = false;

  /// Download & store the essential datasets into the offline cache. Called
  /// on first login, on app start (when a session exists), and every time
  /// connectivity comes back. Errors are ignored — online reads fall back to
  /// whatever was already cached.
  static Future<void> preloadEssential() async {
    if (_preloading || token == null) return;
    _preloading = true;
    try {
      await Future.wait([
        get('/admin/stats').catchError((_) {}),
        get('/admin/teachers').catchError((_) {}),
        get('/admin/classes').catchError((_) {}),
        get('/admin/subjects').catchError((_) {}),
        get('/admin/students').catchError((_) {}),
        get('/routine/teacher/mine').catchError((_) {}),
        get('/routine/slots').catchError((_) {}),
      ]);
    } finally {
      _preloading = false;
    }
  }

  static dynamic _handle(http.Response res) {
    final data = res.body.isEmpty ? {} : jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw ApiAuthException(data['error'] ?? 'সেশন শেষ। আবার লগইন করুন।');
    }
    throw Exception(data['error'] ?? 'Request failed (${res.statusCode})');
  }

  /// True only for real auth failures (401/403). Server 5xx / parse errors
  /// are NOT auth failures and must never clear the stored token.
  static bool isAuthError(Object e) => e is ApiAuthException;
}

/// Thrown when the server rejects the token (HTTP 401/403).
class ApiAuthException implements Exception {
  final String message;
  ApiAuthException(this.message);
  @override
  String toString() => message;
}

/// Deep-copy a decoded JSON value before storing it, so later app mutations of
/// the same object can't corrupt the cache.
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
