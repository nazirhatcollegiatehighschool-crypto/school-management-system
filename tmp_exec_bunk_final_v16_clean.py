# -*- coding: utf-8 -*-
from __future__ import print_function
import io, os

BASE = 'C:/Users/WALTON/Desktop/school-system'
P = os.path.join(BASE, 'apps/teacher_app/lib/screens/student_registration_screen.dart')


def rd(p):
    b = io.open(p, 'rb').read()
    for e in ('utf-8', 'utf-8-sig'):
        try:
            t = b.decode(e)
            if '\x00' not in t:
                return t
        except Exception:
            pass
    return b.decode('latin-1')


def wr(p, t):
    io.open(p, 'w', encoding='utf-8', newline='').write(t)


def rep(p, o, n, lab):
    t = rd(p)
    c = t.count(o)
    if c != 1:
        raise SystemExit('ANCHOR %-26s count=%d %r' % (lab, c, o[:72]))
    wr(p, t.replace(o, n))
    print('  PATCHED  %-26s ok' % lab)


t = rd(P)

# ================================================================ [A] hoist: top-level template + parser
# anchor: the `widget.classLabel` member call producing the template. We make a pure
# top-level function `_bunkPromptTemplate({required String classLabel})` and have BOTH
# the host's method and the dialog's dialog use it — kills the cross-class private scope
# error at 444 permanently.

top_helper = """/// চ structural Bengali copy template — key fields + ID is auto / roll is manual.
String _bunkPromptTemplate({required String classLabel}) {
  final section = classLabel.toLowerCase().contains('group')
      ? 'গ্রুপ (Group) ± '
      : 'বিভাগ (Section) ± ';
  return '''CLSS: ${classLabel}
ছাত্র / ছাত্রীর তথ্য অনুসরণ করুন বিশ্লেষণ করে নিচের FORMAT-এ ফেরত পাঠান — JSON row:
{ "name": "...", "roll": "বাস্তব রোল", "dob": "YYYY-MM-DD", "religion": "...",
  "guardian_name": "...", "guardian_phone": "...", "father_name": "...",
  "mother_name": "...", "birth_cert_no": "...", "address": "...",
  "${classLabel.toLowerCase().contains('group') ? 'group' : 'section'}": "..." }

RULES:
- Student কোড (Student Code / Code): সার্ভার স্বয়ংক্রিয়ভাবে তৈরি করবে — লিখবেন না।
- রোল (Roll): শুধু এই ফিল্ডটি ম্যানুয়াল/ইমপোর্ট prompt থেকে আসে — বাধ্যতামূলকভাবে ভরুন যাচাই করে,
  প্লিজ school-এর এই ক্লাসের (${classLabel}) ${section}স্বয়ংক্রিয় Code+Roll থেকে আলাদা ভাবে রেখে দিন।
- নিচের Prompt-এ নামের পাশে থাকা রোলটি পড়ে 'roll' কী-তে ভরুন.''';
}

/// Parser — reads a Bangla/English copy blob and extracts Roll/রোল into the roll input.
void _bunkParsePrompt(String raw, void Function(String?) onRoll) {
  final rg1 = RegExp(r'''[Rr]oll|রোল''');
  final m = rg1.firstMatch(raw);
  if (m != null) {
    final tail = raw.substring(m.end);
    final mv = RegExp(r'[:=]?\\s*(\\d+)').firstMatch(tail);
    if (mv != null) onRoll(mv.group(1));
  }
}

"""

# insert the helpers right after the services import line (so `class ...StatefulWidget` stays in flow)
services_anchor = "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';\n"
rep(P, services_anchor, services_anchor + "\n" + top_helper, 'services anchor + top-level helpers')

# ================================================================ [B] host class method -> thin delegator (keeps 125 API)
t = rd(P)
old_meth = """  /// চ structural Bengali copy template — key fields + ID is auto/roll is manual.
  String _promptTemplate() {
"""
new_meth = """  /// চ structural Bengali copy template — key fields + ID is auto/roll is manual.
  String _promptTemplate() {
    return _bunkPromptTemplate(classLabel: widget.classLabel);
  }

  /// চ structural Bengali copy template delegator currently unused by host (kept for API compat) — DART will flag as unused; we keep it referenced by the wrapper above via `_bunkPromptTemplate` instead.
  String _promptTemplateOld() {"""
rep(P, old_meth, old_meth, 'host delegator marker')
