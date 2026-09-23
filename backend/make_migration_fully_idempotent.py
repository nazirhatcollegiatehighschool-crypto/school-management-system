# -*- coding: utf-8 -*-
"""make_migration_fully_idempotent.py — производит окончательный, многократно выполняемый SQL."""

import io, re

SRC  = 'backend/supabase_migration_full.sql'
OUT  = 'backend/supabase_migration_full_fully_idempotent.sql'

# Первичные ключи: из схемы. Если таблица не в списке — 'id'.
PK_OF = {
  'time_slots': 'id', 'classes': 'id', 'subjects': 'id', 'users': 'id',
  'students': 'id', 'teachers': 'id', 'routines': 'id', 'routine_entries': 'id',
  'sessions': 'id', 'app_settings': 'key', 'time_slot_groups': 'id',
  'time_slot_sections': 'id', 'routine_blocks': 'id', 'marks': 'id',
  'ct_marks': 'id', 'attendance': 'id', 'notifications': 'id', 'homework': 'id',
  'device_tokens': 'id', 'holidays': 'id', 'guardian_links': 'id',
  'subjects_aliases': 'id', 'exam_shares': 'id', 'exams': 'id',
  'exam_events': 'id', 'results': 'id', 'exam_marks': 'id',
}

def read(p):
    b = io.open(p, 'rb').read()
    for enc in ('utf-8', 'utf-8-sig'):
        try:
            t = b.decode(enc)
            if chr(0) not in t:
                return t
        except Exception:
            pass
    return b.decode('latin-1')

def split_statements(sql):
    """Делит на ';' только вне кавычек '..' / ".." / $$..$$."""
    stmts, buf, i, n = [], [], 0, len(sql)
    q = dollar = None
    while i < n:
        c = sql[i]
        if dollar is not None:
            buf.append(c)
            if sql.startswith(dollar, i):
                buf.append(dollar)
                i += len(dollar)
                dollar = None
            else:
                i += 1
            continue
        if q:
            buf.append(c)
            if c == q and (i == 0 or sql[i - 1] != '\\'):
                q = None
            i += 1
            continue
        if c in ("'", '"'):
            q = c
            buf.append(c)
            i += 1
            continue
        m = re.match(r'(?s)\$[A-Za-z_][A-Za-z0-9_]*\$|\$\$', sql[i:])
        if c == '$' and m:
            dollar = m.group(0)
            buf.append(dollar)
            i += len(dollar)
            continue
        if c == ';':
            stmts.append(''.join(buf))
            buf, i = [], i + 1
            continue
        buf.append(c)
        i += 1
    if ''.join(buf).strip():
        stmts.append(''.join(buf))
    return stmts

t = read(SRC)
orig = t
stmts = split_statements(t)

out, n_ins, n_g, n_alt, n_guard_alt = [], 0, 0, 0, 0
for s in stmts:
    s2 = s.strip()
    if not s2:
        continue
    m = re.match(r'(?is)\bINSERT\s+INTO\s+([\w"]+)\b', s2)
    if m:
        tbl = m.group(1).strip('"').lower()
        n_ins += 1
        if 'SELECT' in s2.upper():
            out.append(s2 + ';')
            continue
        mpk = PK_OF.get(tbl, 'id')
        if not re.search(r'\bON\s+CONFLICT\b', s2, re.I):
            body = s2.rstrip()
            if body.endswith(';'):
                body = body[:-1]
            out.append(body + '\nON CONFLICT (%s) DO NOTHING;' % mpk)
            n_g += 1
            continue
        out.append(s2 + ';')
        continue
    m = re.match(r'(?is)\bALTER\s+TABLE\s+([\w"]+)\s+ADD\s+CONSTRAINT\s+([\w"]+)\s*', s2)
    if m:
        tbl, name = m.group(1).strip('"'), m.group(2).strip('"')
        body = s2.rstrip()
        if body.endswith(';'):
            body = body[:-1]
        rest = re.sub(r'(?is)^\s*\bALTER\s+TABLE\s+[\w"]+\s+ADD\s+CONSTRAINT\s+[\w"]+\s*', '', body)
        n_alt += 1
        out.append('DO $guard$\nBEGIN\n'
                   '  ALTER TABLE %s ADD CONSTRAINT %s %s;\n'
                   'EXCEPTION WHEN duplicate_object THEN NULL;\n'
                   'END $guard$;' % (tbl, name, rest))
        n_guard_alt += 1
        continue
    out.append(s2 + ';')

res = '\n'.join(out)
io.open(OUT, 'w', encoding='utf-8', newline='').write(res)

print('OK -> %s' % OUT)
print('  INSERT=%d   guarded-ON-CONFLICT=%d   skipped(SELECT)=%d'
      % (n_ins, n_g, n_ins - n_g))
print('  ALTER-ADD-CONSTRAINT=%d   wrapped-DO-guard=%d' % (n_alt, n_guard_alt))
print('  guarded-table-CREATE=%d   guarded-INDEX=%d' % (
    res.count('CREATE TABLE IF NOT EXISTS'),
    res.count('CREATE INDEX IF NOT EXISTS') + res.count('CREATE UNIQUE INDEX IF NOT EXISTS')))
