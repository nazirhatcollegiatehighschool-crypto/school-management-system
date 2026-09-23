# -*- coding: utf-8 -*-
from __future__ import print_function
import io, os

BASE = 'C:/Users/WALTON/Desktop/school-system'


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


def one(t, o, lab):
    c = t.count(o)
    if c != 1:
        raise SystemExit('ANCHOR %-26s count=%d %r' % (lab, c, o[:66]))
    return c


# ================================================================ teacher who_is_free — escape chip
p = 'apps/teacher_app/lib/screens/who_is_free_screen.dart'
t = rd(p)
O = "    final slot = t['current_class']?['slot_label']?.toString();\n    final periods = t['periods_today'] as List? ?? [];"
N = "    final slot = t['current_class']?['slot_label']?.toString();\n    final times = t['current_class']?['start_time']?.toString() ?? '';\n    final isEscape = t['is_escape'] == true || t['is_escape'] == 1 || t['is_escape'] == '1';\n    final periods = t['periods_today'] as List? ?? [];"
one(t, O, 'who_is_free tile head')
t = t.replace(O, N)

O2 = "                            Text(free ? 'ফ্রি' : 'ব্যস্ত — ${t['current_class']?['subject_name'] ?? ''} (${_slotDisplayName(slot)}$times)"
N2 = "                            Text(free ? 'ফ্রি' : 'ব্যস্ত — ${t['current_class']?['subject_name'] ?? ''} (${_slotDisplayName(slot)})"
one(t, O2, 'who_is_free tile busy text')
t = t.replace(O2, N2)

# append the bunk chip right after the busy/free line — anchor on the trailing
# of that same Text widget we just validated
O3 = "                              ),\n                              if (phone.isNotEmpty)\n                                IconButton("
one(t, O3, 'who_is_free actions row')
N3 = ("                              ),\n"
      "                              if (isEscape)\n"
      "                                Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),\n"
      "                                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),\n"
      "                                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6),\n"
      "                                        border: Border.all(color: Colors.red.shade300)),\n"
      "                                    child: const Text('বাঙ্ক (ক্লাস-ফাঁকি)', style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold)))),\n"
      "                              if (phone.isNotEmpty)\n"
      "                                IconButton(")
t = t.replace(O3, N3)
wr(p, t)
print('PATCHED  teacher who_is_free escape chip ok')

print('\n=== done: teacher who_is_free now shows a red "বাঙ্ক (ক্লাস-ফাঁকি)" chip on escape rows ===')
print('guardian routine_view + admin routines already surface slot names via helpers.')
print('Run on a Flutter SDK machine to type-check:\n  cd apps && cada um app && flutter analyze')
