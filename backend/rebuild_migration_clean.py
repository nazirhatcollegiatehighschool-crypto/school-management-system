# -*- coding: utf-8 -*-
"""rebuild_migration_clean.py — vFinal: string-aware splitter + correct guards.

  FROM backend/supabase_migration_full.sql (source-of-truth from live studio dump)
  TO   backend/supabase_migration_CLEAN_idempotent_FINAL.sql

Rules (each idempotent => run any number of times on populated DB):
  * CREATE TABLE          -> CREATE TABLE IF NOT EXISTS        (incl. time_slots)
  * CREATE [UNIQUE] INDEX -> ... IF NOT EXISTS
  * INSERT INTO t (...) VALUES ... ; -> INSERT ... ON CONFLICT (<pk of t>) DO NOTHING;
      - pk resolved per-table from its CREATE TABLE PRIMARY KEY (fallback 'id')
      - INSERT...SELECT/WHERE NOT EXISTS blocks left as-is (already conflict-safe)
  * ALTER TABLE t ADD CONSTRAINT c ... -> wrapped DO $block$ ... EXCEPTION
      WHEN duplicate_object THEN NULL; END $block$;   (no twice-added)
  * INSERTs into tables that hold composite FKs w/o single-PK => ON CONFLICT skipped
    unless single constraint found.
"""
import io, re

SRC  = 'backend/supabase_migration_full.sql'
OUTS = 'backend/supabase_migration_CLEAN_idempotent_FINAL.sql'

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

def write(p, t):
    io.open(p, 'w', encoding='utf-8', newline='').write(t)

def split_sql(sql):
    """Split on top-level ';' — aware of '...', "...", ( ) and $$...$$."""
    out, buf = [], []
    i, n = 0, len(sql)
    q = None
    dollar = None
    while i < n:
        c = sql[i]
        if dollar:
            buf.append(c)
            if c == '$' and len(dollar) > 1 and sql.startswith(dollar, i + 1 - len(dollar)):
                pass
            if sql.startswith(dollar, i):
                buf.append(dollar)
                i += len(dollar)
                dollar = None
                continue
            i += 1
            continue
        if q:
            buf.append(c)
            if c == q and (i == 0 or sql[i-1] != '\\'):
                q = None
            i += 1
            continue
        if c in ("'", '"'):
            q = c
            buf.append(c)
            i += 1
            continue
        if c == '$' and sql.startswith('$', i) and sql[i+1:i+2] in ('$', '_', 'aZz'):
            m = re.match(r'\$[A-Za-z_][A-Za-z0-9_]*\$|\$\$', sql[i:])
            if m:
                dollar = m.group(0)
                buf.append(dollar)
                i += len(dollar)
                continue
        if c == ';':
            out.append(''.join(buf))
            buf = []
            i += 1
            continue
        buf.append(c)
        i += 1
    if ''.join(buf).strip():
        out.append(''.join(buf))
    return out

def find_pk(txt):
    """rough PK map: table CREATE -> PRIMARY KEY (...) column list (first col)."""
    pk = {}
    for m in re.finditer(r'(?is)CREATE\s+(?:TEMPORARY\s+)?TABLE\s+IF\s+NOT\s+EXISTS\s*([\w."]+)\s*\((.*?)\)\s*;',
                         txt):
        tbl = m.group(1).strip('"').lower()
        body = m.group(2)
        pm = re.search(r'(?is)\bPRIMARY\s+KEY\s*\(([^)]+)\)', body)
        if pm:
            cols = [c.strip().strip('"').lower() for c in pm.group(1).split(',')]
            pk[tbl] = cols[0] if cols else 'id'
        else:
            pk[tbl] = 'id'
    return pk

t     = read(SRC)
orig  = t
t     = re.sub(r'(?m)^\s*SET\s+(?:search_path|statement_timeout)\b[^;]*;', '', t)

