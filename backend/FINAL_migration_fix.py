# -*- coding: utf-8 -*-
"""FINAL_migration_fix.py — one-shot clean rebuild of the recommended SQL.

Reads  backend/supabase_migration_full_FINAL_recommended.sql   (current, "-leak" fixed)
Writes backend/supabase_migration_full_RUN_ME_FINAL.sql        (string-clean + guarded)

Guarantees (all string/$$/quote-aware; no mid-VALUES corruption):
  * prose-lines outside SQL are dropped (they're all "kept…/commentary" noise)
  * every bare INSERT INTO t (…) VALUES …;   -> … ON CONFLICT (pk(t)) DO NOTHING;
  * every ALTER TABLE t ADD CONSTRAINT c…;   -> DO-block duplicate_object guard
  * CREATE TABLE/INDEX already IF NOT EXISTS, kept as-is (never re-touched)
"""
import io, re

SRC = 'backend/supabase_migration_full_FINAL_recommended.sql'
OUT = 'backend/supabase_migration_full_RUN_ME_FINAL.sql'

PK = {
    'time_slots': 'id', 'classes': 'id', 'subjects': 'id', 'users': 'id',
    'students': 'id', 'teachers': 'id', 'routines': 'id', 'routine_entries': 'id',
    'sessions': 'id', 'app_settings': 'key', 'time_slots_groups': 'id',
    'devices': 'id', 'marks': 'id', 'ct_marks': 'id', 'attendance': 'id',
    'notifications': 'id', 'homework': 'id', 'results': 'id', 'exam_events': 'id',
    'exams': 'id', 'exam_shares': 'id', 'guardian_links': 'id', 'holidays': 'id',
    'device_tokens': 'id', 'exam_shares': 'id', 'promotion_history': 'id',
    'activity_log': 'id', 'time_slot_sections': 'id', 'time_slots_sections': 'id',
    'exam_sections': 'id', 'homework': 'id', 'notifications': 'id',
    'routine_groups': 'id', 'routine_sections': 'id', 'routine_blocks': 'id',
    'routine_no_classes': 'id', 'classes_aliases': 'id',
}
SKIP_IC = {'routine_entries'}  # INSERT..SELECT..WHERE NOT EXISTS

def rd(p):
    b = io.open(p, 'rb').read()
    for enc in ('utf-8', 'utf-8-sig'):
        try:
            t = b.decode(enc)
            if chr(0) not in t:
                return t
        except Exception:
            pass
    return b.decode('latin-1')

def split_top(sql):
    out, buf = [], []
    i, n = 0, len(sql)
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
        if c == '$':
            m = re.match(r'(?s)\$[A-Za-z_][A-Za-z0-9_]*\$|\$\$', sql[i:])
            if m:
                dollar = m.group(0)
                buf.append(dollar)
                i += len(dollar)
                continue
        if c == ';':
            s2 = ''.join(buf).strip()
            if s2:
                out.append(s2)
            buf = []
            i += 1
            continue
        buf.append(c)
        i += 1
    tail = ''.join(buf).strip()
    if tail:
        out.append(tail)
    return out

def is_prose(s):
    """Statement is pure English-prose if it contains no SQL verbs/DDL tokens."""
    if re.search(r'(?i)\b(CREATE|ALTER|INSERT|UPDATE|DELETE|DROP|DO\b|BEGIN\b|'
                 r'COMMIT|ROLLBACK|SELECT|WITH|GRANT|REVOKE|SET\b|TRUNCATE|'
                 r'TABLE|INDEX|CONSTRAINT|FOREIGN|PRIMARY|UNIQUE|CHECK|'
                 r'REFERENCES|ON CONFLICT|DO NOTHING|EXCEPTION|END\b|IDENTITY|'
                 r'GENERATED|DEFAULT|NOT NULL|INTEGER|VARCHAR|TEXT|BOOLEAN|'
                 r'TIMESTAMP|SMALLINT|TIME\b|DATE\b|NUMERIC|VALUES|key\b|id\b'
                 r'|JSON|UUID|COPY)\b', s):
        return False
    return True

t = rd(SRC)
stmts = split_top(t)

