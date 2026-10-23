import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;import 'package:path_provider/path_provider.dart';
import 'config.dart';

/// Three-state connection health used by the status banner + request layer.
class ConnState {
  static const int online = 0;
  static const int reconnecting = 1;
  static const int offline = 2;
}

/// Offline-first layer: persists a GET cache and a mutation outbox to disk.
/// Every queued change replays the exact same HTTP call once the device is
/// back online, so nothing entered offline is lost.
class SyncStore extends ChangeNotifier {
  SyncStore._();
  static final SyncStore instance = SyncStore._();

  final ValueNotifier<bool> online = ValueNotifier(true);
  final ValueNotifier<int> pending = ValueNotifier(0);
  // True connectivity (wifi/mobile) vs ACTUAL server reachability are
  // different things: the phone can have internet while the school server
  // (production server) is unreachable. `serverUp` tracks the latter via
  // lightweight /api/health probes so the UI never shows a misleading
  // "no internet" message when the internet is fine.
  final ValueNotifier<bool> serverUp = ValueNotifier(true);
  DateTime? _lastProbeFail;
  Future<bool>? _probeFlight;

  // ── Connection state machine ──────────────────────────────────────
  // Instead of flipping straight to Offline after ONE failed probe (which
  // happens constantly on mobile data during handoff / cold starts), we
  // track three states:
  //   online       — last probe/request succeeded
  //   reconnecting — a probe failed once; we retry with backoff before
  //                  declaring offline. The UI shows a soft "reconnecting".
  //   offline      — connectivity is genuinely gone, OR repeated probes
  //                  failed. Only then do we show "no internet".
  final ValueNotifier<int> connState = ValueNotifier(ConnState.online);
  int _consecutiveProbeFails = 0;

  /// How many failed probes before we accept "server unreachable".
  static const int _failsBeforeOffline = 3;

  Map<String, dynamic> _cache = {};
  // HTTP validators let the server return 304 when a cached response has not
  // changed. This keeps the durable payload on-device and avoids re-downloading
  // unchanged school datasets on every screen visit.
  Map<String, String> _etags = {};
  List<Map<String, dynamic>> _outbox = [];
  List<Map<String, dynamic>> _errors = [];
  // Optimistic overlays: queued mutations are ALSO mirrored onto the on-device
  // read cache immediately, so an offline add/edit shows up in the UI at once
  // (tagged pending) instead of only after a network round-trip. Keyed by the
  // GET path they affect. Dropped once the mutation actually syncs (then a
  // fresh server pull replaces the cache entry with the real row).
  Map<String, List<Map<String, dynamic>>> _overlays = {};
  bool _inited = false;
  bool _syncing = false;
  String? _redirectBase;
  Connectivity? _conn;
  String? Function()? tokenProvider;
  /// Called whenever connectivity returns (offline -> online). Apps use this
  /// to refresh cached GET data so the latest server data gets stored again.
  void Function()? onReconnected;

  int get pendingCount => _outbox.length;
  List<Map<String, dynamic>> get syncErrors => List.unmodifiable(_errors);
  bool get isSyncing => _syncing;

  bool get isOffline => !online.value;

  /// Server known-down only counts when repeated probes failed recently (60s),
  /// so a stale flag can never wedge the app offline forever, and a single
  /// transient failure never flips us straight to offline.
  bool serverKnownDown() {
    if (serverUp.value) return false;
    if (_consecutiveProbeFails < _failsBeforeOffline) return false;
    final f = _lastProbeFail;
    if (f == null) return false;
    return DateTime.now().difference(f).inSeconds < 60;
  }

  /// Lightweight reachability probe. Coalesces concurrent callers into one
  /// flight. Never throws. Uses a generous timeout so a slow mobile-data
  /// handshake or a serverless cold start does not look like an outage.
  Future<bool> probeServer({Duration timeout = const Duration(seconds: 20)}) {
    if (_probeFlight != null) return _probeFlight!;
    final fut = _probeServerInner(timeout);
    _probeFlight = fut;
    fut.whenComplete(() => _probeFlight = null);
    return fut;
  }

  /// Retry the probe with bounded exponential backoff + jitter before giving
  /// up, so a single blip doesn't mark the server down. Returns true on the
  /// first success.
  Future<bool> probeServerWithRetry({int attempts = 3}) async {
    bool ok = false;
    for (var i = 0; i < attempts; i++) {
      ok = await probeServer(timeout: Duration(seconds: 20 + i * 10));
      if (ok) return true;
      if (!online.value) return false; // device genuinely has no network
      // bounded exponential backoff with jitter: ~1s, ~2s, ~4s (+/- 40%)
      final base = 1000 * (1 << i);
      final jitter = (base * 0.4 * (DateTime.now().microsecond / 1000000)).round();
      await Future.delayed(Duration(milliseconds: base + jitter));
    }
    return false;
  }

