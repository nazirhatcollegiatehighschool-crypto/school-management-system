import io, os, glob

BASE = 'C:/Users/WALTON/Desktop/school-system'
GL = 'সুবিধা ঘর'       # who-is-free title kept
CANNOT = 'পারছেন না'
FREE = 'ফ্রি'
CHIP = 'বাঙ্ক'


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


def rep(p, o, n, lab, required=1):
    t = rd(p); c = t.count(o)
    if c != required:
        raise SystemExit('ANCHOR %-30s count=%d %r' % (lab, c, o[:80]))
    wr(p, t.replace(o, n))
    print('PATCHED  %-30s ok' % lab)


# ================================================================ [1] teacher who_is_free — bunk chip under status line
# real builder anchor (who_is_free file): the busy/period conditional text
rep('apps/teacher_app/lib/screens/who_is_free_screen.dart',
    "child: Text(free ? '" + FREE + "' : 'ব্যস্ত — ${t['current_class']?['subject_name'] ?? ''} (${_slotDisplayName(t['current_slot'])})')",
    "child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [\n"
    "                    Text(free ? '" + FREE + "' : 'ব্যস্ত — ${t['current_class']?['subject_name'] ?? ''} (${_slotDisplayName(t['current_slot'])})'),\n"
    "                    if (free && (t['is_escape'] == true || t['is_escape'] == 1))\n"
    "                      Chip(label: const Text('" + CHIP + "'), visualDensity: VisualDensity.compact, backgroundColor: Colors.red.shade50, labelStyle: TextStyle(color: Colors.red.shade700)))",
    'teacher bunk chip')

# ================================================================ [2] guardian routine_view — escape chip in slot chip
rep('apps/guardian_app/lib/widgets/routine_view.dart',
    "child: Text(_slotDisplayName(slot), style: const TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w600)),",
    "child: Text((slotEscape(slot) ? (_slotDisplayName(slot) + ' (" + CHIP + ")') : _slotDisplayName(slot)), style: TextStyle(fontSize: 13, color: slotEscape(slot) ? Colors.red : Colors.black87, fontWeight: FontWeight.w600)),",
    'guardian slot chip')

# ================================================================ [3] admin routines matrix — escape tick beside name
rep('apps/admin_app/lib/screens/routines_screen.dart',
    ",\n              isSchoolDay: (slot['is_school_day'] ?? true) == true,",
    ",\n              isSchoolDay: (slot['is_school_day'] ?? true) == true,\n              escape: (slot['is_escape'] ?? false) == true,",
    'admin matrix escape')