out = []
n_drop = n_ins = n_conf = n_alt = n_altg = n_skip = 0
for s0 in stmts:
    s = s0.strip()
    if is_prose(s):
        n_drop += 1  # pure prose statement ("kept in file…") → drop entirely
        continue
    m = re.match(r'(?is)\bINSERT\s+INTO\s+([\w"]+)\b', s)
    if m:
        tbl = m.group(1).strip('"').lower()
        n_ins += 1
        if tbl in SKIP_IC or re.search(r'(?is)\bSELECT\b', s) or \
           re.search(r'\bON\s+CONFLICT\b', s, re.I):
            out.append(s + ';')
            continue
        pk = PK.get(tbl, 'id')
        out.append(s.rstrip().rstrip(';') + '\nON CONFLICT (%s) DO NOTHING;' % pk)
        n_conf += 1
        continue
    m = re.match(r'(?is)\bALTER\s+TABLE\s+([\w"]+)\s+ADD\s+CONSTRAINT\s+([\w"]+)\s+', s)
    if m:
        tbl = m.group(1).strip('"')
        nm = m.group(2).strip('"')
        rest = re.sub(r'(?is)^\s*\bALTER\s+TABLE\s+[\w"]+\s+ADD\s+CONSTRAINT\s+[\w"]+\s*',
                      '', s).rstrip(';')
        n_alt += 1
        out.append('DO $guard$\nBEGIN\n'
                   '  ALTER TABLE %s ADD CONSTRAINT %s %s;\n'
                   'EXCEPTION WHEN duplicate_object THEN NULL;\n'
                   'END $guard$;' % (tbl, nm, rest))
        n_altg += 1
        continue
    out.append(s + ';')

res = '\n'.join(out) + '\n'
io.open(OUT, 'w', encoding='utf-8', newline='').write(res)

# ---- VERIFY ----
v = rd(OUT)
n_tbl = len(re.findall(r'(?m)^\s*CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS', v))
n_tbl_raw = len(re.findall(r'(?m)^\s*CREATE\s+TABLE\s+(?!IF\s+NOT\s+EXISTS)', v))
n_idx = len(re.findall(r'(?m)^\s*CREATE\s+(?:UNIQUE\s+)?INDEX\s+IF\s+NOT\s+EXISTS', v))
n_idx_raw = len(re.findall(r'(?m)^\s*CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?!IF\s+NOT\s+EXISTS)', v))
n_ins = len(re.findall(r'(?is)\bINSERT\s+INTO\b', v))
n_oc = len(re.findall(r'(?is)\bON\s+CONFLICT\b', v))
n_alt_v = len(re.findall(r'(?is)\bALTER\s+TABLE\s+[\w"]+\s+ADD\s+CONSTRAINT\s+[\w"]+', v))
n_altg_v = len(re.findall(r'(?is)DO\s+\$guard\$.*?\bEXCEPTION\s+WHEN\s+duplicate_object', v))
prose = 0
for i, l in enumerate(v.splitlines(), 1):
    b = l.strip()
    if not b or b.startswith('--') or b.startswith('/*'):
        continue
    if is_prose_l(l):
        prose += 1

print('OK -> %s' % OUT)
print('  tables   guarded=%d raw=%d' % (n_tbl, n_tbl_raw))
print('  indexes  guarded=%d raw=%d' % (n_idx, n_idx_raw))
print('  INSERT=%d  ON-CONFLICT=%d  (skip=%d)' % (n_ins, n_oc, n_skip))
print('  ALTER-ADD-CONSTRAINT=%d  DO-guarded=%d' % (n_alt_v, n_altg_v))
print('  prose-statements   dropped=%d  remaining=%d' % (n_drop, prose))
print('  prose-leak => %s' % ('ZERO ✅' if prose == 0 else 'STILL %d ⛔' % prose))
bad_ratio = (n_oc and n_ins) and (n_oc == n_ins or (n_oc == n_ins - 1 and n_skip == 1))
print('  insert-guard-ratio => %s'
      % ('100% ✅' if bad_ratio else 'CHECK ⚠️ (%d vs %d)' % (n_ins, n_oc)))