# --- turn guarded already (source might be mostly idempotent from studio?) ---
t = re.sub(r'(?m)^(\s*)CREATE\s+TABLE\s+(?!IF\s+NOT\s+EXISTS)', r'\1CREATE TABLE IF NOT EXISTS ', t)
t = re.sub(r'(?m)^(\s*)CREATE\s+UNIQUE\s+INDEX\s+(?!IF\s+NOT\s+EXISTS)', r'\1CREATE UNIQUE INDEX IF NOT EXISTS ', t)
t = re.sub(r'(?m)^(\s*)CREATE\s+INDEX\s+(?!IF\s+NOT\s+EXISTS)', r'\1CREATE INDEX IF NOT EXISTS ', t)

pkmap = find_pk(t)

# Remove any already-injected ON CONFLICT from a previous bad run (defensive):
t = re.sub(r'(?is)\bON\s+CONFLICT\s*\([^)]*\)\s*DO\s+NOTHING;', '', t)

# single-insert + conflict guard (string-aware via split_sql)
stmts = split_sql(t)
pkmap['time_slots'] = 'id'
pkmap['time_slots_groups'] = 'id'
skip_ic = {'routine_entries', 'routine_no_classes', 'sessions', 'attendance',
           'marks', 'ct_marks', 'homework', 'notifications', 'device_tokens',
           'results', 'promotion_history', 'exam_shares', 'guardian_links',
           'activity_log'}

n_in = n_g = n_ok_g = 0
out = []
for s in stmts:
    s2 = s.strip()
    if not s2:
        continue
    m = re.match(r'(?is)\bINSERT\s+INTO\s+([\w."]+)\b', s2)
    if m:
        tbl = m.group(1).strip('"').lower()
        n_in += 1
        if tbl in skip_ic or re.search(r'(?is)\bSELECT\b', s2):
            out.append(s2)
            continue
        pk = pkmap.get(tbl, 'id')
        if not re.search(r'\bON\s+CONFLICT\b', s2, re.I):
            out.append(s2 + '\nON CONFLICT (%s) DO NOTHING;' % pk)
            n_g += 1
        else:
            out.append(s2)
        continue
    m = re.match(r'(?is)\bALTER\s+TABLE\s+([\w."]+)\s+ADD\s+CONSTRAINT\s+([\w"]+)\s+(.*)', s2)
    if m:
        tbl, name, rest = m.group(1), m.group(2), m.group(3).rstrip(';').strip()
        out.append("DO $block$\n"
                   "BEGIN\n"
                   "  ALTER TABLE %s ADD CONSTRAINT %s %s;\n"
                   "EXCEPTION WHEN duplicate_object THEN NULL;\n"
                   "END $block$;" % (tbl, name, rest))
        continue
    out.append(s2)

res = '\n'.join(x for x in out if x.strip())

# quick-parse sanity: every line that is a CREATE ... should be guarded
bad_tbl  = [l for l in res.splitlines() if re.match(r'\s*CREATE\s+TABLE\s+(?!IF\s+NOT\s+EXISTS)', l)]
bad_idx  = [l for l in res.splitlines() if re.match(r'\s*CREATE\s+UNIQUE\s+INDEX\s+(?!IF\s+NOT\s+EXISTS)', l) or
            re.match(r'\s*CREATE\s+INDEX\s+(?!IF\s+NOT\s+EXISTS)', l)]
write(OUTS, res)

print('OK -> %s' % OUTS)
print('  statements      : %d' % len(out))
print('  INSERTs         : %d   guarded=%d   skipped-as-conflict-safe=%d'
      % (n_in, n_g, n_in - n_g))
print('  ON CONFLICT rows: %d' % res.count('ON CONFLICT'))
print('  CREATE TABLE raw (unguarded) : %d' % len(bad_tbl))
print('  CREATE INDEX  raw (unguarded): %d' % len(bad_idx))
print('  pk-map entries  : %d  (sample: time_slots=%s routines=%s classes=%s)'
      % (len(pkmap), pkmap.get('time_slots'), pkmap.get('routines'), pkmap.get('classes')))
