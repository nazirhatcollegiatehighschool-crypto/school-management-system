import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'config.dart';

/// View / download server-generated PDFs (seat plan, admit cards).
/// The backend accepts `?token=` on these routes because an external
/// viewer cannot send Authorization headers.
///
/// Downloads stream with a real % progress dialog + timeouts, so a slow
/// mobile-data connection never looks frozen.
class PdfHelper {
  static String url(String path) {
    final t = Api.token ?? '';
    final sep = path.contains('?') ? '&' : '?';
    return '${Config.api}$path$sep${'token'}=$t';
  }

  /// "View" = quick download to temp with progress, then open in the
  /// device PDF viewer (works offline afterwards, no browser round-trip).
  static Future<void> view(BuildContext context, String path) async {
    final name = 'view_${DateTime.now().millisecondsSinceEpoch}.pdf';
    await download(context, path, name, openAfter: true, tempFile: true);
  }

  static Future<void> download(
    BuildContext context,
    String path,
    String filename, {
    bool openAfter = true,
    bool tempFile = false,
  }) async {
    final progress = ValueNotifier<double>(0);
    var cancelled = false;
    var dialogOpen = false;
    if (context.mounted) {
      dialogOpen = true;
      unawaited(showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('PDF ডাউনলোড হচ্ছে…'),
            content: ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (_, v, _) => Column(mainAxisSize: MainAxisSize.min, children: [
                LinearProgressIndicator(value: v <= 0 ? null : v),
                const SizedBox(height: 10),
                Text(v <= 0 ? 'শুরু হচ্ছে…' : '${(v * 100).toStringAsFixed(0)}%'),
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () { cancelled = true; Navigator.pop(ctx); },
                child: const Text('বাতিল'),
              ),
            ],
          ),
        ),
      ));
    }
    void closeDialog() {
      if (dialogOpen && context.mounted) {
        dialogOpen = false;
        Navigator.pop(context);
      }
    }

    final client = http.Client();
    try {
      final rq = http.Request('GET', Uri.parse(url(path)));
      final streamed = await client.send(rq).timeout(const Duration(seconds: 30));
      if (streamed.statusCode != 200) {
        throw Exception('ডাউনলোড ব্যর্থ (${streamed.statusCode})');
      }
      final total = streamed.contentLength ?? 0;
      final dir = tempFile
          ? await getTemporaryDirectory()
          : await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$filename');
      if (await file.exists()) await file.delete();
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in streamed.stream.timeout(
          const Duration(seconds: 60),
          onTimeout: (sink) => throw TimeoutException('ডাউনলোড আটকে গেছে — আবার চেষ্টা করুন'),
        )) {
          if (cancelled) {
            await sink.close();
            try { await file.delete(); } catch (_) {}
            return;
          }
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) progress.value = received / total;
        }
      } finally {
        await sink.close();
      }
      progress.dispose();
      closeDialog();
      if (!context.mounted) return;
      if (openAfter) {
        final ok = await launchUrl(Uri.file(file.path), mode: LaunchMode.externalApplication);
        if (!ok && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('PDF সেভ হয়েছে: ${file.path} (viewer খোলা যায়নি)')));
        }
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('সেভ হয়েছে: ${file.path}')));
      }
    } catch (e) {
      progress.dispose();
      closeDialog();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.red,
            content: Text(e is TimeoutException
                ? 'সময় শেষ — নেট চেক করে আবার চেষ্টা করুন'
                : e.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      client.close();
    }
  }
}
