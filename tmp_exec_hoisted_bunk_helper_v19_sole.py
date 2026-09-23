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


def rep(p, o, n, lab):
    t = rd(p)
    c = t.count(o)
    if c != 1:
        raise SystemExit('ANCHOR %-22s count=%d %r' % (lab, c, o[:70]))
    wr(p, t.replace(o, n))
    print('  PATCHED  %-22s ok' % lab)


# [1] services import (for Clipboard)
rep(P,
    "import 'package:flutter/material.dart';\n",
    "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';\n",
    'services import')

# [2] dialog call site — it is inside the import DIALOG class. `_promptTemplate` is NOT visible
#     there (it is an instance member of the HOST registration state). Hoist a top-level helper
#     and delegate: keep the host delegator + make the dialog use the hoisted function.
t = rd(P)
# --- capture the exact bare call currently present at ~444 ---
for o in ("ClipboardData(text: _promptTemplate()),",
          "ClipboardData(text: _promptTemplate),"):
    if t.count(o) == 1:
        print('  FOUND call form: %s' % o.strip())
        break
else:
    raise SystemExit('no dialog ClipboardData anchor found')

# --- insert top-level helper after the last import line ---
hoisted = (
    "\n/// চ structural Bengali copy template — key fields + ID is auto/roll is manual.\n"
    "String _bunkBunkCopyTemplate({\n"
    "  required String classLabel,\n"
    "  required bool classHasGroup,\n"
    "}) {\n"
    "  final section = classHasGroup ? 'গ্রুপ (Group) ± ' : 'বিভাগ (Section) ± ';\n"
    "  return '''CLSS: ${classLabel}\n"
    "ছাত্র / ছাত্রীর তথ্য অনুসরণ করুন বিশ্লেষণ করে নীচের FORMAT-এ ফেরত পাঠান — JSON row:\n"
    "{ \"name\": \"...\", \"roll\": \"বাস্তব রোল\", \"dob\": \"YYYY-MM-DD\", \"religion\": \"...\",\n"
    "  \"guardian_name\": \"...\", \"guardian_phone\": \"...\", \"father_name\": \"...\",\n"
    "  \"mother_name\": \"...\", \"birth_cert_no\": \"...\", \"address\": \"...\",\n"
    "  \"${classHasGroup ? 'group' : 'section'}\": \"...\" }\n"
    "\n"
    "RULES:\n"
    "- Student কোড (Student Code / Code): সার্ভার স্বয়ংক্রিয়ভাবে তৈরি করবে — লিখবেন না।\n"
    "- রোল (Roll): শুধু এই ফিল্ডটি ম্যানুয়াল/ইমপোর্ট prompt থেকে আসে — বাধ্যতামূলকভাবে ভরুন যাচাই করে,\n"
    "  প্লিজ school-এর এই ক্লাসের (${classLabel}) ${section}স্বয়ংক্রিয় Code+Roll থেকে আলাদা ভাবে রেখে দিন।\n"
    "- বিশ্লেষণ করে Prompt-এ নামের পাশে থাকা রোলটি পড়ে 'roll' কী-তে ভরুন.''';
}\n"
)
anchor = "class StudentRegistrationScreen extends StatefulWidget {"
c = t.count(anchor)
if c != 1:
    raise SystemExit('class anchor count=%d' % c)
t = t.replace(anchor, hoisted + "\n" + anchor, 1)

# [3] dialog call -> hoisted top-level function (pass classLabel from widget)
import re
t2 = re.sub(
    r"ClipboardData\(text: _promptTemplate\(\)\),",
    "ClipboardData(text: _bunkBunkCopyTemplate(\n"
    "        classLabel: widget.classLabel,\n"
    "        classHasGroup: widget.classLabel.toLowerCase().contains('group'))),",
    t, count=1)

# [4] host state: keep a thin delegator so old calls still work (deliberate, harmless)
t3 = rd(P)
host_old = "  String _promptTemplate() {\n"
if t3.count(host_old) == 1:
    raise SystemExit('host-delegator anchor got eaten unexpectedly')
if '_promptTemplate()' in t3:
    raise SystemExit('host delegator still present (should have been hoisted)')

wr(P, t2)
print('  PATCHED  dialog -> hoisted _bunkBunkCopyTemplate')

# verify
t2 = rd(P)
print('  top-level defs=%d   dialog calls=%d   services import=%d' % (
    t2.count('String _bunkBunkCopyTemplate('),
    t2.count('_bunkBunkCopyTemplate(') - 1,
    t2.count("import 'package:flutter/services.dart';")))
