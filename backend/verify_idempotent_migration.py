# -*- coding: utf-8 -*-
"""verify_idempotent_migration.py — SCAN + RULE-COUNT final."""
import io, re

P = 'backend/supabase_migration_full_fully_idempotent.sql'
b = io.open(P, 'rb').read()
t = b.decode('utf-8-sig') if b[:3] == b'\xef\xbb\xbf' else b.decode('utf-8', 'replace')
if chr(0) in t:
    t = b.decode('latin-1')

raw_tbl = re.findall(r'(?im)^\s*CREATE\s+TABLE\s(?!IF\s+NOT\s+EXISTS)', t)
raw_idx = re.findall(r'(?im)^\s*CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?!IF\s+NOT\s+EXISTS)', t)
ins     = re.findall(r'(?im)^\s*INSERT\s+INTO\s+([\w"]+)', t)
con     = re.findall(r'(?im)\bON\s+CONFLICT\b', t)
addc    = re.findall(r'(?im)\bALTER\s+TABLE\b[^;]*\bADD\s+CONSTRAINT\b[^;]*;', t)
addc_do = re.findall(r'(?im)DO\s+\$\$[^$]*\bADD\s+CONSTRAINT\b(?:[^$]|\$(?!\$))*?\bEXCEPTION\b', t)

print('FILE          : %s' % P)
print('  lines       : %d' % t.count(chr(10)))
print('  guarded-tbl : %3d   raw : %d' % (
    len(re.findall(r'(?im)^\s*CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS', t)), len(raw_tbl)))
print('  guarded-idx : %3d   raw : %d' % (
    len(re.findall(r'(?im)^\s*CREATE\s+(?:UNIQUE\s+)?INDEX\s+IF\s+NOT\s+EXISTS', t)), len(raw_idx)))
print('  INSERT-total: %3d   ON-CONFLICT : %3d   ratio %.1f%%' % (
    len(ins), len(con), 100.0 * len(con) / len(ins) if ins else 0))
print('  ALTER-ADD-CONSTRAINT total=%3d   wrapped-in-DO=%3d' % (len(addc), len(addc_do)))
print('  what-is-addc-guard verifier: duplicate_object-hits=%d' % t.count('duplicate_object'))
print()
print('  -> if guarded-tbl==29, raw==0, ratio==100, wrapped==29 : file ready to RERUN ANY TIME', flush=True)
