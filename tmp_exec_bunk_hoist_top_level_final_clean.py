# -*- coding: utf-8 -*-
from __future__ import print_function
import io, os, re

BASE = 'C:/Users/WALTON/Desktop/school-system'
P = 'apps/teacher_app/lib/screens/student_registration_screen.dart'


def rd(p):
    p = p if os.path.isabs(p) else os.path.join(BASE, p)
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
    p = p if os.path.isabs(p) else os.path.join(BASE, p)
    io.open(p, 'w', encoding='utf-8', newline='').write(t)


def one(p, o, n, lab):
    t = rd(p)
    c = t.count(o)
    if c != 1:
        raise SystemExit('ANCHOR %-24s count=%d %r' % (lab, c, o[:64]))
    wr(p, t.replace(o, n))
    print('  PATCHED  %-24s ok' % lab)


t = rd(P)

# ---------------------------------------------------------------- [1] services import (Clipboard)
_m_serv = "import 'package:flutter/material.dart';\n"
one(P, _m_serv,
    "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';\n",
    'services import')

t = rd(P)

# ---------------------------------------------------------------- [2] top-level prompt helper
#     New top-level builder — key fields + ID auto/roll manual (pure, class-label driven).
top_helper = '''/// চ structural Bengali copy template — key fields + ID is auto/roll is manual.
String _bunkPromptTemplate({required String classLabel}) {
  final section = classLabel.toLowerCase().contains('group')
      ? 'গ্রুপ (Group) + '
      : 'বিভাগ (Section) + ';
  return '''CLSS: $classLabel
ছাত্র / ছাত্রীর তথ্য অনুসরণ করুন বিশ্লেষণ করে নিচের FORMAT-এ ফেরত পাঠান — JSON row:
{ "name": "...", "roll": "বাস্তব রোল", "dob": "YYYY-MM-DD", "religion": "...",
  "guardian_name": "...", "guardian_phone": "...", "father_name": "...",
  "mother_name": "...", "birth_cert_no": "...", "address": "...",
  "${classLabel.toLowerCase().contains('group') ? 'group' : 'section'}": "..." }

RULES:
- Student কোড (Student Code / Code): সার্ভার স্বয়ংক্রিয়ভাবে তৈরি করবে — লিখবেন না।
- রোল (Roll): শুধু এই ফিল্ডটি ম্যানুয়াল/ইমপোর্ট prompt থেকে আসে — বাধ্যতামূলকভাবে ভরুন যাচাই করে,
  প্লিজ school-এর এই ক্লাসের ($classLabel) স্বয়ংক্রিয় Code+Roll থেকে আলাদা ভাবে রেখে দিন।''';
}

/// Parser — reads a Bangla/English prompt blob and extracts Roll/রোল into a callback.
void _bunkParsePrompt(String raw, void Function(String?) onRoll) {
  final rg1 = RegExp(r'''[Rr]oll|রোল''');
  final m = rg1.firstMatch(raw);
  if (m != null) {
    final tail = raw.substring(m.end);
    final mv = RegExp(r'[:=]?\s*(\d+)').firstMatch(tail);
    if (mv != null) onRoll(mv.group(1));
  }
}

'''
ins = "class StudentRegistrationScreen extends StatefulWidget {"
assert t.count(ins) == 1
t = t.replace(ins, top_helper + ins)
wr(P, t)
print('  PATCHED  top-level _bunkPromptTemplate + _bunkParsePrompt')

# ---------------------------------------------------------------- [3] replace in-class methods with delegators
t = rd(P)

# old instance _promptTemplate() { ... } block -> thin wrapper
old_prompt = re.search(r'  /// চ structural Bengali copy template — key fields \+ ID is auto/roll is manual\.\n'
                       r'  String _promptTemplate\(\) \{(?P<body>.*?)\n  \}\n', t, re.S)
assert old_prompt, 'instance _promptTemplate() block not found'
t = t.replace(old_prompt.group(0),
              "  /// চ structural Bengali copy template — key fields + ID is auto/roll is manual.\n"
              "  String _promptTemplate() =>\n"
              "      _bunkPromptTemplate(classLabel: widget.classLabel);\n")

# old instance _parsePromptText(String raw) { ... } -> delegator
old_parse = re.search(r'  /// Parser — reads a Bangla/English prompt blob and extracts \'Roll\'/\'রোল\' into the roll input\.\n'
                      r'  void _parsePromptText\(String raw\) \{(?P<body2>.*?)\n  \}\n', t, re.S)
if old_parse:
    t = t.replace(old_parse.group(0),
                  "  /// Parser — reads a Bangla/English prompt blob and extracts 'Roll'/'রোল' into the roll input.\n"
                  "  void _parsePromptText(String raw) {\n"
                  "    String? roll;\n"
                  "    _bunkParsePrompt(raw, (v) => roll = v);\n"
                  "    if (roll != null && roll!.isNotEmpty) {\n"
                  "      setState(() => _rollCtl.text = roll!);\n"
                  "    }\n"
                  "  }\n")
wr(P, t)
print('  PATCHED  instance methods -> top-level delegators')

# ---------------------------------------------------------------- [4] dialog call site → top-level helper
t = rd(P)
o_call = "ClipboardData(text: _promptTemplate()),"
n_call = "ClipboardData(text: _bunkPromptTemplate(classLabel: widget.classLabel)),"
if t.count(o_call) == 1:
    t = t.replace(o_call, n_call)
    wr(P, t)
    print('  PATCHED  dialog copy -> _bunkPromptTemplate(classLabel:...)')
else:
    print('  NOTE     dialog call-site anchor count=%d (already other form)' % t.count(o_call))

# ---------------------------------------------------------------- [5] ASCII-ish sanity
t = rd(P)
print('\n--- final consistency ---')
print('  _bunkPromptTemplate(  defs=%d' % t.count('String _bunkPromptTemplate({required String classLabel})'))
print('  _bunkPromptTemplate(classLabel:  calls=%d' % t.count('_bunkPromptTemplate(classLabel:'))
print('  services.dart import: %d' % t.count("import 'package:flutter/services.dart';"))
print('  Clipboard occurrences : %d' % t.count('Clipboard'))
