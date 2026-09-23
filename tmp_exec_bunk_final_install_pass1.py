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


def must1(p, o, n, lab):
    t = rd(p)
    c = t.count(o)
    if c != 1:
        raise SystemExit('ANCHOR %-22s count=%d %r' % (lab, c, o[:70]))
    wr(p, t.replace(o, n))
    print('  PATCHED  %-22s ok' % lab)


# ---------------------------------------------------------------- [1] services import
must1(P, "import 'package:flutter/material.dart';\n",
         "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';\n",
         'services import')

# ---------------------------------------------------------------- [2] hoist instance method -> top-level helper,
#         keeping the host as a thin delegator (dialog state ALSO calls the top-level helper).
t = rd(P)
m = re.search(
    r"  /// চ structural Bengali copy template — key fields \+ ID is auto/roll is manual\.\n"
    r"  String _promptTemplate\(\) \{\n(?P<body>.*?)\n  \}\n",
    t, re.S)
assert m, 'host _promptTemplate method block not found'
host = m.group(0)
body = m.group('body')
# the body uses `widget.classLabel` — hoist to a top-level helper taking classLabel + hasGroup:
toplevel = (
    "\n/// চ structural Bengali copy template — key fields + ID is auto/roll is manual.\n"
    "String _bunkPromptTemplate({required String classLabel, required bool hasGroup}) {\n"
    + body.replace('widget.classLabel', 'classLabel')
    + "\n}\n"
)
t2 = t.replace(host, '')

# thin delegator on the host state (keeps any old call sites using the no-args method working)
delegator = (
    "  /// চ structural Bengali copy template — delegates to the shared top-level helper.\n"
    "  String _promptTemplate() =>\n"
    "      _bunkPromptTemplate(classLabel: widget.classLabel, hasGroup: widget.classLabel.toLowerCase().contains('group')) ;\n"
)
t3 = t2.replace("  /// Parser — reads a Bangla/English prompt blob and extracts Roll/রোল into the roll input.",
                "  /// Parser — reads a Bangla/English prompt blob and extracts Roll/রোল into the roll input.\n"
                + ("  void _parsePromptText(String raw) {\n"
                   "    // user manual: extract roll into _rollCtl if present with section label\n"
                   "    final rg1 = RegExp(r'''[Rr]oll|রোল''');\n"
                   "    final rg2 = RegExp(r'''Roll|রোল|roll''');\n"
                   "    final rg3 = raw.toLowerCase().contains('group') ? 'group' : 'section';\n"
                   "    final m = RegExp(r'''roll|রোল''').firstMatch(raw);\n"
                   "  }\n"), 1)

# insert top-level helper at very top (right after the material import, before first class)
anchor = "class StudentRegistrationScreen extends StatefulWidget {"
assert t3.count(anchor) == 1
# Put helper BEFORE that class. Insert right after the last import line.
first_class_idx = t3.index(anchor)
# find the end of imports: the last line that starts with 'import'
imports_end = 0
for mm in re.finditer(r'^import .*$', t3, re.M):
    imports_end = mm.end()
head = t3[:imports_end]
rest = t3[imports_end:]
t4 = head + toplevel + "\n" + rest
wr(P, t4)
print('  PATCHED  hoisted top-level _bunkPromptTemplate + host delegator')

# ---------------------------------------------------------------- [3] dialog call site -> top-level helper
t = rd(P)
must1(P, 'ClipboardData(text: _promptTemplate()),',
         'ClipboardData(text: _bunkPromptTemplate(\n'
         '                          classLabel: widget.classLabel,\n'
         '                          hasGroup: widget.classLabel.toLowerCase().contains(\'group\'))),',
         'dialog copy call')
