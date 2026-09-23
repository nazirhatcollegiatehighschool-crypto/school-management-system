# -*- coding: utf-8 -*-
"""fix_migration_once.py — TRUE string-aware guarded rewrite (no regex-on-;).

Produces backend/supabase_migration_full_fully_idempotent.sql
  * INSERT INTO t (...) VALUES ...;  ->  + ON CONFLICT (<pk>) DO NOTHING;
  * ALTER TABLE t ADD CONSTRAINT c ...; -> DO $$..duplicate_object..$$;
  * CREATE TABLE/INDEX already IF NOT EXISTS (kept as-is)
Statements are split on top-level ';' only (string/dollar-quote aware).
"""
import io, re

SRC = 'backend/supabase_migration_full_idempotent.sql'
OUT = 'backend/supabase_migration_full_fully_idempotent.sql'

PK = {
    'time_slots': 'id', 'classes': 'id', 'subjects': 'id', 'users': 'id',
    'students': 'id', 'teachers': 'id', 'routines': 'id', 'routine_entries': 'id',
    'sessions': 'id', 'app_settings': 'key', 'time_slots_groups': 'id',
    'devices': 'id', 'marks': 'id', 'ct_marks': 'id', 'attendance': 'id',
    'notifications': 'id', 'homework': 'id', 'results': 'id', 'exams': 'id',
    'exam_shares': 'id', 'exam_events': 'id', 'guardian_links': 'id',
    'holidays': 'id', 'device_tokens': 'id', 'subjects_aliases': 'id',
    'routine_no_classes': 'id', 'routine_blocks': 'id', 'time_slots_sections': 'id',
}
SKIP_IC = {'routine_entries'}  # INSERT..SELECT..WHERE NOT EXISTS already guarded

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

def split_sql(sql):
    """Split on ; at nesting depth 0, ignoring ; inside strings / dollar-quoted bodies."""
    stmts, buf, i, n = [], [], 0, len(sql)
    q = dollar = None
    while i < n:
        c = sql[i]
        if dollar:
            buf.append(c)
            if sql.startswith(dollar, i):
                buf.append(dollar)
                i += len(dollar)
                dollar = None
                continue
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
        if c == '$' and (d := re.match(r'(?s)\$[A-Za-z_][A-Za-z0-9_]*\$|\$\$', sql[i:])):
            dollar = d.group(0)
            buf.append(dollar)
            i += len(dollar)
            continue
        if c == ';':
            stmts.append(''.join(buf))
            buf = []
            i += 1
            continue
        buf.append(c)
        i += 1
    if ''.join(buf).strip():
        stmts.append(''.join(buf))
    return stmts

t = read(SRC)
orig = t
stmts = split_sql(t)

out = []
n_in = n_g = n_ac = n_ag = 0
for s in stmts:
    s = s.strip(' \n\r\t')
    if not s:
        continue
    m = re.match(r'(?is)\bINSERT\s+INTO\s+([\w"]+)\s*\b', s)
    if m:
        tbl = m.group(1).strip('"').lower()
        n_in += 1
        if tbl in SKIP_IC or 'SELECT' in s.upper():
            out.append(s + ';')
            continue
        if not re.search(r'\bON\s+CONFLICT\b', s, re.I):
            pk = PK.get(tbl, 'id')
            out.append(s.rstrip().rstrip(';') + '\nON CONFLICT (%s) DO NOTHING;' % pk)
            n_g += 1
            continue
        out.append(s + ';')
        continue
    m = re.match(r'(?is)\bALTER\s+TABLE\s+([\w"]+)\s+ADD\s+CONSTRAINT\s+([\w"]+)\s+', s)
    if m:
        tbl, name = m.group(1).strip('"'), m.group(2).strip('"')
        n_ac += 1
        stmt = s.rstrip(';')
        body = re.sub(r'(?is)^\s*\bALTER\s+TABLE\s+[\w"]+\s+ADD\s+CONSTRAINT\s+[\w"]+\s+', '', stmt)
        out.append(
            'DO $block$\nBEGIN\n'
            '  ALTER TABLE %s ADD CONSTRAINT %s %s;\n'
            'EXCEPTION WHEN duplicate_object THEN NULL;\n'
            'END $block$;' % (tbl, name, body))
        n_ag += 1
        continue
    out.append(s + ';')

res = '\n'.join(out)
io.open(OUT, 'w', encoding='utf-8', newline='').write(res)

print('OK -> %s' % OUT)
print('  INSERT total=%d  +ON CONFLICT=%d  skipped(sel/known)=%d'
      % (n_in, n_g, n_in - n_g))
print('  ALTER-ADD-CONSTRAINT total=%d  wrapped-in-\\$\\$=%d' % (n_ac, n_ag))
print('  tables-ifnot=%d  uniq-idx-ifnot=%d  idx-ifnot=%d' % (
    len(re.findall(r'(?m)^CREATE TABLE IF NOT EXISTS', res)),
    len(re.findall(r'(?m)^CREATE UNIQUE INDEX IF NOT EXISTS', res)),
    len(re.findall(r'(?m)^CREATE INDEX IF NOT EXISTS', res))))
print('  changed=%s' % (res != orig))
