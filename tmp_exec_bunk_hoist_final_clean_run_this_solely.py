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


t = rd(P)

# --- (A) remove the host-class method getter block (keep a thin host wrapper that
#         delegates to the NEW top-level helper). Match the exact current block:
import_services_anchor = "import 'package:flutter/material.dart';\n"
services = "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';\n"
one(P, import_services_anchor, services, 'services import')

# --- (B) capture the current method body to reuse its exact text as the top-level helper
m = re.search(
    r"  /// চ structural Bengali copy template — key fields \+ ID is auto/roll is manual\.\n"
    r"  String _promptTemplate\(\) \{(?P<body>.*?)\n  \}\n",
    t,
    re.S,
)
assert m, 'method block not found'
body = m.group('body')
# body is indented by 4 spaces as method content; top-level keeps same relative text minus 2 spaces
# (we keep exactly the text, only moving the closing of the string; minimal risk)
top_template = (
    "/// চ structural Bengali copy template — key fields + ID is auto/roll is manual.\n"
    "String _promptTemplate() {" + body + "\n}\n\n"
)
# remove from class
t2 = t.replace(m.group(0), "")

# --- put top-level helper + parser right after the imports (top of file), before `class`
insert_at = "class StudentRegistrationScreen extends StatefulWidget {"
assert t2.count(insert_at) == 1
t3 = t2.replace(
    insert_at,
    top_template
    + "/// Parser — reads a Bangla/English prompt blob and extracts Roll/রোল into a callback.\n"
    "void _parsePromptText(String raw, void Function(String?) onRoll) {\n"
    "  final rg1 = RegExp(r'''[Rr]oll|রোল''');\n"
    "  final m = rg1.firstMatch(raw);\n"
    "  if (m != null) {\n"
    "    final tail = raw.substring(m.end);\n"
    "    final mv = RegExp(r'[:=]?\\s*(\\d+)').firstMatch(tail);\n"
    "    if (mv != null) onRoll(mv.group(1));\n"
    "  }\n"
    "}\n\n"
    + insert_at,
)

# --- (C) the host class method `_parsePromptText(raw)` (instance) previously used setState
#         — now delegates to top-level helper; find current in-class definition:
old_parse = re.search(r"  void _parsePromptText\(String raw\) \{.*?\n  \}\n", t3, re.S)
if old_parse:
    t3 = t3.replace(old_parse.group(0),
                    "  void _parsePromptText(String raw) {\n"
                    "    setState(() => _parsePromptText(raw, (v) {\n"
                    "      if (v != null && v.isNotEmpty) _rollCtl.text = v;\n"
                    "    }));\n"
                    "  }\n")

# --- (D) dialog call site: use top-level _promptTemplate() (now in scope) — keep method-call form
o_call = "ClipboardData(text: _promptTemplate()),"
n_call = "ClipboardData(text: _promptTemplate()),"
# it is already the method-call form; just make sure there is no bare-getter leftover
t3 = t3.replace("ClipboardData(text: _promptTemplate),",
                "ClipboardData(text: _promptTemplate()),")

wr(P, t3)
print('  PATCHED  prompt helpers hoisted to top level')

# quick consistency
final = rd(P)
print('  top-level _promptTemplate(): %d defs — _promptTemplate() calls: %d' % (
    len(re.findall(r'^\s*String _promptTemplate\(\)', final, re.M)),
    final.count('_promptTemplate()') - 1))
print('  Clipboard.setData call: %r' %
      re.search(r'ClipboardData\(text: \w+\)', final).group(0))
print('  services import present: %s' % ("services.dart" in final))
