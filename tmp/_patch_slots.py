# -*- coding: utf-8 -*-
"""Slot-restructure helper: shared display mapping across the 3 Flutter apps.

Backend (supabase_migration_full.sql) now seeds 9 named slots:
  ASSEMBLY 10:00-10:15 (break), CLASS_1..CLASS_7 (10:15..16:00), LEISURE 13:15-14:00 (break).
The apps must show these as "Period 1..7" + Assembly(সমাবেশ) + Leisure(অবসর)
instead of the raw CLASS_n codes.
"""
import io

def rd(p):
    b = io.open(p, 'rb').read()
    for e in ('utf-8', 'utf-8-sig', 'utf-16', 'utf-16-le', 'utf-16-be'):
        try:
            t = b.decode(e)
            if '\x00' not in t:
                return t
        except Exception:
            pass
    return b.decode('latin-1')

def wr(p, t):
    io.open(p, 'w', encoding='utf-8', newline='').write(t)

# CLASS_n -> 'Period n' (UI keeps saying Period 1..7), ASSEMBLY -> assembly,
# LEISURE -> leisure. Falls back to the raw label for anything legacy
# (Assembly / 1st Period / Tiffin Break) so an un-seeded DB still reads sanely.
def dart_format_slot(expr):
    """expr: the Flutter expression that yields a slot label String."""
    return (
        "((m) { final l = ${expr}.toString().toLowerCase();\n"
        "    final m1 = RegExp(r'^class_?(\\d+)$').firstMatch(l);\n"
        "    if (m1 != null) return 'Period ${m1.group(1)}';\n"
        "    if (l.contains('assembly')) return '\\u09B8\\u09AE\\u09BE\\u09AC\\u09C7\\u09B6';\n"
        "    if (l.contains('leisure') || l.contains('tiffin') || l.contains('lunch'))\n"
        "        return '\\u0985\\u09AC\\u09B8\\u09B0';\n"
        "    if (l.contains('break')) return '\\u09AC\\u09BF\\u09B0\\u09A4\\u09BF';\n"
        "    return ${expr}.toString();\n"
        "  })(m)"
    )

def apply(path, subs):
    t = rd(path)
    for old, new, cnt in subs:
        n = t.count(old)
        if n != cnt:
            raise SystemExit("MISMATCH in %s: anchor found %d times (want %d): %s"
                             % (path, n, cnt, old[:70]))
        t = t.replace(old, new)
    wr(path, t)
    print("  patched", path)

if __name__ == '__main__':
    import sys
    print("module ready")
