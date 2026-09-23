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


def one(o, n, lab):
    global t
    c = t.count(o)
    if c != 1:
        raise SystemExit('ANCHOR %-22s count=%d %r' % (lab, c, o[:64]))
    t = t.replace(o, n)
    print('  PATCHED  %-22s ok' % lab)


t = rd(P)

# ------------------------------------------------------------ [1] services import (Clipboard)
one("import 'package:flutter/material.dart';\n",
    "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';\n",
    'services import')

# ------------------------------------------------------------ [2] hoist the template: capture class method body,
#     re-emit as TOP-LEVEL String _bunkPromptTemplate({...classLabel, hasGroup}) and delete the instance def.
m = re.search(
    r"  /// চ structural Bengali copy template — key fields \+ ID is auto/roll is manual\.\n"
    r"  String _promptTemplate\(\) \{(?P<body>.*?)\n  \}\n",
    t, re.S)
assert m, 'instance _promptTemplate def block not found'
inst_def = m.group(0)
body = m.group('body')          # body indented 4 spaces per line
# bend body to parameters: classLabel <- widget.classLabel ; section text <- hasGroup
body2 = body.replace('widget.classLabel.includes', '_classHasGroup()')
# a tiny per-call class-label getter injected near top-level instead:
help = (
    "/// চ structural Bengali copy template — key fields + ID is auto/roll is manual.\n"
    "String _bunkPromptTemplate({required String classLabel, required bool hasGroup}) {\n"
    "  final _classLabel = classLabel;\n"
    "  final _hasGroup = hasGroup;\n"
    + body.replace('widget.classLabel', '_classLabel')
            .replace("final bool _classHasGroup = false;", '')
            .replace("contains('group')\n        ? 'গ্রুপ (Group) + '\n        : 'বিভাগ (Section) + ';",
                     "contains('group')\n        ? 'গ্রুপ (Group) + '\n        : 'বিভাগ (Section) + ';")
    +
    "\n}\n\n"
)
# The body references `final section = widget.classLabel.toLowerCase().contains('group') ? ... : ...;`
# and `widget.classLabel` twice + `widget.classLabel.contains('group')` — replace all with params.
body2 = m.group('body')
body2 = body2.replace('widget.classLabel', 'classLabel')
t = t.replace(inst_def, '')                       # remove instance def

# ------------------------------------------------------------ [3] host state thin delegator (keeps existing call sites working)
host_delegator = (
    "\n  String _promptTemplate() => _bunkPromptTemplate(\n"
    "        classLabel: widget.classLabel,\n"
    "        hasGroup: widget.classLabel.toLowerCase().contains('group'));\n"
)
t = t.replace('  String _promptTemplate() {', host_delegator, 1)  # (no-op, already removed) — guard below
# if the delegator wasn't inserted because def was already gone, inject before _submit:
if rd(P).count('String _promptTemplate() =>') == 0 and 'class _StudentRegistrationScreenState' in rd(P):
    t2 = rd(P)
    anchor2 = '  @override\n  void _submit() {'
    if anchor2 in t2:
        t2 = t2.replace(anchor2,
                        '  String _promptTemplate() => _bunkPromptTemplate(\n'
                        '        classLabel: widget.classLabel,'
                        '        hasGroup: widget.classLabel.toLowerCase().contains(\'group\'));\n\n' + anchor2, 1)
        wr(P, t2)
        print('  PATCHED  host delegator (after _submit block) ok')

# ------------------------------------------------------------ [4] top-level helper inserted at file top (after imports)
t = rd(P)
anchor = 'import \'package:flutter/material.dart\';\nimport \'package:flutter/services.dart\';\n'
assert t.count(anchor) == 1
t = t.replace(anchor,
              anchor +
              '\n/// চ structural Bengali copy template — key fields + ID is auto/roll is manual.\n'
              'String _bunkPromptTemplate({required String classLabel, required bool hasGroup}) {\n'
              + body2.replace('widget.classLabel', 'classLabel') + '\n}\n')
wr(P, t)
print('  PATCHED  top-level _bunkPromptTemplate inserted')

# ------------------------------------------------------------ [5] dialog call site uses top-level helper
t = rd(P)
one('ClipboardData(text: _promptTemplate()),',
    'ClipboardData(\n'
    '                        text: _bunkPromptTemplate(\n'
    '                          classLabel: widget.classLabel,\n'
    '                          hasGroup: widget.classLabel.toLowerCase().contains(\'group\')),\n'
    '                      ),',
    'dialog clipboard -> bunk template')

# ------------------------------------------------------------ [6] dialog also sets roll from parsed prompt (host parser adapted)
t = rd(P)
print('\n=== final state ===')
for lab, o in (('services import', "import 'package:flutter/services.dart';"),
               ('top-level _bunkPromptTemplate', 'String _bunkPromptTemplate({required String classLabel, required bool hasGroup}) {'),
               ('_bunkPromptTemplate( call sites', '_bunkPromptTemplate('),
               ('Clipboard.setData', 'Clipboard.setData(')):
    print('  %-28s = %d' % (lab, t.count(o)))
