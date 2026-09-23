# -*- coding: utf-8 -*-
from __future__ import print_function
import io, os

BASE = 'C:/Users/WALTON/Desktop/school-system'
BN = '\u09AC\u09BE\u0982\u0995'


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


def rep(p, o, n, lab):
    t = rd(p); c = t.count(o)
    if c != 1:
        raise SystemExit('ANCHOR %-24s count=%d %r' % (lab, c, o[:64]))
    io.open(os.path.join(BASE, p), 'w', encoding='utf-8', newline='').write(t.replace(o, n))
    print('PATCHED  %-24s ok' % lab)


# ================================================================ [teacher] who_is_free — escape chip below free/busy
rep('apps/teacher_app/lib/screens/who_is_free_screen.dart',
    "Text(periods.isEmpty ? '' : '', style: const TextStyle(fontSize: 12))",
    "Text(periods.isEmpty ? '' : '', style: const TextStyle(fontSize: 12))\n"
    "                    if (t['is_escape'] == true || t['is_escape'] == 1 || t['is_escape'] == '1')\n"
    "                      Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(top: 4),\n"
    "                        child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),\n"
    "                          decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(6),\n"
    "                              border: Border.all(color: const Color(0xFFE57373))),\n"
    "                          child: Row(mainAxisSize: MainAxisSize.min, children: const [\n"
    "                            Icon(Icons.warning_amber, size: 14, color: Color(0xFFC62828)),\n"
    "                            SizedBox(width: 4),\n"
    "                            Text('" + BN + " — ক্লাস-ফাঁকি', style: TextStyle(fontSize: 11, color: Color(0xFFC62828), fontWeight: FontWeight.bold)),\n"
    "                          ])))),",
    'who_is_free escape chip')

# ================================================================ [guardian] routine_view — escape dot on slot label
rep('apps/guardian_app/lib/widgets/routine_view.dart',
    "'CLASS_${m.group(1)} period'.toUpperCase()",
    "'CLASS_${m.group(1)} period' + (isEscape ? ' ·" + BN + "' : '')",
    'guardian routine slot escape')

print('\n=== escape/bunk (ক্লাস-ফাঁকি) — flutter touch ===')
print('two screens patched: teacher who_is_free (red বাঙ্ক chip) + guardian routine (·বাঙ্ক tag).')
print('\nNOTE — run on the Flutter machine (no SDK on this box):')
print('  cd apps/teacher_app  && flutter analyze && flutter run')
print('  cd apps/guardian_app && flutter analyze && flutter run')
