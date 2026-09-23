# -*- coding: utf-8 -*-
from __future__ import print_function
import io, re, glob, subprocess, os

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


def rep(p, o, n, lab):
    t = rd(p); c = t.count(o)
    if c != 1:
        raise SystemExit('ANCHOR %-24s count=%d %r' % (lab, c, o[:88]))
    wr(p, t.replace(o, n)); print('  PATCHED  %-26s ok' % lab)


P = 'apps/teacher_app/lib/screens/student_registration_screen.dart'

# ---- 1) the def is a METHOD (line 125): keep `String _promptTemplate() {`
#         but the call at 444 currently reads `_promptTemplate()` -> re-verify exact bytes
t = rd(P); L = t.splitlines()
print('  def line 125: %r' % L[124][:60])
i = next(i for i, l in enumerate(L, 1) if 'ClipboardData' in l)
print('  call line %d: %r' % (i, L[i - 1][:90]))
print('  call line %d: %r' % (i + 1, L[i][:90]))
