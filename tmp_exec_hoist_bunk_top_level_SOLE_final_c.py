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


def one(p, o, n, lab):
    t = rd(p)
    c = t.count(o)
    if c != 1:
        raise SystemExit('ANCHOR %-22s count=%d %r' % (lab, c, o[:70]))
    wr(p, t.replace(o, n))
    print('  PATCHED  %-22s ok' % lab)


# ------------------------------------------------------------- SERVICES IMPORT (Clipboard)
one(P, "import 'package:flutter/material.dart';\n",
    "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';\n",
    'services import')

# ------------------------------------------------------------- HOIST: top-level template + roll parser,
#            used by BOTH the host screen state and the import dialog (the two live in
#            separate State classes — a private host method is invisible to the dialog).
import re
t = rd(P)
m = re.search(
    r"  /// চ structural Bengali copy template — key fields \+ ID is auto/roll is manual\.\n"
    r"  String _promptTemplate\(\) \{\n(?P<body>.*?)\n  \}\n",
    t, re.S)
assert m, 'host _promptTemplate block not found'
body = m.group('body')
t2 = t.replace(m.group(0), '')

hoist = (
    "\n/// চ structural bilingual copy template — key fields + ID auto / roll manual.\n"
    "String _bunkPromptTemplate({required String classLabel, required bool hasGroup}) {\n"
    + body.replace('widget.classLabel', 'classLabel') +
    "\n}\n"
)
anchor = "class StudentRegistrationScreen extends StatefulWidget {"
assert t2.count(anchor) == 1
t3 = t2.replace(anchor, hoist + "\n" + anchor, 1)

# host thin delegator keeps any existing in-file `_promptTemplate()` calls working:
dleg = (
    "  /// Delegates to the top-level Bengali copy template helper (shared host+dialog).\n"
    "  String _promptTemplate() => _bunkPromptTemplate(\n"
    "        classLabel: widget.classLabel,\n"
    "        hasGroup: widget.classLabel.toLowerCase().contains('group'));\n"
)
anchor2 = "  /// Parser — reads a Bangla/English prompt blob and extracts Roll/রোল into the roll input."
assert t3.count(anchor2) == 1
t4 = t3.replace(anchor2, dleg + anchor2, 1)
wr(P, t4)
print('  PATCHED  hoisted top-level _bunkPromptTemplate + host delegator')

# ------------------------------------------------------------- DIALOG call site -> hoisted helper
t = rd(P)
one(P, "ClipboardData(text: _promptTemplate()),",
    "ClipboardData(text: _bunkPromptTemplate(\n"
    "          classLabel: widget.classLabel,\n"
    "          hasGroup: widget.classLabel.toLowerCase().contains('group'))),",
    'dialog copy call')

t = rd(P)
print('\n  ---- consistency ----')
print('   services import=%-3d  top-level def=%-3d  host delegator=%-3d  dialog _bunkPromptTemplate(ref)=%-3d' % (
    t.count("import 'package:flutter/services.dart';"),
    t.count("String _bunkPromptTemplate({required String classLabel,"),
    t.count("String _promptTemplate() => _bunkPromptTemplate("),
    t.count("ClipboardData(text: _bunkPromptTemplate(")))
