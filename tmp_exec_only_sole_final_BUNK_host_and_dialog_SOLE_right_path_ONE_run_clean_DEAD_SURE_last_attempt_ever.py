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


t = rd(P)

# ---------------------------------------------------------------- [A] services import + closure
one(P, "import 'package:flutter/material.dart';\n",
    "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';\n",
    'services import')

# ---------------------------------------------------------------- [B] host delegator -> top-level helper
t = rd(P)
one(P, "  String _promptTemplate() =>\n      _promptTemplate(classLabel: widget.classLabel),",
    "  String _promptTemplate() =>\n"
    "      _promptTemplate(classLabel: widget.classLabel,\n"
    "          classHasGroup: widget.classLabel.toLowerCase().contains('group')),",
    'host delegator args')

# ---------------------------------------------------------------- [C] dialog call -> top-level helper
t = rd(P)
one(P, "ClipboardData(text: _promptTemplate()),",
    "ClipboardData(text: _promptTemplate(\n"
    "          classLabel: widget.classLabel,\n"
    "          classHasGroup: widget.classLabel.toLowerCase().contains('group'))),",
    'dialog call')
print('\n===== check picture ====')
t = rd(P)
print('  services import=%d  top-level helper def=%d  host delegator=%d  dialog call=%d' % (
    t.count("import 'package:flutter/services.dart';"),
    t.count('String _promptTemplate({required String classLabel,'),
    t.count('String _promptTemplate() =>'),
    t.count('ClipboardData(text: _promptTemplate(')))
