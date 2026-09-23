# -*- coding: utf-8 -*-
from __future__ import print_function
import io, os

BASE = 'C:/Users/WALTON/Desktop/school-system'
BN = '\u09AC\u09BE\u0982\u0995'
SS = 'স্লট'


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


def rep(p, o, n, lab):
    t = rd(p); c = t.count(o)
    if c != 1:
        raise SystemExit('ANCHOR %-26s count=%d %r' % (lab, c, o[:64]))
    wr(p, t.replace(o, n))
    print('PATCHED  %-26s ok' % lab)


# ================================================================ [teacher] who_is_free — বাংলা বাঙ্ক chip on escape rows
rep('apps/teacher_app/lib/screens/who_is_free_screen.dart',
    "child: Text('' , style: const TextStyle(fontSize: 12)),",
    "child: isEscape\n"
    "              ? Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),\n"
    "                decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(4),\n"
    "                    border: Border.all(color: const Color(0xFFEF9A9A))),\n"
    "                child: const Text('বাঙ্ক · ক্লাস-ফাঁকি', style: TextStyle(fontSize: 11, color: Color(0xFFC62828), fontWeight: FontWeight.bold)))\n"
    "              : const Text('', style: TextStyle(fontSize: 12)),",
    'who_is_free escape chip')

print('\n=== escape (ক্লাস-ফাঁকি) Flutter chip staged for review ===')
for p in ('apps/teacher_app/lib/screens/who_is_free_screen.dart',
          'apps/guardian_app/lib/widgets/routine_view.dart',
          'apps/admin_app/lib/screens/routines_screen.dart'):
    print('  %-58s escapes=%d' % (p, rd(p).count('বাঙ্ক')))
print()
print('Run on the Flutter-SDK machine (this box has none):')
print('  cd apps && for a in teacher_app guardian_app admin_app; do (cd $a && flutter analyze); done')
