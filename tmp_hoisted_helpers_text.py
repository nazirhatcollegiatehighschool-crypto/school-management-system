import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Loosely опю·পিওdescribed الشخصي helpers — app-wide, so both the host form AND the
/// import dialog can render the বাংলা prompt template (the dialog is a separate
/// State class, it cannot see the host State's private members).
String bunkPromptTemplate({
  required String classLabel,
  required bool classHasGroup,
}) {
  final section = classHasGroup ? 'গ্রুপ (Group) ± ' : 'বিভাগ (Section) ± ';
  return '''CLSS: ${classLabel}
ছাত্র / ছাত্রীর তথ্য অনুসরণ করুন বিশ্লেষণ করে নীচের FORMAT-এ ফেরত পাঠান — JSON row:
{ "name": "...", "roll": "বাস্তব রোল", "dob": "YYYY-MM-DD", "religion": "...",
  "guardian_name": "...", "guardian_phone": "...", "father_name": "...",
  "mother_name": "...", "birth_cert_no": "...", "address": "...",
  "${classHasGroup ? 'group' : 'section'}": "..." }

RULES:
- Student কোড (Student Code / Code): সার্ভার স্বয়ংক্রিয়ভাবে তৈরি করবে — লিখবেন না।
- রোল (Roll): শুধু এই ফিল্ডটি ম্যানুয়াল/ইমপোর্ট prompt থেকে আসে — বাধ্যতামূলকভাবে ভরুন যাচাই করে,
  প্লিজ school-এর এই ক্লাসের (${classLabel}) ${section}স্বয়ংক্রিয় Code+Roll থেকে আলাদা ভাবে রেখে দিন।
- বিশ্লেষণ করে Prompt-এ নামের পাশে থাকা রোলটি পড়ে 'roll' কী-তে ভরুন।''';
}

/// বাংলা / English prompt থেকে Roll / রোল বের করে callback-এ দেয় (shared parser).
void bunkParsePrompt(String raw, void Function(String?) onRoll) {
  final rg1 = RegExp(r'''[Rr]oll|রোল''');
  final m = rg1.firstMatch(raw);
  if (m != null) {
    final tail = raw.substring(m.end);
    final mv = RegExp(r'[:=]?\s*(\d+)').firstMatch(tail);
    if (mv != null) onRoll(mv.group(1));
  }
}