  Future<bool> _probeServerInner(Duration timeout) async {
    try {
      final res = await http
          .get(Uri.parse('${Config.api}/health'))
          .timeout(timeout);
      final ok = res.statusCode >= 200 && res.statusCode < 300;
      _markServer(ok);
      return ok;
    } catch (_) {
      _markServer(false);
      return false;
    }
  }

  void _markServer(bool ok) {
    if (ok) {
      _consecutiveProbeFails = 0;
      _lastProbeFail = null;
    } else {
      _consecutiveProbeFails++;
      _lastProbeFail = DateTime.now();
    }
    // serverUp drives the request layer's cache-first behaviour: it is only
    // "down" once we've failed enough times to be confident.
    final up = _consecutiveProbeFails < _failsBeforeOffline;
    if (serverUp.value != up) {
      serverUp.value = up;
    }
    _recomputeConnState();
    notifyListeners();
  }

  /// Derive the 3-state banner state from connectivity + server health.
  void _recomputeConnState() {
    int next;
    if (!online.value) {
      next = ConnState.offline;
    } else if (serverUp.value) {
      next = ConnState.online;
    } else if (_consecutiveProbeFails < _failsBeforeOffline) {
      next = ConnState.reconnecting;
    } else {
      next = ConnState.offline;
    }
    if (connState.value != next) connState.value = next;
  }

  /// Call when a request fails with a network-level error. A single failed
  /// request is NOT proof the server is down — it only nudges the probe. We
  /// count it toward the offline threshold so several real failures in a row
  /// do flip the state, but one blip does not.
  void markRequestFailed() {
    if (online.value && serverUp.value) {
      // first failure: show "reconnecting" softly, kick a probe in the bg
      connState.value = ConnState.reconnecting;
      unawaited(probeServer());
    } else {
      _markServer(false);
    }
  }

  /// Call on any successful API response — a real request succeeding is the
  /// strongest possible evidence the server is reachable.
  void markRequestOk() {
    if (!serverUp.value || connState.value != ConnState.online) {
      _markServer(true);
    }
  }

