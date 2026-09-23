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


# ---------------------------------------------------------------- [1] services import (Clipboard)
one(P, "import 'package:flutter/material.dart';\n",
    "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';\n",
    'services import')

# ---------------------------------------------------------------- [2] hoist the template into a TOP-LEVEL helper
t = rd(P)
m = re.search(
    r"  /// চ structural Bengali copy template — key fields \+ ID is auto/roll is manual\.\n"
    r"  String _promptTemplate\(\) \{\n(?P<body>.*?)\n  \}\n",
    t, re.S)
assert m, 'instance _promptTemplate block not found'
body = m.group('body')
# body uses `widget.classLabel`; for a top-level fn we pass classLabel + hasGroup.
top = (
    "\n/// চ structural Bengali copy template — key fields + ID is auto/roll is manual.\n"
    "String _bunkPromptTemplate({required String classLabel, required bool hasGroup}) {\n"
    + body.replace('widget.classLabel', 'classLabel')
    + "\n}\n"
)
t2 = t.replace(m.group(0), '')
# host delegator (tiny) so any pre-existing no-arg call sites still work:
t3 = t2.replace(
    "  /// Parser — reads a Bangla/English prompt blob and extracts Roll/রোল into the roll input.",
    "  /// Delegates to the top-level Bengali copy template helper.\n"
    "  String _promptTemplate() => _bunkPromptTemplate(\n"
    "        classLabel: widget.classLabel,\n"
    "        hasGroup: widget.classLabel.toLowerCase().contains('group'));\n"
    "\n"
    "  /// Parser — reads a Bangla/English prompt blob and extracts Roll/রোল into the roll input.",
    1)
anchor = "class StudentRegistrationScreen extends StatefulWidget {"
assert t3.count(anchor) == 1
t4 = t3.replace(anchor, top.strip() + "\n\n" + anchor, 1)
wr(P, t4)
print('  PATCHED  hoisted _bunkPromptTemplate top-level + host delegator')

# ---------------------------------------------------------------- [3] dialog call site -> top-level helper
t = rd(P)
one(P, "ClipboardData(text: _promptTemplate()),",
    "ClipboardData(text: _bunkPromptTemplate(\n"
    "            classLabel: widget.classLabel,\n"
    "            hasGroup: widget.classLabel.toLowerCase().contains('group'))),",
    'dialog copy -> hoisted')

# ---------------------------------------------------------------- [4] host dialog classes per class; verify
t = rd(P)
print('  top-level defs=%d  delegator=%d  dialog calls=%d  services import=%d' % (
    len(re.findall(r'^String _bunkPromptTemplate\(\{', t, re.M)),
    t.count('String _promptTemplate() =>'),
    t.count('_bunkPromptTemplate('),
    t.count("import 'package:flutter/services.dart';")))
