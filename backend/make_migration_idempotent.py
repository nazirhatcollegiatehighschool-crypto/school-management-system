# -*- coding: utf-8 -*-
"""backend/supabase_migration_full.sql  ->  idempotent re-run  (guarded CREATEs; no 42P07)."""
import io, re, sys

SRC = 'backend/supabase_migration_full.sql'
OUT = 'backend/supabase_migration_full_idempotent.sql'

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

# 1) CREATE TABLE            -> CREATE TABLE IF NOT EXISTS
t = re.sub(r'(?m)^(\s*)CREATE\s+TABLE\s+(?!IF\s+NOT\s+EXISTS)', r'\1CREATE TABLE IF NOT EXISTS ', t)
# 2) CREATE UNIQUE INDEX / CREATE INDEX -> ... IF NOT EXISTS
t = re.sub(r'(?m)^(\s*)CREATE\s+UNIQUE\s+INDEX\s+(?!IF\s+NOT\s+EXISTS)',
           r'\1CREATE UNIQUE INDEX IF NOT EXISTS ', t)
t = re.sub(r'(?m)^(\s*)CREATE\s+INDEX\s+(?!IF\s+NOT\s+EXISTS)', r'\1CREATE INDEX IF NOT EXISTS ', t)
# 3) ALTER TABLE ... ADD CONSTRAINT  -> ADD CONSTRAINT IF NOT EXISTS
t = re.sub(r'(?i)(\bADD\s+CONSTRAINT\s+\w+)(\s+(?:FOREIGN\s+KEY|UNIQUE|PRIMARY\s+KEY|CHECK))(?:\s+IF\s+NOT\s+EXISTS)?',
           r'\1 IF NOT EXISTS\2', t)
# 4) CREATE OR REPLACE FUNCTION stays; plain CREATE FUNCTION (rare) -> OR REPLACE + guard
t = re.sub(r'(?m)^(\s*)CREATE\s+OR\s+REPLACE\s+FUNCTION', r'\1CREATE OR REPLACE FUNCTION', t)

def count(p, s): return len(re.findall(p, s, re.M))
ct = count(r'^\s*CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS', t)
ctu = count(r'^\s*CREATE\s+TABLE\s+(?!IF\s+NOT\s+EXISTS)', t)
iu = count(r'^\s*CREATE\s+UNIQUE\s+INDEX\s+IF\s+NOT\s+EXISTS', t)
iuu = count(r'^\s*CREATE\s+UNIQUE\s+INDEX\s+(?!IF\s+NOT\s+EXISTS)', t)
ii = count(r'^\s*CREATE\s+INDEX\s+IF\s+NOT\s+EXISTS', t)
iiu = count(r'^\s*CREATE\s+INDEX\s+(?!IF\s+NOT\s+EXISTS)', t)
ac = t.lower().count('add constraint if not exists')
acu = len(re.findall(r'(?i)\bADD\s+CONSTRAINT\s+\w+\s+(?!IF\s+NOT\s+EXISTS)', t))

if ctu or iuu or iiu or acu:
    sys.stderr.write('ERROR: still unguarded -> table=%d unique=%d index=%d constr=%d\n'
                     % (ctu, iuu, iiu, acu))
    sys.exit(1)

io.open(OUT, 'w', encoding='utf-8', newline='').write(t)
print('OK  %s' % OUT)
print('   tables guarded=%d  unique-index guarded=%d  index guarded=%d  constraints IFNOT=%d'
      % (ct, iu, ii, ac))
print('   changed=%s   lines=%d   bytes=%d' % (t != orig, t.count(chr(10)) + 1, len(t.encode('utf-8'))))
