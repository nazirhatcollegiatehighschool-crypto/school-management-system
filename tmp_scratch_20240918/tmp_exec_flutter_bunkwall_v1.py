# -*- coding: utf-8 -*-
from __future__ import print_function
import io

BASE = 'C:/Users/WALTON/Desktop/school-system'

SLOT_SET = {'assembly': 'समाবেশ', 'leisure': 'অবসর'}


def rd(p):
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
    io.open(p, 'w', encoding='utf-8', newline='').write(t)


def rep(p, o, n, lab):
    t = rd(p); c = t.count(o)
    if c != 1:
        raise SystemExit('ANCHOR %-26s count=%d %r' % (lab, c, o[:64]))
    wr(p, t.replace(o, n))
    print('PATCHED  %-26s ok' % lab)


# ================================================================ [A] teacher — bunk chip on who_is_free tile
# Window anchor: the tile already shows _slotDisplayName? Find the exact dart.
