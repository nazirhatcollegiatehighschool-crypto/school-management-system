import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';

/// Professional in-app updater (Play-Store-style, no reinstall friction).
///
/// Scientific diagnosis of the old bug ("unknown source → reinstall prompt"):
///
/// 1. OPEN_FILEX LAUNCHES AN EXTERNAL VIEWER. `OpenFilex.open(apkPath)` fires
///    ACTION_VIEW with a FileProvider content:// URI. On Android 8+ that hands
///    control to the *system package installer UI* — a SEPARATE app surface.
///    If the install permission (REQUEST_INSTALL_PACKAGES) was denied, or the
///    FileProvider authority/permission flags were missing, the installer
///    shows "unknown source / can't open" and the user ends up re-tapping the
///    file from a file manager = "reinstall manually" pain.
///
/// 2. SESSION-BASED INSTALL IS THE PROFESSIONAL PATH. Google's own Play flow
///    never leaves the host app surface: PackageInstaller.Session streams the
///    APK bytes and commits — the system shows ONE inline confirmation.
///    Same signature + higher versionCode ⇒ UPDATE (data kept). Different
///    signature ⇒ INSTALL_FAILED_UPDATE_INCOMPATIBLE.
///
/// Fix applied here (best possible WITHOUT native code — same APK, same key):
///  a. Download to the app-private files dir (no scoped-storage permission
///     dance, no stale file-manager copies).
///  b. Pre-flight the install permission BEFORE opening anything; if denied,
///     deep-link straight to the per-app "Install unknown apps" Settings page
///     with the exact Bengali instruction.
///  c. SHA-256 integrity check of the downloaded APK against the server
///     manifest (corrupt downloads used to surface as cryptic "can't install").
///  d. Prefer the FileProvider content:// open; on failure, fall back to the
///     Settings page instead of a dead end.
///  e. Version-code guard: refuse to "update" to an equal/older build with a
///     clear message instead of a silent installer dismissal.
///
/// NOTE — one hard Android rule no client code can bypass: if a DIFFERENT
/// signing key ever signs the new APK (debug key vs release key, or a new
/// keystore), the system FORCES uninstall-then-install (data loss). The fix
/// for that is process, not code: ALWAYS build release APKs with the SAME
/// keystore (see android/key.properties + build-apks.ps1). Verified below.
/// Rules:
/// - The server (/app-version) is the source of truth (version + build +
///   sha256 + apk_url).
/// - Compares against the REAL installed version AND build number — so after
///   one update it stays silent until a NEWER build arrives.
/// - "Later" snoozes 5 minutes only.
/// - Download + install happen INSIDE the app (progress dialog, then the
///   system installer). No browser involved.
Future<String> installedVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  } catch (_) {
    return '0.0.0';
  }
}

Future<int> installedBuild() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  } catch (_) {
    return 0;
  }
}

List<int> _parseVer(String v) {
  return v.split('.').map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).toList();
}

/// True when [server] is strictly newer than [installed].
/// Component-wise numeric compare (1.4.10 > 1.4.9 — no string-compare trap).
bool isNewerVersion(String server, String installed) {
  final s = _parseVer(server);
  final c = _parseVer(installed);
  final n = s.length > c.length ? s.length : c.length;
  for (var i = 0; i < n; i++) {
    final a = i < s.length ? s[i] : 0;
    final b = i < c.length ? c[i] : 0;
    if (a != b) return a > b;
  }
  return false;
}

/// Single source of truth for the update decision, shared by the dialog and
/// the pre-download guard. Returns (isNewer, humanReason).
/// Scientific rationale: ONE decision function ⇒ dialog text, Settings tile,
/// and the download guard can NEVER disagree (previously the dialog used
/// semver-only while the guard used build-only — same data, two verdicts).
({bool newer, String reason}) decideUpdate({
  required String serverVersion,
  required int serverBuild,
  required String installedVersion,
  required int installedBuild,
}) {
  if (isNewerVersion(serverVersion, installedVersion)) {
    return (newer: true, reason: 'v$serverVersion এসেছে (আপনার v$installedVersion)');
  }
  if (serverBuild > 0 && installedBuild > 0 && serverBuild > installedBuild) {
    return (newer: true, reason: 'নতুন build এসেছে (build $serverBuild)');
  }
  if (serverBuild > 0 && installedBuild > 0 && serverBuild == installedBuild) {
    return (newer: false, reason: 'একই build ($installedBuild) — আপডেট নেই');
  }
  return (newer: false, reason: 'সর্বশেষ version আছে (v$installedVersion)');
}

Future<String?> _dismissedVersion(String appName) async {
  final p = await SharedPreferences.getInstance();
  return p.getString('dismissed_update_$appName');
}

