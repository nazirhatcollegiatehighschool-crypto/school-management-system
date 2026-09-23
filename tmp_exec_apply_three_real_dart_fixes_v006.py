# -*- coding: utf-8 -*-
import io, os
BASE = 'C:/Users/WALTON/Desktop/school-system'


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


def one(lab, o, n):
    t = rd(P)
    c = t.count(o)
    if c != 1:
        raise SystemExit('ANCHOR %-22s count=%d %r' % (lab, c, o[:70]))
    wr(P, t.replace(o, n))
    print('  PATCHED  %-22s ok' % lab)


P = 'apps/teacher_app/lib/screens/student_registration_screen.dart'

# [A] Ci=2 services dup -> 1 (byte-сиг exact dup block)
o1 = ("import 'package:flutter/material.dart';\n"
      "import 'package:flutter/material.dart';\n"
      "import 'package:flutter/services.dart';\n"
      "import 'package:flutter/services.dart';\n")
one('services dup -> 1', o1,
    "import 'package:flutter/material.dart';\n"
    "import 'package:flutter/services.dart';\n")

# [B] 444:43 undefined _promptTemplate -> top-level _bunkPromptTemplate shared helper call
one('dialog copy -> bunk helper',
    "ClipboardData(text: _promptTemplate()),",
    "ClipboardData(text: _bunkPromptTemplate(\n"
    "        classLabel: widget.classLabel,\n"
    "        classHasGroup: widget.classLabel.toLowerCase().contains('group'))),")

# [C] host delegator -> same top-level helper (thin)
o3 = ("  String _promptTemplate() => _bunkPromptTemplate(\n"
      "        classLabel: widget.classLabel,\n"
      "        classHasGroup: widget.classLabel.toLowerCase().contains('group'));\n")
# does host already have it (either form)?
t = rd(P)
if t.count("do_renderable import '../api.dart';") or 'belt':
    pass
if "String _promptTemplate() {" in t:
    one('host delegator inject', 
        "  String _promptTemplate() {",
        "  String _promptTemplate() => _bunkPromptTemplate(\n"
        "        classLabel: widget.classLabel,\n"
        "        classHasGroup: widget.classLabel.toLowerCase().contains('group'));\n"
        "\n"
        "  String _unused_old_host_body_guard() {", 1)
else:
    print('  (host delegator already thin — skip C)')
