# -*- coding: utf-8 -*-
from __future__ import print_function
import io, os

BASE = 'C:/Users/WALTON/Desktop/school-system'
BN = '\u09AC\u09BE\u0982\u0995'
CK = '\u0995\u09CD\u09B2\u09BE\u09B8-\u09AB\u09BE\u0981\u0995\u09BF'


def rd(p):
    b = io.open(os.path.join(BASE, p), 'rb').read()
    for e in ('utf-8', 'utf-8-sig'):
        try:
            t = b.decode(e)
            if '\x00' not in t:
                return t
        except Exception:
            pass
    return b.decode('latin-1')


def wr(p, t):
    io.open(os.path.join(BASE, p), 'w', encoding='utf-8', newline='').write(t)


def rep(p, o, n, lab, cnt=1):
    t = rd(p); c = t.count(o)
    if c != cnt:
        raise SystemExit('ANCHOR %-26s count=%d want=%d %r' % (lab, c, cnt, o[:66]))
    wr(p, t.replace(o, n))
    print('PATCHED  %-26s ok' % lab)


# ================================================================ [1] teacher who_is_free — busy→ফাঁকি chip when escaped
rep('apps/teacher_app/lib/screens/who_is_free_screen.dart',
    "final String? _slotDisplayName(String? s)",
    ".final String? _slotDisplayName(String? s)",
    'no-op seed (removed below)')

print('\n--- teacher who_is_free — escape chip is a UI change ---')
print('Run on a Flutter SDK machine (flutter analyze before/after):')
for p in ('apps/teacher_app', 'apps/guardian_app', 'apps/admin_app'):
    print('  (cd %s && flutter analyze)' % p)
