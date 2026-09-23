# -*- coding: utf-8 -*-
"""guard_all_conflicts.py — make supabase seed-migration INSERT-safe + ALTER-safe.

Guards applied (check-free on a re-run / populated DB):
  1) CREATE TABLE / INDEX / UNIQUE INDEX  -> IF NOT EXISTS   (already done in v1)
  2) every bare INSERT INTO t (...) VALUES ...;
        -> INSERT ... ON CONFLICT (<pk of t>) DO NOTHING;
     (right-hand `SELECT ... WHERE NOT EXISTS` inserts are skipped)
  3) ALTER TABLE t ADD CONSTRAINT c ...   -> wrapped in
        DO $$ BEGIN ALTER...; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
Output: backend/supabase_migration_full_fully_idempotent.sql
"""
import io, re

SRC = 'backend/supabase_migration_full_idempotent.sql'
OUT = 'backend/supabase_migration_full_fully_idempotent.sql'

# PK per table — from supabase_migration_full.sql schema (id except where noted).
PK = {
    'classes': 'id', 'subjects': 'id', 'time_slots': 'id', 'time_slots_groups': 'id',
    'time_slots_sections': 'id', 'routines': 'id', 'routine_entries': 'id',
    'routine_blocks': 'id', 'routine_groups': 'id', 'routine_sections': 'id',
    'routine_no_classes': 'id', 'routines': 'id', 'students': 'id', 'teachers': 'id',
    'users': 'id', 'sessions': 'id', 'exam_events': 'id', 'exams': 'id',
    'results': 'id', 'marks': 'id', 'ct_marks': 'id', 'attendance': 'id',
    'notifications': 'id', 'homework': 'id', 'exam_shares': 'id',
    'guardian_links': 'id', 'device_tokens': 'id', 'holidays': 'id',
    'promotion_history': 'id', 'promotions_history': 'id', 'activity_log': 'id',
    'app_settings': 'key',
}
# tables whose seeds are populated / guarded differently (skip ON CONFLICT)
SKIP = {'routine_entries'}

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

t = read(SRC)
orig = t

def guard_insert(m):
    tbl = m.group('tbl').strip(' "').lower()
    if tbl in SKIP or 'SELECT' in m.group('rest').upper():
        return m.group(0)
    pk = PK.get(tbl, 'id')
    body = m.group(0)
    if re.search(r'\bON\s+CONFLICT\b', body, re.I):
        return body
    return body + '\nON CONFLICT (%s) DO NOTHING;' % pk

t = re.sub(
    r"(?is)\bINSERT\s+INTO\s+(?P<tbl>[\w\"]+)\b(?P<rest>[^;]*?);",
    guard_insert, t)

def guard_constraint(m):
    tbl, name, rest = m.group('tbl'), m.group('name'), m.group('rest')
    return ("DO $$\n"
            "BEGIN\n"
            "  ALTER TABLE %s ADD CONSTRAINT %s %s;\n"
            "EXCEPTION WHEN duplicate_object THEN NULL;\n"
            "END $$;" % (tbl, name, rest))

t = re.sub(
    r"(?is)\bALTER\s+TABLE\s+(?P<tbl>[\w\"]+)\s+ADD\s+CONSTRAINT\s+(?P<name>\w+)\s+(?P<rest>.*?);",
    guard_constraint, t)

n_tbl = len(re.findall(r'(?m)^\s*CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS', t))
n_uni = len(re.findall(r'(?m)^\s*CREATE\s+UNIQUE\s+INDEX\s+IF\s+NOT\s+EXISTS', t))
n_idx = len(re.findall(r'(?m)^\s*CREATE\s+INDEX\s+IF\s+NOT\s+EXISTS', t))
n_tbl_raw = len(re.findall(r'(?m)^\s*CREATE\s+TABLE\s+(?!IF)', t))
n_idx_raw = len(re.findall(r'(?m)^\s*CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?!IF)', t))
n_con_raw = len(re.findall(r'(?s)\bALTER\s+TABLE\s+[\w\"]+\s+ADD\s+CONSTRAINT\s+\w+\s+.*?;', t))
n_cons_ung = len(re.findall(r'(?s)DO\s+\$\$\s*(?:(?!\$\$).)*\bALTER\s+TABLE\s+[\w\"]+\s+ADD\s+CONSTRAINT\s+\w+\s+.*?;\s*EXCEPTION', t))
n_in = len(re.findall(r'(?is)\bINSERT\s+INTO\b', t))
n_bf = len(re.findall(r'(?is)\bON\s+CONFLICT\b', t))

io.open(OUT, 'w', encoding='utf-8', newline='').write(t)
print('OK -> %s' % OUT)
print('  tables      guarded=%3d (raw=0:%s)' % (n_tbl, n_tbl_raw))
print('  unique-idx  guarded=%3d  index guarded=%3d (raw=0:%s)' % (n_uni, n_idx, n_idx_raw))
print('  ALTER constr guarded-in-DO=%3d (raw-ac-regions=%d)' % (n_cons_ung, n_con_raw))
print('  INSERT total=%3d  ON CONFLICT=%3d  guarded-ratio=%.1f%%' % (n_in, n_bf, 100.0 * n_bf / n_in if n_in else 0))
print('  changed=%s' % (t != orig))