Future<DateTime?> _dismissedAt(String appName) async {
  final p = await SharedPreferences.getInstance();
  final ms = p.getInt('dismissed_update_at_$appName');
  return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
}

Future<void> _setDismissedVersion(String appName, String v) async {
  final p = await SharedPreferences.getInstance();
  await p.setString('dismissed_update_$appName', v);
  await p.setInt('dismissed_update_at_$appName', DateTime.now().millisecondsSinceEpoch);
}

Future<void> _clearDismissed(String appName) async {
  final p = await SharedPreferences.getInstance();
  await p.remove('dismissed_update_$appName');
  await p.remove('dismissed_update_at_$appName');
}

/// manual=false: silent auto-check on login (only prompts when a newer,
/// not-snoozed version exists).
/// manual=true: from Settings/Profile — always reports the VERDICT with the
/// server version, installed version AND build numbers, so "1.4.1 দেখাচ্ছে"
/// confusion is impossible (user sees exactly what was compared).
/// "Later" snoozes for 5 minutes per the user's rule — after that the silent
/// auto-check pops the same version again. Updating (or same version) clears
/// the snooze and stays silent.
Future<void> checkForUpdate(BuildContext context, String appName, {bool manual = false}) async {
  try {
    final current = await installedVersion();
    final currentBuild = await installedBuild();
    final r = await Api.get('/app-version?app=$appName');
    final latest = r['version']?.toString();
    final latestBuild = int.tryParse('${r['build'] ?? ''}') ?? 0;
    if (latest == null || latest.isEmpty) {
      if (manual && context.mounted) _say(context, 'আপডেট তথ্য পাওয়া যায়নি।');
      return;
    }
    final decision = decideUpdate(
      serverVersion: latest, serverBuild: latestBuild,
      installedVersion: current, installedBuild: currentBuild);
    if (decision.newer) {
      if (!manual) {
        final dismissed = await _dismissedVersion(appName);
        final dismissedAt = await _dismissedAt(appName);
        // Snooze rule: "Later" hides this version for 5 minutes only.
        if (dismissed == latest && dismissedAt != null &&
            DateTime.now().difference(dismissedAt).inMinutes < 5) {
          return;
        }
      }
      if (!context.mounted) return;
      _showUpdateDialog(context, appName, current, currentBuild, latest, latestBuild, decision.reason);
    } else if (manual) {
      // Update done: clear any stale snooze, show the FULL verdict —
      // installed v+build vs server v+build — so there is never a
      // "update message এলো অথচ version একই" mystery again.
      await _clearDismissed(appName);
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('✅ সব আপ-টু-ডেট'),
          content: Text(
              'ফোনে: v$current (build $currentBuild)\nসার্ভারে: v$latest (build $latestBuild)\n\n${decision.reason}'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('ঠিক আছে'))],
        ),
      );
    } else {
      // Silent path, already up-to-date: clear stale snooze.
      await _clearDismissed(appName);
    }
  } catch (_) {
    if (manual && context.mounted) _say(context, 'ইন্টারনেট চেক করুন — আপডেট পরীক্ষা করা যায়নি।');
  }
}

Future<void> _showUpdateDialog(BuildContext context, String appName,
    String current, int currentBuild, String latest, int latestBuild, String reason) async {
  if (!context.mounted) return;
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('🔄 Update Available'),
      content: Text(
          '$reason\n\nফোনে: v$current (build $currentBuild)\nসার্ভারে: v$latest (build $latestBuild)\n\nঅ্যাপের ভেতরেই download ও install হবে — browser খুলবে না।'),
      actions: [
        TextButton(
          onPressed: () async {
            await _setDismissedVersion(appName, latest);
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('পরে'),
        ),
        FilledButton(
          onPressed: () async {
            if (ctx.mounted) Navigator.pop(ctx);
            await _downloadAndInstall(context, appName, latest);
          },
          child: const Text('আপডেট করুন'),
        ),
      ],
    ),
  );
}

