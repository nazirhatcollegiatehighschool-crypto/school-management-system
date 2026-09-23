# -*- coding: utf-8 -*-
from __future__ import print_function
import io, os, glob

BASE = 'C:/Users/WALTON/Desktop/school-system'
APPS = os.path.join(BASE, 'apps')

BANK = 'বাঙ্ক'
BN = 'বাঙ্ক'
CLASS_FAKI = 'ক্লাস-ফাঁকি'

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
        raise SystemExit('ANCHOR %-28s count=%d %r' % (lab, c, o[:70]))
    wr(p, t.replace(o, n))
    print('PATCHED  %-28s ok' % lab)

# ---------------------------------------------------------------- teach — who_is_free tile: bunk chip on escape rows
rep('apps/teacher_app/lib/screens/who_is_free_screen.dart',
    "final bool is_escape = false;",
    "final bool is_escape = false;\n    final bool bunkNow = is_escape && free;",
    'who_is_free bunk flag',
    )
rep('apps/teacher_app/lib/screens/who_is_free_screen.dart',
    "if (bunkNow)",
    "if (bunkNow) print('bunk');",
    'who_is_free sentinel')

# ---------------------------------------------------------------- guardian — routine_view: escape chip in slot tile
rep('apps/guardian_app/lib/widgets/routine_view.dart',
    "child: Text(_slotDisplayName(slot), style: const TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w600)),",
    "child: Text(escapeDetected ? (_slotDisplayName(slot) + ' (বাঙ্ক)') : _slotDisplayName(slot), style: TextStyle(fontSize: 13, color: escapeDetected ? Colors.red : Colors.black87, fontWeight: FontWeight.w600)),",
    'guardian routine escape chip')

# ---------------------------------------------------------------- admin — routines matrix cell: escape dot
print('\n=== escape/bunk Flutter surface ===')
print('REMEMBER: flutter analyze MUST run on any machine with the Flutter SDK;')
print('the Python byte-patcher cannot type-check Dart (no host SDK here).')
