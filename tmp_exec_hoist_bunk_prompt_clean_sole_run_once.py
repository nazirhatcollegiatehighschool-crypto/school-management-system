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
        raise SystemExit('ANCHOR %-24s count=%d %r' % (lab, c, o[:70]))
    wr(p, t.replace(o, n))
    print('  PATCHED  %-24s ok' % lab)


# 1) services import (enables Clipboard)
one(P, "import 'package:flutter/material.dart';\n",
       "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';\n",
       'services import')

t = rd(P)

# 2) hoist the instance method -> top-level function bound to classLabel/sectionLabel
match = re.search(
    r"\n  /// চ structural Bengali copy template — key fields \+ ID is auto/roll is manual\.\n"
    r"  String _promptTemplate\(\) \{\n(?P<body>.*?)\n  \}\n",
    t, re.S)
if not match:
    raise SystemExit('instance _promptTemplate() block not found')
body = match.group('body')

hoisted = (
    "\n/// চ structural Bengali copy template — key fields + ID is auto/roll is manual.\n"
    "String _bunkPromptTemplate({\n"
    "  required String classLabel,\n"
    "  required String sectionLabel,\n"
    "}) {\n" + body + "\n}\n")
t = t.replace(match.group(0), hoisted, 1)

# 3) thin delegator inside the host class (so existing call at 444? no — 444 is the DIALOG class)
host_anchor = "  /// Parser — reads a Bangla/English prompt blob and extracts Roll/রোল into the roll input."
host_def = (
    "  /// Delegates to the top-level bunk copy template (shared with the import dialog).\n"
    "  String _promptTemplate() => _bunkPromptTemplate(\n"
    "        classLabel: widget.classLabel,\n"
    "        sectionLabel: widget.sectionLabel);\n"
    "\n"
    "  /// Parser — reads a Bangla/English prompt blob and extracts Roll/রোল into the roll input.")
if host_anchor in t:
    t = t.replace(host_anchor, host_def, 1)
else:
    # fallback: insert the delegator right before _parsePromptText's currently-unused def
    # (the dialog is a SEPARATE class; host instance doesn't even need it — the dialog uses the top-level fn)
    pass

# 4) SNAILY leftovers: kill any stray instance `void _parsePromptText(String raw) {` calls to _bunkParsePrompt
t = t.replace("ClipboardData(text: _promptTemplate),",
              "ClipboardData(text: _bunkPromptTemplate(\n"
              "                  classLabel: widget.classLabel,\n"
              "                  sectionLabel: widget.sectionLabel)),", 1)

# 5) fix remaining instance-wide `_promptTemplate` references (host class only)
t = re.sub(r"(?m)^(\s+)(ClipboardData\(text: _promptTemplate\()),?\s*$",
           r"\1\2),", t)
wr(P, t)

final = rd(P)
print('  DONE  top-level _bunkPromptTemplate defs=%d' %
      len(re.findall(r'^String _bunkPromptTemplate\(', final, re.M)))
print('        dialg call uses _bunkPromptTemplate: %d' %
      final.count('_bunkPromptTemplate('))
print('        leftover instance _promptTemplate in dialog scope: %d' %
      len(re.findall(r'\b_promptTemplate\b', final)))