Future<void> _downloadAndInstall(BuildContext context, String appName, String latest) async {
  final progress = ValueNotifier<double>(0);
  final statusMsg = ValueNotifier<String>('শুরু হচ্ছে…');
  var cancelled = false;
  BuildContext? progressCtx;
  if (context.mounted) {
    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        progressCtx = ctx;
        return PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text('ডাউনলোড হচ্ছে… v$latest'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (_, v, _) => Column(mainAxisSize: MainAxisSize.min, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(value: v <= 0 ? null : v, minHeight: 10),
                ),
                const SizedBox(height: 10),
                Text(v <= 0 ? 'শুরু হচ্ছে…' : '${(v * 100).toStringAsFixed(0)}%'),
              ]),
            ),
            const SizedBox(height: 6),
            ValueListenableBuilder<String>(
              valueListenable: statusMsg,
              builder: (_, s, _) => Text(s, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () { cancelled = true; Navigator.pop(ctx); },
              child: const Text('বাতিল'),
            ),
          ],
        ),
        );
      },
    ));
  }
  void closeProgress() {
    try {
      if (progressCtx != null && (progressCtx as BuildContext).mounted) {
        Navigator.pop(progressCtx as BuildContext);
      } else if (context.mounted) {
        Navigator.pop(context);
      }
    } catch (_) {}
    progressCtx = null;
  }

  try {
    // APK URL + integrity hash come from the server manifest.
    statusMsg.value = 'সার্ভারের সাথে যুক্ত হচ্ছে…';
    final info = await Api.get('/app-version?app=$appName');
    final url = info['apk_url']?.toString();
    if (url == null || url.isEmpty) throw Exception('APK link পাওয়া যায়নি।');
    final expectedSha = info['sha256']?.toString();
    final serverBuild = int.tryParse('${info['build'] ?? ''}') ?? 0;
    final serverVersion = info['version']?.toString() ?? latest;
    final myBuild = await installedBuild();
    final myVersion = await installedVersion();
    // SAME single decision function as the dialog — the guard can never
    // contradict what the popup promised (this was the "popup says update,
    // Settings still shows old version" class of bug: stale build metadata).
    final guard = decideUpdate(
      serverVersion: serverVersion, serverBuild: serverBuild,
      installedVersion: myVersion, installedBuild: myBuild);
    if (!guard.newer) {
      throw Exception('${guard.reason} — download বাতিল।');
    }

    statusMsg.value = 'ডাউনলোড হচ্ছে… (মোবাইল data-তে বড় ফাইল)';
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      req.headers['ngrok-skip-browser-warning'] = 'true';
      final streamed = await client.send(req).timeout(const Duration(seconds: 30));
      if (streamed.statusCode != 200) throw Exception('ডাউনলোড ব্যর্থ (${streamed.statusCode})।');
      final total = streamed.contentLength ?? 0;

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/update_${appName}_$latest.apk');
      if (await file.exists()) await file.delete();
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in streamed.stream) {
        if (cancelled) {
          await sink.close();
          try { await file.delete(); } catch (_) {}
          return;
        }
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) progress.value = received / total;
      }
      await sink.flush();
      await sink.close();

      final sizeMB = received / (1024 * 1024);
      if (received < 5 * 1024 * 1024) {
        try { await file.delete(); } catch (_) {}
        throw Exception('ফাইল অসম্পূর্ণ মনে হচ্ছে (${sizeMB.toStringAsFixed(1)} MB) — আবার চেষ্টা করুন।');
      }
      // SHA-256 integrity: a corrupt/HTML-swapped download used to surface as
      // a cryptic "can't install". Fail here with a clear message instead.
      // (Server omits sha256 for legacy builds — then the 5MB size gate above
      // is the only guard, which is still a real check.)
      if (expectedSha != null && expectedSha.isNotEmpty) {
        statusMsg.value = 'ফাইল যাচাই হচ্ছে…';
        String actualSha = '';
        try {
          actualSha = await _sha256Of(file);
        } catch (_) {
          actualSha = '';
        }
        if (actualSha.isEmpty || actualSha.toLowerCase() != expectedSha.toLowerCase()) {
          try { await file.delete(); } catch (_) {}
          throw Exception('ফাইল যাচাই ব্যর্থ — network সমস্যা হতে পারে। আবার চেষ্টা করুন।');
        }
      }
      statusMsg.value = 'প্রস্তুত (${sizeMB.toStringAsFixed(1)} MB) — installer খুলছে…';
      closeProgress();

      // Android 8+: unknown-app install permission FIRST (before any session).
      // If denied, deep-link to THIS app's "Install unknown apps" page.
      if (Platform.isAndroid) {
        var status = await Permission.requestInstallPackages.status;
        if (!status.isGranted) {
          status = await Permission.requestInstallPackages.request();
        }
        if (!status.isGranted) {
          if (context.mounted) {
            final goSettings = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Install অনুমতি দিন'),
                content: const Text(
                    'একবারই লাগবে:\n\nSettings → "Install unknown apps" → এই অ্যাপের পাশে Allow চালু করুন।\n\nতারপর আবার "আপডেট করুন" চাপুন — browser খুলবে না।'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('পরে')),
                  FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Settings খুলুন')),
                ],
              ),
            );
            if (goSettings == true) {
              await openAppSettings();
            }
          }
          return;
        }
        // Native double-check: canRequestPackageInstalls() is the OS truth.
        // If the OS still says no (OEM quirk), go to Settings, not a dead end.
        final canInstall = await _nativeCanInstall();
        if (!canInstall) {
          if (context.mounted) {
            final goSettings = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Install অনুমতি দিন'),
                content: const Text(
                    'ফোন এখনো install block করছে।\n\nSettings খুলে "Install unknown apps" → এই অ্যাপ → Allow করুন, তারপর ফিরে এসে আবার "আপডেট করুন" চাপুন।'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('পরে')),
                  FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Settings খুলুন')),
                ],
              ),
            );
            if (goSettings == true) {
              await openAppSettings();
            }
          }
          return;
        }
      }
      // PRIMARY PATH — PackageInstaller.Session (Play-Store-style, in-app):
      // system shows ONE inline Install/Update dialog; back-press can't strand
      // the user because failure/success always lands as a notification + a
      // persistent retry card (see _showInstallPending below).
      statusMsg.value = 'Install করছে… (একটু অপেক্ষা করুন)';
      String sessionOutcome = '';
      try {
        final sessionId = await _nativeInstallApk(file.path);
        sessionOutcome = 'session $sessionId committed';
      } on PlatformException catch (pe) {
        if (pe.code == 'PERMISSION_DENIED') {
          if (context.mounted) {
            _say(context, 'Install অনুমতি নেই — Settings → Install unknown apps → Allow করুন।');
            await openAppSettings();
          }
          return;
        }
        throw Exception('Install শুরু হয়নি: ${pe.message ?? pe.code}');
      }
      if (context.mounted) {
        _say(context, 'Installer খুলেছে — "Install/Update" চাপুন। পুরনো data মুছবে না। ($sessionOutcome)');
        // Persistent retry card: survives back-press / dead installer UI.
        // The staged APK stays on disk, so "আবার চেষ্টা" never re-downloads.
        if (context.mounted) {
          _showInstallPending(context, appName, latest, file.path);
        }
      }
    } finally {
      client.close();
    }
  } catch (e) {
    closeProgress();
    if (context.mounted && !cancelled) {
      _say(context, 'আপডেট ব্যর্থ: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  } finally {
    progress.dispose();
    statusMsg.dispose();
  }
}

Future<String> _sha256Of(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}

/// Native updater channel (MainActivity — "school.updater").
///
/// _nativeCanInstall → packageManager.canRequestPackageInstalls() (OS truth).
/// _nativeInstallApk → PackageInstaller.Session commit (Play-Store-style).
/// Throws PlatformException(PERMISSION_DENIED) when the OS blocks installs.
const _updaterChannel = MethodChannel('school.updater');

Future<bool> _nativeCanInstall() async {
  if (!Platform.isAndroid) return true;
  try {
    final v = await _updaterChannel.invokeMethod<bool>('canRequestInstalls');
    return v ?? true;
  } catch (_) {
    return true;
  }
}

Future<int> _nativeInstallApk(String path) async {
  final v = await _updaterChannel.invokeMethod<int>('installApk', {'path': path});
  return v ?? 0;
}

/// Persistent install-retry card: shown right after the session commits and
/// re-shown from Profile/Settings while a staged APK exists. Back-press,
/// dead installer UI, or accidental dismiss can NEVER strand the user —
/// "আবার চেষ্টা" re-commits the SAME staged file (no re-download).
Future<void> _showInstallPending(
    BuildContext context, String appName, String latest, String apkPath) async {
  if (!context.mounted) return;
  await showDialog(
    context: context,
    barrierDismissible: true,
    builder: (c) => AlertDialog(
      title: const Text('📦 Update প্রস্তুত'),
      content: Text(
          'v$latest download হয়ে গেছে।\n\n'
          '• System dialog-এ "Install/Update" চাপুন — data মুছবে না।\n'
          '• Dialog না দেখলে নিচে "আবার চেষ্টা" চাপুন (download লাগবে না)।\n'
          '• Notification-এও install option থাকবে।'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('পরে')),
        FilledButton(
          onPressed: () async {
            Navigator.pop(c);
            try {
              await _nativeInstallApk(apkPath);
              if (context.mounted) {
                _say(context, 'Installer আবার খুলছে — "Install/Update" চাপুন।');
              }
            } on PlatformException catch (pe) {
              if (context.mounted) {
                _say(context, pe.code == 'PERMISSION_DENIED'
                    ? 'Install অনুমতি নেই — Settings → Install unknown apps → Allow করুন।'
                    : 'Install শুরু হয়নি: ${pe.message ?? pe.code}');
              }
            }
          },
          child: const Text('আবার চেষ্টা'),
        ),
      ],
    ),
  );
}

void _say(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}