  /// Re-check connectivity + server reachability (call on app resume so a
  /// stale offline/server-down flag never wedges the banner forever).
  Future<void> recheck() async {
    try {
      final res = await _conn?.checkConnectivity();
      if (res != null) _applyConn(res);
    } catch (_) {}
    if (!online.value) {
      _recomputeConnState();
      return;
    }
    await probeServerWithRetry();
  }

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
      // self-heal: re-probe while marked down/reconnecting so the status
      // clears on its own once the server recovers.
      if (online.value && connState.value != ConnState.online) {
        probeServerWithRetry(attempts: 1);
      }
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
    if (online.value && !was) {
      // Connectivity returned: reset the failure streak and verify server.
      _consecutiveProbeFails = 0;
      if (pendingCount > 0) flush();
      unawaited(probeServerWithRetry(attempts: 2));
      onReconnected?.call();
    } else if (!online.value && was) {
      // Connectivity dropped: the device really is offline now.
      _consecutiveProbeFails = _failsBeforeOffline;
      _recomputeConnState();
    } else {
      _recomputeConnState();
    }
    notifyListeners();
  }

  Future<void> _load() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/sync_store.json');
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString());
        _cache = (j['cache'] as Map?)?.cast<String, dynamic>() ?? {};
        _etags = (j['etags'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ?? {};
        _outbox = (j['outbox'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _errors = (j['errors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final ov = j['overlays'];
        if (ov is Map) {
          _overlays = {};
          ov.forEach((k, v) {
            _overlays['$k'] = (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          });
        }
      }
    } catch (_) {}
    pending.value = _outbox.length;
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/sync_store.json');
      await f.writeAsString(jsonEncode({'cache': _cache, 'etags': _etags, 'outbox': _outbox, 'errors': _errors, 'overlays': _overlays}));
    } catch (_) {}
  }

  String _keyOf(String path) => 'GET $path';

  /// Store a successful GET response for offline reads.
  String? etagFor(String path) => _etags[_keyOf(path)];

  /// Store a successful GET response and its validator for later conditional reads.
  Future<void> cachePut(String path, dynamic data, {String? etag}) async {
    _cache[_keyOf(path)] = data;
    if (etag != null && etag.isNotEmpty) _etags[_keyOf(path)] = etag;

    if (_cache.length > 80) {
      // drop oldest half by insertion order (dart keeps insertion order)
      final keys = _cache.keys.toList();
      for (var i = 0; i < keys.length - 60; i++) {
        _cache.remove(keys[i]);
      }
    }
    await _save();
  }

  /// On-device GET, with any still-unsynced local edits overlaid on top.
  dynamic cacheGet(String path) {
    final base = _cache[_keyOf(path)];
    final ops = _overlays[path];
    if (ops == null || ops.isEmpty) return base;
    return _applyOverlays(base, ops);
  }

  Future<void> cacheDel(String path) async {
    _cache.remove(_keyOf(path));
    _etags.remove(_keyOf(path));
    await _save();
  }

  /// Queue a mutation for later replay. Returns the outbox entry id.
  /// [optimistic] lets the caller mirror the change onto the read cache now:
  ///   { 'cache': 'GET path', 'action': 'append'|'update'|'remove',
  ///     'idField': 'id', 'item': { ...row... } }
  Future<String> enqueue(String method, String path, Map<String, dynamic>? body,
      {Map<String, dynamic>? optimistic}) async {
    final id = '${DateTime.now().millisecondsSinceEpoch}-${_outbox.length}';
    final entry = {'id': id, 'method': method, 'path': path, 'body': body ?? {}, 't': DateTime.now().toIso8601String()};
    if (optimistic != null) entry['optimistic'] = optimistic;
    _outbox.add(entry);
    if (optimistic != null) {
      final cp = optimistic['cache'];
      final item = optimistic['item'];
      if (cp is String && item is Map) {
        (_overlays[cp] ??= []).add({
          'opId': id,
          'action': optimistic['action'] ?? 'append',
          'idField': optimistic['idField'] ?? 'id',
          'item': item,
        });
      }
    }
    pending.value = _outbox.length;
    notifyListeners();
    await _save();
    return id;
  }

  /// Number of still-unsynced local edits affecting a given GET path.
  int pendingFor(String path) => (_overlays[path] ?? const []).length;

  void _removeOverlay(String opId) {
    for (final k in _overlays.keys.toList()) {
      _overlays[k]!.removeWhere((o) => o['opId'] == opId);
      if (_overlays[k]!.isEmpty) _overlays.remove(k);
    }
  }

  dynamic _applyOverlays(dynamic base, List<Map<String, dynamic>> ops) {
    List list;
    if (base is List) {
      list = jsonDecode(jsonEncode(base)) as List;
    } else if (base == null) {
      if (!ops.every((o) => o['action'] == 'append')) return base;
      list = [];
    } else {
      return base;
    }
    for (final op in ops) {
      final action = '${op['action']}';
      final item = op['item'];
      if (item is! Map) continue;
      final idField = '${op['idField'] ?? 'id'}';
      final itemId = '${item[idField]}';
      if (action == 'append') {
        list.add(jsonDecode(jsonEncode(item)));
      } else if (action == 'update') {
        final i = list.indexWhere((e) => e is Map && '${e[idField]}' == itemId);
        if (i >= 0) { list[i] = jsonDecode(jsonEncode(item)); } else { list.add(jsonDecode(jsonEncode(item))); }
      } else if (action == 'remove') {
        list.removeWhere((e) => e is Map && '${e[idField]}' == itemId);
      }
    }
    return list;
  }

  Future<void> _resyncPath(String path) async {
    try {
      final res = await _http('GET', path, null);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = res.body.isEmpty ? null : jsonDecode(res.body);
        await cachePut(path, data);
      }
    } catch (_) {}
  }

  Future<void> clear() async {
    _cache = {};
    _etags = {};
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
        _removeOverlay(entry['id'] as String);
        if (!ok) {
          failed++;
          if (_errors.length > 20) _errors.removeAt(0);
          _errors.add({'t': DateTime.now().toIso8601String(), 'method': entry['method'], 'path': entry['path'], 'error': 'Server rejected this request'});
        } else {
          synced++;
          // Replace the optimistic cache entry with the server's real row.
          final opt = entry['optimistic'];
          if (opt is Map && opt['cache'] is String) {
            unawaited(_resyncPath(opt['cache'] as String));
          }
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
    // Always resolve the CURRENT server base (user may change Server URL
    // in settings after init — never replay to a stale host).
    String base = '';
    try {
      base = Config.api;
    } catch (_) {}
    if (base.isEmpty) base = _redirectBase ?? '';
    final uri = Uri.parse(base + path);
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
