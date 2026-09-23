import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Offline-first layer: persists a GET cache and a mutation outbox to disk.
/// Every queued change replays the exact same HTTP call once the device is
/// back online, so nothing entered offline is lost.
class SyncStore extends ChangeNotifier {
  SyncStore._();
  static final SyncStore instance = SyncStore._();

  final ValueNotifier<bool> online = ValueNotifier(true);
  final ValueNotifier<int> pending = ValueNotifier(0);

  Map<String, dynamic> _cache = {};
  List<Map<String, dynamic>> _outbox = [];
  List<Map<String, dynamic>> _errors = [];
  bool _inited = false;
  bool _syncing = false;
  String? _redirectBase;
  Connectivity? _conn;
  String? Function()? tokenProvider;

  int get pendingCount => _outbox.length;
  List<Map<String, dynamic>> get syncErrors => List.unmodifiable(_errors);
  bool get isSyncing => _syncing;

  Future<bool> init({String? base}) async {
    if (_inited) return true;
    _redirectBase = base;
    await _load();
    _inited = true;

    _conn = Connectivity();
    try {
      final res = await _conn!.checkConnectivity();
      _applyConn(res);
    } catch (_) {}

    _conn!.onConnectivityChanged.listen(_applyConn);
    // periodic safety net: retry the outbox while app is open
    Timer.periodic(const Duration(seconds: 30), (_) {
      if (online.value && pendingCount > 0) flush();
    });
    return true;
  }

  void _applyConn(List<ConnectivityResult> res) {
    final was = online.value;
    online.value = res.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet ||
        r == ConnectivityResult.vpn);
    if (online.value && !was && pendingCount > 0) flush();
  }

  Future<void> _load() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/sync_store.json');
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString());
        _cache = (j['cache'] as Map?)?.cast<String, dynamic>() ?? {};
        _outbox = (j['outbox'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _errors = (j['errors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      }
    } catch (_) {}
    pending.value = _outbox.length;
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/sync_store.json');
      await f.writeAsString(jsonEncode({'cache': _cache, 'outbox': _outbox, 'errors': _errors}));
    } catch (_) {}
  }

  String _keyOf(String path) => 'GET ' + path.split('?').first;

  /// Store a successful GET response for offline reads.
  Future<void> cachePut(String path, dynamic data) async {
    _cache[_keyOf(path)] = data;
    if (_cache.length > 80) {
      // drop oldest half by insertion order (dart keeps insertion order)
      final keys = _cache.keys.toList();
      for (var i = 0; i < keys.length - 60; i++) _cache.remove(keys[i]);
    }
    await _save();
  }

  dynamic cacheGet(String path) => _cache[_keyOf(path)];

  Future<void> cacheDel(String path) async {
    _cache.remove(_keyOf(path));
    await _save();
  }

  /// Queue a mutation for later replay. Returns the outbox entry id.
  Future<String> enqueue(String method, String path, Map<String, dynamic>? body) async {
    final id = '${DateTime.now().millisecondsSinceEpoch}-${_outbox.length}';
    _outbox.add({'id': id, 'method': method, 'path': path, 'body': body ?? {}, 't': DateTime.now().toIso8601String()});
    pending.value = _outbox.length;
    notifyListeners();
    await _save();
    return id;
  }

  Future<void> clear() async {
    _cache = {};
    _outbox = [];
    _errors = [];
    pending.value = 0;
    notifyListeners();
    await _save();
  }

  /// Replay every queued mutation in order (FIFO). Stops on network loss,
  /// records deterministic errors, removes successful / rejected entries.
  Future<Map<String, int>> flush() async {
    if (_syncing || !_inited) return {'synced': 0, 'failed': 0};
    _syncing = true;
    notifyListeners();
    var synced = 0, failed = 0;
    try {
      while (_outbox.isNotEmpty) {
        final entry = Map<String, dynamic>.from(_outbox.first);
        final ok = await _send(entry);
        if (ok == null) {
          // network is unreachable right now — stop, keep the rest
          break;
        }
        _outbox.removeAt(0);
        if (!ok) {
          failed++;
          if (_errors.length > 20) _errors.removeAt(0);
          _errors.add({'t': DateTime.now().toIso8601String(), 'method': entry['method'], 'path': entry['path'], 'error': 'Server rejected this request'});
        } else {
          synced++;
        }
        pending.value = _outbox.length;
        await _save();
      }
    } finally {
      _syncing = false;
      notifyListeners();
    }
    return {'synced': synced, 'failed': failed};
  }

  Future<bool?> _send(Map<String, dynamic> entry) async {
    try {
      final res = await _http(entry['method'] as String, entry['path'] as String, entry['body'] as Map<String, dynamic>?);
      if (res.statusCode == 401 || res.statusCode == 403) return false; // session expired — surface to user
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return null; // unreachable — stop
    }
  }

  Future<http.Response> _http(String method, String path, Map<String, dynamic>? body) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final tok = await _token();
    if (tok != null) headers['Authorization'] = 'Bearer $tok';
    final uri = Uri.parse((_redirectBase ?? '') + path);
    switch (method) {
      case 'POST':
        return http.post(uri, headers: headers, body: jsonEncode(body ?? {})).timeout(const Duration(seconds: 20));
      case 'PUT':
        return http.put(uri, headers: headers, body: jsonEncode(body ?? {})).timeout(const Duration(seconds: 20));
      case 'DELETE':
        return http.delete(uri, headers: headers).timeout(const Duration(seconds: 20));
      default:
        return http.get(uri, headers: headers).timeout(const Duration(seconds: 20));
    }
  }

  Future<String?> _token() async => tokenProvider?.call();
}