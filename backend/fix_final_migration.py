# -*- coding: utf-8 -*-
"""fix_final_migration.py — ONE strict pass, file→file, string-aware.

 * strips non-comment English prose (prefixes or drops it — no SQL leak)
 * INSERT INTO t (...) VALUES ...;  →  + ON CONFLICT (<pk>) DO NOTHING;
 * ALTER TABLE t ADD CONSTRAINT c..; → DO $$guard$$ … duplicate_object guard
 * CREATE TABLE/INDEX  → IF NOT EXISTS (kept from guarded source)
Output: backend/supabase_migration_full_FINAL_CLEAN_RUN.sql
"""
import io, re

SRC = 'backend/supabase_migration_full_FINAL_recommended.sql'
OUT = 'backend/supabase_migration_full_FINAL_CLEAN_RUN.sql'

PK = {
    'time_slots': 'id', 'time_slots_groups': 'id', 'time_slots_sections': 'id',
    'classes': 'id', 'subjects': 'id', 'users': 'id', 'students': 'id',
    'teachers': 'id', 'routines': 'id', 'routine_entries': 'id',
    'sessions': 'id', 'app_settings': 'key', 'devices': 'id', 'marks': 'id',
    'ct_marks': 'id', 'attendance': 'id', 'notifications': 'id',
    'homework': 'id', 'results': 'id', 'exams': 'id', 'exam_events': 'id',
    'exam_shares': 'id', 'guardian_links': 'id', 'holidays': 'id',
    'device_tokens': 'id', 'subjects_aliases': 'id', 'exam_sections': 'id',
    'routine_blocks': 'id', 'routine_groups': 'id', 'routine_sections': 'id',
    'routine_no_classes': 'id', 'promotion_history': 'id', 'activity_log': 'id',
    'device_checks': 'id', 'guardian_shares': 'id', 'homework_files': 'id',
    'attachments': 'id',
}
SKIP_IC = {'routine_entries'}
PROSE = re.compile(r'^[A-Za-z][^\n;]{2,}$')

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

def strip_prose(s):
    """Return (clean_stmt, n_prose_lines). SQL lines kept; pure-prose lines
    become '-- ...' comments (never break a statement — statement s here is
    already a single top-level chunk ending in ';')."""
    ls = s.splitlines()
    buf = []
    n = 0
    for ln in ls:
        b0 = ln.strip()
        if not b0:
            buf.append(ln)
            continue
        if b0.startswith('--') or b0.startswith('/*'):
            buf.append(ln)
            continue
        # SQL keyword or column/here target => keep
        if re.match(r'(?i)^(CREATE|ALTER|INSERT|UPDATE|DELETE|DROP|DO|'
                    r'BEGIN|COMMIT|ROLLBACK|SELECT|SET|GRANT|REVOKE|'
                    r'TRUNCATE|COPY|COMMENT|EXECUTE|WITH|SEL|FROM|WHERE|'
                    r'VALUES|ON\s+CONFLICT|EXCEPTION|END|RETURNING|\w+_id|\w+\)|\w+,)', b0):
            buf.append(ln)
            continue
        # pure prose line => comment it
        buf.append('-- ' + ln.strip())
        n += 1
    return '\n'.join(buf), n

t = rd(SRC)
stmts = split_top(t)

res = []
n_ins = n_conf = n_alt = n_altg = n_prose = 0
for s0 in stmts:
    s, np = strip_prose(s0)
    n_prose += np
    s = s.strip()
    if not s:
        continue
    m = re.match(r'(?is)\bINSERT\s+INTO\s+([\w"]+)\b', s)
    if m:
        n_ins += 1
        tbl = m.group(1).strip('"').lower()
        if tbl in SKIP_IC or re.search(r'(?is)\bSELECT\b', s) or \
           re.search(r'\bON\s+CONFLICT\b', s, re.I):
            res.append(s + ';')
            continue
        res.append(s.rstrip().rstrip(';') +
                    '\nON CONFLICT (%s) DO NOTHING;' % PK.get(tbl, 'id'))
        n_conf += 1
        continue
    m = re.match(r'(?is)\bALTER\s+TABLE\s+([\w"]+)\s+ADD\s+CONSTRAINT\s+([\w"]+)\s*', s)
    if m:
        n_alt += 1
        tbl = m.group(1).strip('"')
        nm = m.group(2).strip('"')
        rest = re.sub(r'(?is)^\s*\bALTER\s+TABLE\s+[\w"]+\s+ADD\s+CONSTRAINT\s+[\w"]+\s*',
                      '', s).rstrip(';')
        res.append('DO $\$\nBEGIN\n'
                   '  ALTER TABLE %s ADD CONSTRAINT %s %s;\n'
                   'EXCEPTION WHEN duplicate_object THEN NULL;\n'
                   'END $$;' % (tbl, nm, rest))
        n_altg += 1
        continue
    res.append(s + ';')

final = '\n'.join(res) + '\n'
io.open(OUT, 'w', encoding='utf-8', newline='').write(final)

v = io.open(OUT, 'r', encoding='utf-8').read()
print('OK -> %s' % OUT)
print('  INSERT=%-3d  guarded=%-3d' % (n_ins, n_conf))
print('  ALTER-constraint=%-3d guarded-in-DO=%-3d' % (n_alt, n_altg))
print('  prose-lines-commented=%-3d' % n_prose)
print('  tables-guarded=%d idx-guarded=%d' % (
    len(re.findall(r'(?m)^\s*CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS', v)),
    len(re.findall(r'(?m)^\s*CREATE\s+(?:UNIQUE\s+)?INDEX\s+IF\s+NOT\s+EXISTS', v))))
bad = [l for l in re.findall(r'(?m)^[A-Za-z]\S*.*$', v)
       if not re.match(r'(?i)^(CREATE|ALTER|INSERT|UPDATE|DELETE|DROP|DO\s|'
                       r'BEGIN|COMMIT|ROLLBACK|SELECT|SET|GRANT|REVOKE|END|ON\s|'
                       r'EXCEPTION|WITH\s|COPY|COMMENT|VALUES|FROM|WHERE|TRUNCATE)', l)
       and not l.strip().startswith('--')]
print('  prose-leak-lines : %d' % len(bad))
for b in bad[:6]:
    print('      %s' % b[:90])
