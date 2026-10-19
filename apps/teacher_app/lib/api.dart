import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';
import 'sync_store.dart';

class Api {
  static String? token;
  static const Duration _timeout = Duration(seconds: 25);
  static const _tokenKey = 'auth_token';

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
  static Map<String, String> get _probeHeaders => const {};

  static Future<bool> testHealth(String base) async {
    try {
      final res = await http
          .get(Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}/api/health'),
              headers: _probeHeaders)
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

  static Future<dynamic> promoteReview(int classId, int sessionId) async {
    return get('/promote/review?class_id=$classId&session_id=$sessionId');
  }

  static Future<dynamic> promoteExecute(Map<String, dynamic> body) async {
    return post('/promote/execute', body);
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

  /// Replay queued offline changes against the server.
  /// Sends an OCR capture to /teacher/ocr/recognize.
  ///
  /// The backend OCR route has NO multer — it reads base64 out of a JSON body
  /// (`image_base64`), so instead of a raw multipart stream we base64-encode the
  /// image bytes client-side. This keeps the deployed Google-Vision endpoint
  /// reachable without adding any backend upload dependency.
  static Future<dynamic> postMultipart(
      String path, Map<String, dynamic> body) async {
    Map<String, dynamic> out = {};
    for (final e in body.entries) {
      if (e.key == 'image' && e.value != null) {
        final Uint8List bytes = await _imageBytes(e.value);
        if (bytes.isNotEmpty) out['image_base64'] = base64Encode(bytes);
      } else {
        out[e.key] = e.value;
      }
    }
    return post(path, out);
  }

  /// Real multipart file upload (images, PDFs) with auth. Returns decoded JSON.
  static Future<dynamic> uploadFile(String path, String filePath, {String field = 'file'}) async {
    try {
      final rq = http.MultipartRequest('POST', Uri.parse(Config.api + path));
      if (token != null) rq.headers['Authorization'] = 'Bearer $token';
      rq.files.add(await http.MultipartFile.fromPath(field, filePath));
      final streamed = await rq.send().timeout(const Duration(seconds: 90));
      final body = await streamed.stream.bytesToString();
      final data = body.isEmpty ? {} : jsonDecode(body);
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        throw Exception((data is Map && data['error'] != null) ? data['error'] : 'Upload failed (${streamed.statusCode})');
      }
      sync.markRequestOk();
      return data;
    } catch (e) {
      if (isNetworkError(e)) rethrow;
      rethrow;
    }
  }

  /// Coerce either an XFile (image_picker) or a plain file path into bytes.
  static Future<Uint8List> _imageBytes(dynamic image) async {
    try {
      dynamic bytes;
      try {
        bytes = await image.readAsBytes();
      } catch (_) {
        bytes = null;
      }
      if (bytes is Uint8List) return bytes;
      if (bytes is List<int>) return Uint8List.fromList(bytes);
      final path = image is String ? image : image.path;
      if (path is String && path.isNotEmpty) {
        return await File(path).readAsBytes();
      }
    } catch (_) {}
    return Uint8List(0);
  }

  /// Fire-and-forget entry point for screens: preload essential datasets.
  static void kickstartPreload() => unawaited(preloadEssential());

  static Future<Map<String, int>> flushOffline() => sync.flush();

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
        get('/teacher/profile').catchError((_) {}),
        get('/teacher/exams').catchError((_) {}),
        get('/teacher/events').catchError((_) {}),
        get('/teacher/subjects').catchError((_) {}),
        get('/teacher/homework').catchError((_) {}),
        get('/routine/teacher/mine').catchError((_) {}),
        get('/routine/teacher/subjects').catchError((_) {}),
        get('/routine/slots').catchError((_) {}),
        get('/teacher/class-teacher-requests').catchError((_) {}),
        get('/teacher/directory').catchError((_) {}),
        get('/teacher/attendance?date=${DateTime.now().toIso8601String().substring(0, 10)}').catchError((_) {}),
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

  /// True when a mutation was stored on-device (offline) instead of sent.
  /// Data WILL reach the server automatically when internet returns.
  static bool isQueued(dynamic r) => r is Map && r['offline_queued'] == true;

  /// Instant on-device read: permanent disk cache (survives restarts, cleared
  /// only on logout). Returns null when nothing was ever cached.
  static dynamic peekCache(String path) {
    try {
      return jsOne(sync.cacheGet(path));
    } catch (_) {
      return null;
    }
  }

  /// Background refresh: fetch from network and update the permanent cache.
  /// Never throws — callers paint cache first, then call this to revalidate.
  static Future<dynamic> refreshCache(String path) async {
    try {
      final res = await http
          .get(Uri.parse(Config.api + path), headers: _headers)
          .timeout(_timeout);
      final data = _handle(res);
      sync.markRequestOk();
      unawaited(sync.cachePut(path, jsOne(data)));
      return data;
    } catch (_) {
      sync.markRequestFailed();
      return null;
    }
  }

  /// Cache-first page loader: paints on-device data instantly (no spinner),
  /// then silently refreshes from network. Calls [onData] with cached data
  /// first (if any), then with fresh data. Throws only when there is neither
  /// cache nor network — so screens show error UI only when truly empty.
  static Future<void> loadCachedFirst(String path, void Function(dynamic data) onData) async {
    final c = peekCache(path);
    if (c != null) {
      try { onData(c); } catch (_) {}
    }
    final fresh = await refreshCache(path);
    if (fresh != null) {
      try { onData(fresh); } catch (_) {}
    } else if (c == null) {
      final data = await get(path); // throws the real error
      try { onData(data); } catch (_) {}
    }
  }
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