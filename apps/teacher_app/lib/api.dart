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

  static Future<dynamic> get(String path) async {
    try {
      final res = await http
          .get(Uri.parse(Config.api + path), headers: _headers)
          .timeout(_timeout);
      final data = _handle(res);
      // keep a copy for offline reads
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
      return _handle(res);
    } catch (e) {
      if (isNetworkError(e)) {
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
      return _handle(res);
    } catch (e) {
      if (isNetworkError(e)) {
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

  static Future<Map<String, int>> flushOffline() => sync.flush();

  static dynamic _handle(http.Response res) {
    final data = res.body.isEmpty ? {} : jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    throw Exception(data['error'] ?? 'Request failed (${res.statusCode})');
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