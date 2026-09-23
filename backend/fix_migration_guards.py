# -*- coding: utf-8 -*-
"""fix_migration_guards.py — string-aware re-guard of the fully-idempotent file.

Fixes the one remaining class of bug (my earlier naive `;`-splitter cut an INSERT
mid-VALUES and injected `ON CONFLICT` inside a string literal → `syntax error at
or near "kept"`, `Non-ASCII` comment lines, and duplicate `ON CONFLICT`).

Strategy:
  * tokenize/split ONLY on top-level `;` (string + dollar-quote aware),
  * every INSERT..VALUES gets a single trailing `ON CONFLICT (<pk>) DO NOTHING;`
    (removes any half-injected one first),
  * every `ALTER TABLE t ADD CONSTRAINT c …` is wrapped in
    DO $$ … EXCEPTION WHEN duplicate_object THEN NULL; END $$;,
  * verify final counts are (tables=IFNOT, idx=IFNOT, insert==conflict).
"""
import io, re

SRC = 'backend/supabase_migration_full_fully_idempotent.sql'
OUT = 'backend/supabase_migration_full_fully_idempotent_FINAL.sql'

PK = {
    'time_slots': 'id', 'classes': 'id', 'subjects': 'id', 'users': 'id',
    'students': 'id', 'teachers': 'id', 'routines': 'id', 'routine_entries': 'id',
    'sessions': 'id', 'app_settings': 'key', 'time_slots_groups': 'id',
    'device_tokens': 'id', 'marks': 'id', 'ct_marks': 'id', 'attendance': 'id',
    'notifications': 'id', 'homework': 'id', 'results': 'id', 'exams': 'id',
    'exam_shares': 'id', 'exam_events': 'id', 'guardian_links': 'id',
    'holidays': 'id', 'routine_sections': 'id', 'routine_groups': 'id',
    'routine_no_classes': 'id', 'time_slot_sections': 'id',
    'device_token': 'id', 'promotion_history': 'id', 'subjects_aliases': 'id',
}
# INSERT .. SELECT .. WHERE NOT EXISTS (already safe) -> skip ON CONFLICT
SKIP_SELECT = {'routine_entries'}


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


def split_aware(sql):
    """Split on top-level ';' (string- and $$-quote aware)."""
    out, buf, i, n = [], [], 0, len(sql)
    q = dollar = None
    while i < n:
        c = sql[i]
        if q is not None:
            buf.append(c)
            if c == q and (i == 0 or sql[i - 1] != '\\'):
                q = None
            i += 1
            continue
        if dollar is not None:
            buf.append(c)
            if sql.startswith(dollar, i):
                buf.append(dollar)
                i += len(dollar)
                dollar = None
            else:
                i += 1
            continue
        if c in ("'", '"'):
            q = c
            buf.append(c)
            i += 1
            continue
        dm = re.match(r'(?s)\$[A-Za-z_][A-Za-z0-9_]*\$|\$\$', sql[i:])
        if dm:
            dollar = dm.group(0)
            buf.append(dollar)
            i += len(dollar)
            continue
        if c == ';':
            s = ''.join(buf).strip()
            if s:
                out.append(s)
            buf = []
            i += 1
            continue
        buf.append(c)
        i += 1
    s = ''.join(buf).strip()
    if s:
        out.append(s)
    return out


t = read(SRC)
stmts = split_aware(t)

out = []
n_ins = n_conf = n_alt = n_alt_guarded = 0
for s in stmts:
    m_ins = re.match(r'(?is)\bINSERT\s+INTO\s+([\w"]+)\s*\b', s)
    if m_ins:
        tbl = m_ins.group(1).strip('"').lower()
        n_ins += 1
        if tbl in SKIP_SELECT or 'SELECT' in s.upper():
            out.append(s + ';')
            continue
        # strip any half-embedded ON CONFLICT from previous bad run
        s_clean = re.sub(r'(?is)\bON\s+CONFLICT\s*\([^)]*\)\s*DO\s+NOTHING\s*;?', '', s).strip()
        pk = PK.get(tbl, 'id')
        out.append(s_clean.rstrip(';').rstrip() + '\nON CONFLICT (%s) DO NOTHING;' % pk)
        n_conf += 1
        continue
    m_alt = re.match(r'(?is)\bALTER\s+TABLE\s+([\w"]+)\s+ADD\s+CONSTRAINT\s+([\w"]+)\s+', s)
    if m_alt:
        n_alt += 1
        rest = re.sub(r'(?is)^\s*\bALTER\s+TABLE\s+[\w"]+\s+ADD\s+CONSTRAINT\s+[\w"]+\s+', '', s)
        out.append(
            'DO $guard$\nBEGIN\n'
            '  ALTER TABLE %s ADD CONSTRAINT %s %s;\n'
            'EXCEPTION WHEN duplicate_object THEN NULL;\n'
            'END $guard$;' % (m_alt.group(1).strip('"'),
                             m_alt.group(2).strip('"'), rest))
        n_alt_guarded += 1
        continue
    out.append(s + (';' if s[-1] != ';' else ''))

res = '\n'.join(out) + ('\n' if not out[-1].endswith('\n') else '')
io.open(OUT, 'w', encoding='utf-8', newline='').write(res)

n_tbl = len(re.findall(r'(?m)^\s*CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS', res))
n_tbl_raw = len(re.findall(r'(?m)^\s*CREATE\s+TABLE\s+(?!IF\s+NOT\s+EXISTS)', res))
n_idx = len(re.findall(r'(?m)^\s*CREATE\s+(?:UNIQUE\s+)?INDEX\s+IF\s+NOT\s+EXISTS', res))
n_idx_raw = len(re.findall(r'(?m)^\s*CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?!IF\s+NOT\s+EXISTS)', res))
print('OK -> %s' % OUT)
print('  guarded-table=%d raw=%d' % (n_tbl, n_tbl_raw))
print('  guarded-idx  =%d raw=%d' % (n_idx, n_idx_raw))
print('  INSERT=%d  ON-CONFLICT=%d  diff=%d%s'
      % (n_ins, n_conf, n_ins - n_conf,
         '' if n_ins == n_conf else '  <-- (skip-select tables ok)' if n_ins - n_conf == len(SKIP_SELECT) else ' <-- BAD'))
print('  ALTER-ADD-CONSTRAINT=%d  guarded=%d' % (n_alt, n_alt_guarded))
print('  bytes=%d' % len(res.encode('utf-8')))
