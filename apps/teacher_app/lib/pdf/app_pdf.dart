import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// On-device PDF generation.
///
/// Every PDF the teacher app offers (marksheet, seat plan, admit cards) is
/// rendered here from JSON the app already fetched — nothing is downloaded as
/// a PDF from the server. That keeps generation working offline-after-load and
/// removes the need for any server-side PDF renderer.
class AppPdf {
  AppPdf._();

  static pw.Font? _bn;
  static pw.MemoryImage? _schoolLogo;

  /// Bundled Bangla font. Loaded once, then reused by every document.
  static Future<pw.Font> banglaFont() async {
    if (_bn != null) return _bn!;
    final ByteData data = await rootBundle.load('assets/fonts/Kalpurush.ttf');
    _bn = pw.Font.ttf(data);
    final logo = await rootBundle.load('assets/school_logo.png');
    _schoolLogo = pw.MemoryImage(logo.buffer.asUint8List());
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
  }) => pw.TextStyle(
    font: font,
    fontSize: size,
    fontWeight: weight,
    color: color,
  );

  static pw.Widget signatoryBlock(
    pw.Font font,
    Map? signatory,
    String fallbackTitle,
  ) {
    final name = '${signatory?['name'] ?? ''}'.trim();
    final title = '${signatory?['designation'] ?? fallbackTitle}'.trim();
    pw.Widget? stamp;
    final encoded = signatory?['data_base64']?.toString();
    if (encoded != null && encoded.isNotEmpty) {
      try {
        stamp = pw.Image(
          pw.MemoryImage(base64Decode(encoded)),
          width: 112,
          height: 30,
          fit: pw.BoxFit.contain,
        );
      } catch (_) {}
    }
    return pw.Expanded(
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.SizedBox(height: 30, child: stamp ?? pw.SizedBox()),
          pw.Container(width: 150, height: 0.6, color: PdfColors.black),
          if (name.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 3),
              child: pw.Text(
                name,
                textAlign: pw.TextAlign.center,
                maxLines: 1,
                style: pw.TextStyle(font: pw.Font.timesBold(), fontSize: 8.5),
              ),
            ),
          pw.Text(
            title,
            textAlign: pw.TextAlign.center,
            maxLines: 1,
            style: bn(font, size: 8),
          ),
        ],
      ),
    );
  }

  static pw.TextStyle _headingStyle(
    pw.Font bnFont,
    String text, {
    double size = 12,
  }) => RegExp(r'[\u0980-\u09FF]').hasMatch(text)
      ? bn(bnFont, size: size, weight: pw.FontWeight.bold)
      : pw.TextStyle(
          font: pw.Font.timesBold(),
          fontSize: size,
          letterSpacing: 1.2,
        );

  /// Reference-inspired A4 paper: fine double rule and a quiet school-seal watermark.
  static pw.PageTheme paperTheme({double margin = 36}) => pw.PageTheme(
    pageFormat: PdfPageFormat.a4,
    margin: pw.EdgeInsets.all(margin),
    buildBackground: (ctx) => pw.FullPage(
      ignoreMargins: true,
      child: pw.Stack(
        children: [
          pw.Positioned.fill(
            child: pw.Container(color: PdfColor.fromHex('#fffefb')),
          ),
          pw.Positioned.fill(
            child: pw.Container(
              margin: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey800, width: 0.8),
              ),
              child: pw.Container(
                margin: const pw.EdgeInsets.all(4),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey600, width: 0.4),
                ),
              ),
            ),
          ),
          if (_schoolLogo != null)
            pw.Center(
              child: pw.Opacity(
                opacity: 0.06,
                child: pw.Image(
                  _schoolLogo!,
                  width: 240,
                  height: 240,
                  fit: pw.BoxFit.contain,
                ),
              ),
            ),
        ],
      ),
    ),
  );

  static pw.Widget logoMark({double width = 44}) => _schoolLogo == null
      ? pw.SizedBox()
      : pw.Container(
          width: width,
          height: width,
          padding: const pw.EdgeInsets.all(2),
          decoration: pw.BoxDecoration(
            shape: pw.BoxShape.circle,
            border: pw.Border.all(color: PdfColors.grey700),
          ),
          child: pw.Image(_schoolLogo!, fit: pw.BoxFit.contain),
        );

  /// School header block used on top of every printable document.
  static pw.Widget header(
    pw.Font font,
    String schoolName,
    String schoolAddress, {
    required String title,
    String? subtitle,
    String schoolNameBn = 'নাজিরহাট কলেজিয়েট উচ্চ বিদ্যালয়',
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(8, 7, 8, 7),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey800, width: 0.8),
        color: PdfColors.white,
      ),
      child: pw.Column(
        children: [
          pw.Text(
            schoolName,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: pw.Font.timesBold(),
              fontSize: 15,
              color: PdfColors.black,
            ),
          ),
          if (schoolNameBn.isNotEmpty)
            pw.Text(
              schoolNameBn,
              textAlign: pw.TextAlign.center,
              style: bn(font, size: 11, weight: pw.FontWeight.bold),
            ),
          if (schoolAddress.isNotEmpty)
            pw.Text(
              schoolAddress.toUpperCase(),
              textAlign: pw.TextAlign.center,
              style: RegExp(r'[\u0980-\u09FF]').hasMatch(schoolAddress)
                  ? bn(font, size: 7.5, color: PdfColors.grey800)
                  : pw.TextStyle(
                      font: pw.Font.times(),
                      fontSize: 7.5,
                      color: PdfColors.grey800,
                      letterSpacing: 1.0,
                    ),
            ),
          if (_schoolLogo != null)
            pw.Container(
              width: 52,
              height: 52,
              margin: const pw.EdgeInsets.only(top: 3, bottom: 2),
              padding: const pw.EdgeInsets.all(2),
              decoration: pw.BoxDecoration(
                shape: pw.BoxShape.circle,
                border: pw.Border.all(color: PdfColors.grey700),
              ),
              child: pw.Image(_schoolLogo!, fit: pw.BoxFit.contain),
            ),
          pw.SizedBox(height: 4),
          pw.Container(
            height: 1,
            width: double.infinity,
            color: PdfColors.grey700,
          ),
          pw.SizedBox(height: 4),
          if (subtitle != null && subtitle.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2),
              child: pw.Text(
                subtitle,
                textAlign: pw.TextAlign.center,
                style: _headingStyle(font, subtitle, size: 10),
              ),
            ),
          pw.Text(
            title.toUpperCase(),
            textAlign: pw.TextAlign.center,
            style: _headingStyle(font, title.toUpperCase(), size: 12.5),
          ),
        ],
      ),
    );
  }
}
