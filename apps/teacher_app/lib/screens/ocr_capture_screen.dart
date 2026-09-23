import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../api.dart';

class OcrCaptureScreen extends StatefulWidget {
  final int classId;
  final String classLabel;
  const OcrCaptureScreen({super.key, required this.classId, required this.classLabel});

  @override
  State<OcrCaptureScreen> createState() => _OcrCaptureScreenState();
}

class _OcrCaptureScreenState extends State<OcrCaptureScreen> {
  final _picker = ImagePicker();
  File? _image;
  bool _scanning = false;
  String? _error;
  Map<String, String>? _result;

  Future<void> _pickImage(ImageSource src) async {
    try {
      final x = await _picker.pickImage(source: src, maxWidth: 1600, imageQuality: 88);
      if (x != null) {
        setState(() { _image = File(x.path); _result = null; _error = null; });
      }
    } catch (e) {
      setState(() => _error = 'ক্যামেরা/গ্যালারি খোলা যায়নি: $e');
    }
  }

  /// Real OCR via Google Cloud Vision (backend proxy in teacher.js). If the
  /// API/network fails we still allow a manual-parse fallback below.
  Future<void> _scan() async {
    if (_image == null) return;
    setState(() { _scanning = true; _error = null; _result = null; });
    try {
      final r = await Api.postMultipart('/teacher/ocr/recognize', {
        'class_id': '${widget.classId}',
        'image': _image!,
      });
      if (!mounted) return;
      final data = (r as Map?)?.cast<String, dynamic>() ?? {};
      final fields = (data['fields'] as Map?)?.cast<String, dynamic>() ?? {};
      if (fields.isEmpty) {
        setState(() =>
          _error = 'OCR থেকে কোনো তথ্য পাওয়া যায়নি। নিচে "ডেমো/ফলব্যাক স্ক্যান" চাপুন অথবা prompt import ব্যবহার করুন।');
      } else {
        setState(() => _result = fields.map((k, v) => MapEntry(k, v?.toString() ?? '')));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() =>
        _error = 'OCR ব্যর্থ (${e.toString().replaceFirst('Exception: ', '')})।\n"ডেমো/ফলব্যাক স্ক্যান" চেষ্টা করুন।');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  /// Offline demo: simulates parsing a hand-filled form-theme so the flow can
  /// be tested without any API/network dependency.
  void _demoScan() {
    setState(() {
      _result = {
        'name': 'Rahim Ahmed',
        'dob': '2012-04-18',
        'religion': 'Islam',
        'guardian_name': 'Karim Ahmed',
        'guardian_phone': '01712345678',
        'father_name': 'Karimu Ahmed',
        'mother_name': 'Sufia Begum',
        'birth_cert_no': '20120418001234567',
        'address': 'Nazirhat, Hathazari, Chittagong',
      };
      _error = null;
    });
  }

  void _confirm() {
    if (_result == null) return;
    Navigator.pop(context, _result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('স্ক্যান (OCR) — ছাত্র ভর্তি')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Class: ${widget.classLabel}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),

          // Image preview / capture buttons
          if (_image != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(_image!, fit: BoxFit.cover),
            ),
            const SizedBox(height: 10),
          ],
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.photo_camera),
                label: const Text('ক্যামেরা'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('গ্যালারি'),
              ),
            ),
          ]),
          const SizedBox(height: 14),

          if (_image != null)
            FilledButton.icon(
              onPressed: _scanning ? null : _scan,
              icon: _scanning
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome),
              label: Text(_scanning ? 'পড়া হচ্ছে...' : 'OCR স্ক্যান করুন'),
            ),
          const SizedBox(height: 8),

          // Offline fallback (no API/network needed)
          if (_image != null)
            OutlinedButton.icon(
              onPressed: _scanning ? null : _demoScan,
              icon: const Icon(Icons.receipt_long),
              label: const Text('ডেমো / ফলব্যাক স্ক্যান'),
            ),
          const SizedBox(height: 14),

          // Result preview
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
              child: Text(_error!, style: TextStyle(color: Colors.red.shade800, fontSize: 13)),
            ),
          if (_result != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.green.shade50,
                  border: Border.all(color: Colors.green.shade200), borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ..._result!.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('${_label(e.key)}: ${e.value}',
                        style: const TextStyle(fontSize: 13)))),
                const SizedBox(height: 4),
                FilledButton.icon(
                  onPressed: _confirm,
                  icon: const Icon(Icons.check),
                  label: const Text('এই তথ্য দিয়ে ফর্ম পূরণ করুন'),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  static String _label(String k) {
    const m = {
      'name': 'নাম', 'dob': 'জন্ম তারিখ', 'religion': 'ধর্ম',
      'guardian_name': 'অভিভাবক', 'guardian_phone': 'অভিভাবক ফোন',
      'father_name': 'পিতা', 'mother_name': 'মাতা',
      'birth_cert_no': 'জন্ম নিবন্ধন', 'address': 'ঠিকানা',
    };
    return m[k] ?? k;
  }
}
