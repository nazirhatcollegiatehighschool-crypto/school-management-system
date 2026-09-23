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
        raise SystemExit('ANCHOR %-20s count=%d %r' % (lab, c, o[:70]))
    wr(p, t.replace(o, n))
    print('  PATCHED  %-20s ok' % lab)


# --------------------------------------------------------------- [1] restore teacher_repo app imports that my
#     earlier import-splice clobbered (api + ocr_capture). Prepend fresh copies to be safe:
t = rd(P)
head = t[:120]
need = ("import '../api.dart';\n"
        "import 'ocr_capture_screen.dart';\n")
# (material/services already correct at top — just ensure api+ocr present once anywhere)
for imp in ("import '../api.dart';", "import 'ocr_capture_screen.dart';"):
    if t.count(imp) == 0:
        t = t.replace("import 'package:flutter/services.dart';\n",
                      "import 'package:flutter/services.dart';\n" + imp + "\n", 1)
        print('  RESTORED  %s' % imp)
wr(P, t)

# --------------------------------------------------------------- [2] hoisted shared top-level helper; the host
#     keeps a thin delegator `_promptTemplate()`; the dang dialog uses BUNK directly.
t = rd(P)
m = re.search(
    r"  /// চ structural Bengali copy template — key fields \+ ID is auto/roll is manual\.\n"
    r"  String _promptTemplate\(\) \{\n(?P<body>.*?)\n  \}\n",
    t, re.S)
assert m, 'host _promptTemplate block not found'
body = m.group('body')
t2 = t.replace(m.group(0), '')
anchor = "class StudentRegistrationScreen extends StatefulWidget {"
assert t2.count(anchor) == 1
hoist = (
    "\n/// চ structural Bengali copy template — key fields + ID is auto/roll is manual.\n"
    "String _bunkPromptTemplate({required String classLabel, required bool classHasGroup}) {\n"
    + body.replace('widget.classLabel', 'classLabel') + "\n}\n"
)
t3 = t2.replace(anchor, hoist + "\n" + anchor, 1)
wr(P, t3)
print('  PATCHED  hoisted top-level _bunkPromptTemplate')

# host delegator keeps any in-class `_promptTemplate()` callers working:
t = rd(P)
anchor2 = "  /// Parser — reads a Bangla/English prompt blob and extracts Roll/রোল into the roll input."
assert t.count(anchor2) == 1
t = t.replace(anchor2,
              "  /// Delegates to the top-level Bengali copy template helper (visible to the whole file).\n"
              "  String _promptTemplate() => _bunkPromptTemplate(\n"
              "        classLabel: widget.classLabel,\n"
              "        classHasGroup: widget.classLabel.toLowerCase().contains('group'));\n"
              "\n" + anchor2, 1)
wr(P, t)
print('  PATCHED  host thin delegator')

# --------------------------------------------------------------- [3] dialog call site -> hoisted top-level
t = rd(P)
one(P, "ClipboardData(text: _promptTemplate()),",
    "ClipboardData(text: _bunkPromptTemplate(\n"
    "          classLabel: widget.classLabel,\n"
    "          classHasGroup: widget.classLabel.toLowerCase().contains('group'))),",
    'dialog call')
