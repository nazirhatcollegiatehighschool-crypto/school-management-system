# -*- coding: utf-8 -*-
"""finalize_migration.py — clean, string-aware, TOP-LEVEL-';'-only guarded rewrite.

Reads  backend/supabase_migration_full_idempotent.sql            (source-of-truth)
Writes backend/supabase_migration_full_FINAL_recommended.sql      (apply this one)

Guards added (safe to re-run on already-populated DB):
  * INSERT INTO t (...) VALUES ...;
        -> append  ON CONFLICT (<pk of t>) DO NOTHING;   (skip known INSERT..SELECT)
  * ALTER TABLE t ADD CONSTRAINT c ...;
        -> wrap in DO $$ .. EXCEPTION WHEN duplicate_object THEN NULL; END $$;
  * CREATE TABLE / Index  -> IF NOT EXISTS (kept; already guarded in source)
String/$$/quote-aware split => no mid-VALUES corruption, no "kept" leakage.
"""
import io, re

SRC = 'backend/supabase_migration_full_idempotent.sql'
OUT = 'backend/supabase_migration_full_FINAL_recommended.sql'

PK = {
    'time_slots': 'id', 'time_slot_groups': 'id', 'time_slot_sections': 'id',
    'classes': 'id', 'subjects': 'id', 'users': 'id', 'students': 'id',
    'teachers': 'id', 'routines': 'id', 'routine_entries': 'id',
    'sessions': 'id', 'app_settings': 'key', 'time_slots_groups': 'id',
    'routines_old': 'id', 'devices': 'id', 'marks': 'id', 'ct_marks': 'id',
    'attendance': 'id', 'notifications': 'id', 'homework': 'id',
    'results': 'id', 'exams': 'id', 'exam_events': 'id', 'exam_shares': 'id',
    'guardian_links': 'id', 'holidays': 'id', 'device_tokens': 'id',
    'subjects_aliases': 'id', 'exam_sections': 'id', 'classes_aliases': 'id',
    'routine_blocks': 'id', 'routine_groups': 'id', 'routine_sections': 'id',
    'routine_no_classes': 'id', 'promotion_history': 'id', 'activity_log': 'id',
    'device_checks': 'id', 'notifications_log': 'id', 'students_aliases': 'id',
    'exam_shares': 'id',
}
SKIP_IC = {'routine_entries'}   # INSERT..SELECT..WHERE NOT EXISTS → already safe

def readb(p):
    b = io.open(p, 'rb').read()
    for enc in ('utf-8', 'utf-8-sig', 'latin-1'):
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
        if c in ('\'', '"'):
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
            st = ''.join(buf).strip()
            if st:
                out.append(st)
            buf = []
            i += 1
            continue
        buf.append(c)
        i += 1
    tail = ''.join(buf).strip()
    if tail:
        out.append(tail)
    return out

def writeb(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)

raw = readb(SRC)
stmts = split_top(raw)

res = []
n_ins = n_conf = n_alt = n_alt_g = 0
for s0 in stmts:
    s = s0.strip()
    m = re.match(r'(?is)\bINSERT\s+INTO\s+([\w"]+)\b', s)
    if m:
        n_ins += 1
        tbl = m.group(1).strip('"').lower()
        if tbl in SKIP_IC or re.search(r'(?is)\bSELECT\b', s):
            res.append(s + ';')
            continue
        pk = PK.get(tbl, 'id')
        if re.search(r'\bON\s+CONFLICT\b', s, re.I):
            res.append(s + ';')
            continue
        res.append(s.rstrip().rstrip(';') + '\nON CONFLICT (%s) DO NOTHING;' % pk)
        n_conf += 1
        continue
    m = re.match(r'(?is)\bALTER\s+TABLE\s+([\w"]+)\s+ADD\s+CONSTRAINT\s+([\w"]+)\s*', s)
    if m:
        n_alt += 1
        tbl = m.group(1).strip('"')
        nm = m.group(2).strip('"')
        rest = re.sub(r'(?is)^\s*\bALTER\s+TABLE\s+[\w"]+\s+ADD\s+CONSTRAINT\s+[\w"]+\s*', '', s).rstrip(';')
        res.append(
            'DO $guard$\nBEGIN\n'
            '  ALTER TABLE %s ADD CONSTRAINT %s %s;\n'
            'EXCEPTION WHEN duplicate_object THEN NULL;\n'
            'END $guard$;' % (tbl, nm, rest))
        n_alt_g += 1
        continue
    res.append(s + ';')

final = '\n'.join(res) + '\n'
writeb(OUT, final)

# verify (string-aware, no globals)
v = readb(OUT)
n_tbl_g = len(re.findall(r'(?m)^\s*CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS', v))
n_tbl_r = len(re.findall(r'(?m)^\s*CREATE\s+TABLE\s+(?!IF\s+NOT\s+EXISTS)', v))
n_idx_g = len(re.findall(r'(?m)^\s*CREATE\s+(?:UNIQUE\s+)?INDEX\s+IF\s+NOT\s+EXISTS', v))
n_idx_r = len(re.findall(r'(?m)^\s*CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?!IF\s+NOT\s+EXISTS)', v))
n_ins = len(re.findall(r'(?i)\bINSERT\s+INTO\b', v))
n_oc = len(re.findall(r'(?i)\bON\s+CONFLICT\b', v))
n_altv = len(re.findall(r'(?is)\bALTER\s+TABLE\s+[\w"]+\s+ADD\s+CONSTRAINT\s+[\w"]+', v))
n_altg = len(re.findall(r'(?is)DO\s+\$guard\$.*?\bADD\s+CONSTRAINT\b', v))
n_leak = len(re.findall(r'(?is)\bkept\b', v))

print('OK -> %s' % OUT)
print('  tables guarded=%-3d raw=%d     indexes guarded=%-3d raw=%d'
      % (n_tbl_g, n_tbl_r, n_idx_g, n_idx_r))
print('  INSERT=%-3d  ON-CONFLICT=%-3d  ratio=%.0f%%' % (n_ins, n_oc, 100.0 * n_oc / n_ins if n_ins else 0))
print('  ALTER-ADD-CONSTRAINT=%d  guarded=$guard$=%d' % (n_altv, n_altg))
print('  English-leak ("kept") occurrences: %d' % n_leak)
print('  bytes=%d' % len(final.encode('utf-8')))
