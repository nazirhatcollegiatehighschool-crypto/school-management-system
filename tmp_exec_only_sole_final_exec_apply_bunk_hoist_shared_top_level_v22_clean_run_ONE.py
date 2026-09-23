# -*- coding: utf-8 -*-
from __future__ import print_function
import io, os

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


def must1(p, o, n, lab):
    t = rd(p)
    c = t.count(o)
    if c != 1:
        raise SystemExit('ANCHOR %-22s count=%d %r' % (lab, c, o[:70]))
    wr(p, t.replace(o, n))
    print('  PATCHED  %-22s ok' % lab)


# ---------------------------------------------------------------- [1] Clipboard services import (top of file)
must1(P, "import 'package:flutter/material.dart';\n",
         "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';\n",
         'services import')

# ---------------------------------------------------------------- [2] top-level Bengali copy template helper
#     (used by BOTH the host state and the import dialog state — shared scope).
top_helper = (
    "\n"
    "/// চ structural Bengali copy template — key fields + ID is auto/roll is manual.\n"
    "String _bunkPromptTemplate({required String classLabel, required bool classHasGroup}) {\n"
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
    "- বিশ্লেষণ করে Prompt-এ নামের পাশে থাকা রোলটি পড়ে 'roll' কী-তে ভরুন.''';\n"
    "}\n"
)

host_anchor = "class StudentRegistrationScreen extends StatefulWidget {"
must1(P, host_anchor, top_helper + "\n" + host_anchor, 'top-level helper hoist')

# ---------------------------------------------------------------- [3] host state — thin delegator so existing
#     call sites inside the host class keep working (line ~157/125 delegates are private).
t = rd(P)
d1 = t.count("  String _promptTemplate() {")
d2 = t.count("  String _promptTemplate() =>")
print('  host _promptTemplate instance-decl-count=%d  delegator-count=%d' % (d1, d2))
if d1 == 1 and d2 == 0:
    old = re.search(r"  String _promptTemplate\(\) \{(?P<body>.*?)\n  \}\n", t, re.S)
    if old:
        t = t.replace(
            old.group(0),
            "  String _promptTemplate() => _bunkPromptTemplate(\n"
            "        classLabel: widget.classLabel,\n"
            "        classHasGroup: widget.classLabel.toLowerCase().contains('group'));\n",
        )
        wr(P, t)
        print('  PATCHED  host delegator -> top-level helper')
else:
    print('  (host instance method already a delegator — skipping)')

# ---------------------------------------------------------------- [4] dialog copy call -> top-level helper
t = rd(P)
must1(P, "ClipboardData(text: _promptTemplate()),",
         "ClipboardData(text: _bunkPromptTemplate(\n"
         "        classLabel: widget.classLabel,\n"
         "        classHasGroup: widget.classLabel.toLowerCase().contains('group'))),",
         'dialog copy -> top-level')

# ---------------------------------------------------------------- [5] summary
t = rd(P)
print('\n  services import  = %d' % t.count("import 'package:flutter/services.dart';"))
print('  top-level def    = %d' % t.count("String _bunkPromptTemplate({required String classLabel, required bool classHasGroup}) {"))
print('  host delegator   = %d' % t.count('classHasGroup: widget.classLabel.toLowerCase().contains(\'group\')),'))
print('  dialog call      = %d' % t.count('_bunkPromptTemplate('))
