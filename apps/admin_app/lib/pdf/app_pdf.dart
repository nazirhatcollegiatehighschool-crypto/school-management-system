import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// On-device PDF generation.
///
/// Every PDF this app offers (result cards, whole-class result sheets) is
/// rendered here from JSON the app already fetched — nothing is downloaded as
/// a pre-built PDF from the server. That keeps generation working offline and
/// means the guardian / teacher / admin apps can all render the same data
/// without any server-side PDF renderer.
class AppPdf {
  AppPdf._();

  static pw.Font? _bn;

  /// Bundled Bangla font. Loaded once, then reused by every document.
  static Future<pw.Font> banglaFont() async {
    if (_bn != null) return _bn!;
    final ByteData data = await rootBundle.load('assets/fonts/Kalpurush.ttf');
    _bn = pw.Font.ttf(data);
    return _bn!;
  }

  /// Share the finished document through the system share sheet (Drive,
  /// WhatsApp, Bluetooth, "save to files", …) — the PDF never leaves the phone
  /// unless the user explicitly shares it.
  static Future<void> share(Uint8List bytes, String filename) =>
      Printing.sharePdf(bytes: bytes, filename: filename);

  /// Full-screen on-device PDF preview (no download, no server).
  static Future<void> preview(Uint8List bytes) =>
      Printing.layoutPdf(onLayout: (_) async => bytes);

  static pw.TextStyle bn(
    pw.Font font, {
    double size = 10,
    pw.FontWeight? weight,
    PdfColor color = PdfColors.black,
  }) =>
      pw.TextStyle(font: font, fontSize: size, fontWeight: weight, color: color);

  /// School header block used on top of every printable document.
  static pw.Widget header(
    pw.Font font,
    String schoolName,
    String schoolAddress, {
    required String title,
    String? subtitle,
  }) {
    return pw.Column(children: [
      pw.Text(schoolName,
          textAlign: pw.TextAlign.center,
          style: bn(font, size: 16, weight: pw.FontWeight.bold, color: PdfColors.blue900)),
      if (schoolAddress.isNotEmpty)
        pw.Text(schoolAddress, textAlign: pw.TextAlign.center, style: bn(font, size: 9, color: PdfColors.grey700)),
      pw.SizedBox(height: 4),
      pw.Divider(),
      pw.Text(title,
          textAlign: pw.TextAlign.center,
          style: bn(font, size: 13, weight: pw.FontWeight.bold)),
      if (subtitle != null && subtitle.isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2),
          child: pw.Text(subtitle, textAlign: pw.TextAlign.center, style: bn(font, size: 9.5, color: PdfColors.grey800)),
        ),
    ]);
  }
}
