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
        raise SystemExit('ANCHOR %-22s count=%d %r' % (lab, c, o[:70]))
    wr(p, t.replace(o, n))
    print('  PATCHED  %-22s ok' % lab)


# --------------------------------------------------------------- SERVICES IMPORT
one(P, "import 'package:flutter/material.dart';\n",
    "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';\n",
    'services import')

# --------------------------------------------------------------- HOIST host method -> top-level helper
t = rd(P)
m = re.search(
    r"  /// চ structural Bengali copy template — key fields \+ ID is auto/roll is manual\.\n"
    r"  String _promptTemplate\(\) \{\n(?P<body>.*?)\n  \}\n",
    t, re.S)
assert m, 'host _promptTemplate block not found'
body = m.group('body')
t2 = t.replace(m.group(0), '')

# top-level helper just before the widget class
anchor = "class StudentRegistrationScreen extends StatefulWidget {"
assert t2.count(anchor) == 1
top = (
    "\n/// চ structural Bengali copy template — key fields + ID is auto/roll is manual.\n"
    "String _bunkPromptTemplate({required String classLabel, required bool classHasGroup}) {\n"
    + body.replace('widget.classLabel', 'classLabel') +
    "\n}\n"
)
t3 = t2.replace(anchor, top + "\n" + anchor, 1)
wr(P, t3)
print('  PATCHED  hoisted _bunkPromptTemplate + host delegator')

# host delegator (keeps any existing `_promptTemplate()` calls in the host working)
t = rd(P)
anchor2 = "  /// Parser — reads a Bangla/English prompt blob and extracts Roll/রোল into the roll input."
assert t.count(anchor2) == 1
t = t.replace(anchor2,
              "  /// Delegates to the top-level Bengali copy template helper (shared with the import dialog).\n"
              "  String _promptTemplate() => _bunkPromptTemplate(\n"
              "        classLabel: widget.classLabel,\n"
              "        classHasGroup: widget.classLabel.toLowerCase().contains('group'));\n"
              "\n" + anchor2, 1)
wr(P, t)
print('  PATCHED  host thin delegator')

# --------------------------------------------------------------- DIALOG call site -> top-level helper
t = rd(P)
one(P, "ClipboardData(text: _promptTemplate()),",
    "ClipboardData(text: _bunkPromptTemplate(\n"
    "          classLabel: widget.classLabel,\n"
    "          classHasGroup: widget.classLabel.toLowerCase().contains('group'))),",
    'dialog call')
