# -*- coding: utf-8 -*-
"""emit_final_recommended.py — THE final one. String-aware, top-';'-only split;
adds ON CONFLICT (pk) DO NOTHING to bare VALUE-INSERTs, wraps ADD CONSTRAINT in
DO-duplicate_object, and always-//-comments any non-SQL prose so no 'kept' leak.

OUT: backend/supabase_migration_FINAL_RUN_ME.sql
"""
import io, re

SRC = 'backend/supabase_migration_full_idempotent.sql'
OUT = 'backend/supabase_migration_FINAL_RUN_ME.sql'

# per-table PRIMARY KEY (source schema: every table `id` except app_settings)
PK = {
    'time_slots': 'id', 'time_slot_groups': 'id', 'time_slot_sections': 'id',
    'classes': 'id', 'subjects': 'id', 'users': 'id', 'students': 'id',
    'teachers': 'id', 'routines': 'id', 'routine_entries': 'id',
    'sessions': 'id', 'app_settings': 'key', 'device_tokens': 'id',
    'marks': 'id', 'ct_marks': 'id', 'attendance': 'id', 'notifications': 'id',
    'homework': 'id', 'results': 'id', 'exams': 'id', 'exam_events': 'id',
    'exam_shares': 'id', 'guardian_links': 'id', 'holidays': 'id',
    'subjects_aliases': 'id', 'classes_aliases': 'id', 'routine_blocks': 'id',
    'routine_groups': 'id', 'routine_sections': 'id', 'routine_no_classes': 'id',
    'promotion_history': 'id', 'activity_log': 'id', 'device_checks': 'id',
    'students_aliases': 'id', 'exam_sections': 'id', 'time_slots_groups': 'id',
}
SKIP_IC = {'routine_entries'}  # INSERT..SELECT..WHERE NOT EXISTS

def readb(p):
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
    """Split on top-level ';' — string+$$-aware, so VALUES never break up."""
    stmts, buf = [], []
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
            s = ''.join(buf).strip()
            if s:
                stmts.append(s)
            buf = []
            i += 1
            continue
        buf.append(c)
        i += 1
    tail = ''.join(buf).strip()
    if tail:
        stmts.append(tail)
    return stmts

def comment_prose(stmt):
    """Turn bare prose (no leading --) into a -- comment line."""
    lines = stmt.splitlines()
    out = []
    changed = False
    for ln in lines:
        if not ln.strip():
            out.append(ln)
            continue
        body = ln.strip()
        if body.startswith('--') or body.startswith('/*'):
            out.append(ln)
            continue
        # SQL keywords that legitimately start a real statement
        if re.match(
            r'(?is)^(CREATE|ALTER|INSERT|UPDATE|DELETE|DROP|DO|GRANT|REVOKE|'
            r'TRUNCATE|SET|SELECT|BEGIN|COMMIT|ROLLBACK|SAVEPOINT|EXPLAIN|'
            r'COPY|COMMENT|VACUUM|ANALYZE|CALL|PREPARE|EXECUTE)\b',
            body):
            out.append(ln)
            continue
        out.append('-- ' + ln.lstrip())
        changed = True
    return '\n'.join(out), changed

t = readb(SRC)
stmts = split_top(t)

res = []
n_ins = n_conf = n_alt = n_altg = n_prose = 0
for s in stmts:
    s2, chg = comment_prose(s)
    if chg and not s2.strip().startswith(('CREATE', 'ALTER', 'INSERT', 'DO')):
        n_prose += 1
    m = re.match(r'(?is)\bINSERT\s+INTO\s+([\w"]+)\b', s2)
    if m:
        n_ins += 1
        tbl = m.group(1).strip('"').lower()
        if tbl in SKIP_IC or re.search(r'(?is)\bSELECT\b', s2):
            res.append(s2 + ';')
            continue
        if re.search(r'\bON\s+CONFLICT\b', s2, re.I):
            res.append(s2 + ';')
            continue
        res.append(s2.rstrip().rstrip(';') +
                   '\nON CONFLICT (%s) DO NOTHING;' % PK.get(tbl, 'id'))
        n_conf += 1
        continue
    m = re.match(r'(?is)\bALTER\s+TABLE\s+([\w"]+)\s+ADD\s+CONSTRAINT\s+([\w"]+)\s*',
                 s2)
    if m:
        n_alt += 1
        tbl = m.group(1).strip('"')
        nm = m.group(2).strip('"')
        rest = re.sub(
            r'(?is)^\s*\bALTER\s+TABLE\s+[\w"]+\s+ADD\s+CONSTRAINT\s+[\w"]+\s*',
            '', s2).rstrip(';')
        res.append(
            'DO $guard$\nBEGIN\n'
            '  ALTER TABLE %s ADD CONSTRAINT %s %s;\n'
            'EXCEPTION WHEN duplicate_object THEN NULL;\n'
            'END $guard$;' % (tbl, nm, rest))
        n_altg += 1
        continue
    res.append(s2 + ';')

final = '\n'.join(res) + '\n'
io.open(OUT, 'w', encoding='utf-8', newline='').write(final)

v = readb(OUT)
print('OK -> %s' % OUT)
print('  tables-guarded=%d raw=%d' % (
    len(re.findall(r'(?m)^\s*CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS', v)),
    len(re.findall(r'(?m)^\s*CREATE\s+TABLE\s+(?!IF\s+NOT\s+EXISTS)', v))))
print('  idx-guarded  =%d raw=%d' % (
    len(re.findall(r'(?m)^\s*CREATE\s+(?:UNIQUE\s+)?INDEX\s+IF\s+NOT\s+EXISTS', v)),
    len(re.findall(r'(?m)^\s*CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?!IF\s+NOT\s+EXISTS)', v))))
print('  INSERT=%d  ON-CONFLICT=%d' % (
    len(re.findall(r'(?i)\bINSERT\s+INTO\b', v)),
    len(re.findall(r'(?i)\bON\s+CONFLICT\b', v))))
print('  ALTER-ADD-CONSTRAINT=%d  guarded-in-DO=%d  prose-commented=%d' % (
    len(re.findall(r'(?i)\bALTER\s+TABLE\s+[\w"]+\s+ADD\s+CONSTRAINT\s+[\w"]+', v)),
    len(re.findall(r'(?is)DO\s+\$guard\$.*?\bADD\s+CONSTRAINT\b', v)),
    n_prose))
print('  stray-"kept"-not-preceded-by---: %d' % len(
    re.findall(r'(?m)^(?!--)\s*kept\b', v, re.I)))
