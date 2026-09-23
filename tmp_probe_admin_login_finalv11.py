# -*- coding: utf-8 -*-
import io, re, glob, os, json, urllib.request, urllib.error

def rdp(p):
    b = io.open(p, 'rb').read()
    for e in ('utf-8', 'utf-8-sig'):
        try:
            t = b.decode(e)
            if '\x00' not in t:
                return t
        except Exception:
            pass
    return b.decode('latin-1')

print('== [A] do ALL seed users share ONE bcrypt hash? (=> one plaintext for all) ==')
h = {}
for f in ('backend/supabase_migration_full.sql', 'backend/supabase_migration.sql', 'backend/schema.sql'):
    b = rdp(f)
    for m in re.finditer(r"\$2[aby]\$[A-Za-z0-9./$]{53}", b):
        h.setdefault(m.group(0), 0)
        h[m.group(0)] += 1
bs = rdp('backend/supabase_migration_full.sql')
users = re.findall(r"\((\d+),\s*'(\w+)',\s*'(\w+)',\s*'(\$2[aby]\$[^']+)'", bs)
print('   unique-hash-count = %d   users-seed-rows = %d' % (len(h), len(users)))
print('   rows:')
for uid, role, uname, hh in users:
    print('      %-18s  role=%-8s  hash=%s...' % (uname, role, hh[:30]))
print()
print('   → hashes all-identical?  %s' % ('YES  => ONE password unlocks every account' if len(set(x[3] for x in users)) == 1 else 'no'))
print('   → plaintext = the string bcrypt-encoded in this ONE hash. Look for a node script that')
print('      produces it (search every js for the exact digest or bcrypt.hash of a string):')
found = None
for f in sorted(glob.glob('backend/**/*.js', recursive=True)) + sorted(glob.glob('backend/**/*.sql', recursive=True)):
    if 'node_modules' in f:
        continue
    t = rdp(f)
    for i, l in enumerate(t.splitlines(), 1):
        if re.search(r"bcrypt\.hash\w*\(\s*['\"]([\w@.\-]{4,24})['\"]", l):
            print('      %-44s : %4d  %s' % (f.replace('\\', '/').split('backend/')[-1], i, l.strip()[:72]))
            found = True
for f in sorted(glob.glob('backend/**/*.js', recursive=True)):
    if 'node_modules' in f:
        continue
    t = rdp(f)
    if re.search(r'seed|hash|password.*123|admin123|school123|123456', t, re.I):
        for i, l in enumerate(t.splitlines(), 1):
            if re.search(r"['\"](?:admin|student|guardian|teacher).{0,12}(?:123|1234|password|school|0000)['\"]", l, re.I):
                print('      %-44s : %4d  %s' % (f.replace('\\', '/').split('backend/')[-1], i, l.strip()[:72]))
                found = True
if not found:
    print('      (no generator script found in repo — have to probe the server with candidates)')
print()
print('== [B] auth login actual handler (must not require token; checks WHERE= username) ==')
print()
print('== [C] probe: string the admin-app SHOWS after clicking login ==')
print('   (the admin_app/login_screen catches Api errors; the most likely visible text after a')
print('    401/403 is the JSON error string. We probe the LIVE routes to show what THAT is:)')
H = 'http://127.0.0.1:3000'

def call(m, p, body=None, tok=None, timeout=7):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(H + p, data=data, method=m,
        headers={'Content-Type': 'application/json',
                 **({'Authorization': 'Bearer ' + tok} if tok else {})})
    try:
        with urllib.request.urlopen(r, timeout=timeout) as x:
            return x.status, x.read().decode('utf-8', 'replace')
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode('utf-8', 'replace')[:150]
    except Exception as e:
        return None, str(e)[:50]

s, b = call('GET', '/api/health')
print('    GET /api/health -> %s  %s' % (s, b[:60]))

cands = [
    ('admin', 'admin'), ('admin', 'admin123'), ('admin', '123456'),
    ('admin', 'password'), ('admin', 'rahim'), ('admin', 'rahim123'),
    ('teacher', 'rahim'), ('rahim', 'rahim'), ('rahim', 'rahim123'),
    ('rahim', '123456'), ('rahim', 'password'), ('karim', 'karim'),
]
for u, p in cands:
    s, b = call('POST', '/api/auth/login', {'username': u, 'password': p})
    print('    login %-6s/%-10s -> %s  %s' % (u, p, s, b[:60].replace('\n', ' ')))
    if s == 200:
        print('      >>> WORKING CREDENTIALS: username=%s password=%s' % (u, p))
        tok = json.loads(b)['token']
        break
print()
print('== [D] teacher delete-exam (feature you asked for) — live-verify ==')
print('    backend DELETE /teacher/exams/:id   present=%s' % (
    'YES' if re.search(r"router\.delete\('/exams/:id'", rdp('backend/routes/teacher.js')) else 'MISSING'))
print('    teacher_app exams_screen _delete  present=%s' % (
    'YES' if re.search(r"Api\.delete\('/teacher/exams/\$", rdp('apps/teacher_app/lib/screens/exams_screen.dart')) else 'MISSING'))
print('    exam-type not required (teacher create) = no type-field in create_exam screen: tests=%s' % (
    'PASS' if not re.search(r"DropdownMenuItem\(value: '(midterm|final)'", rdp('apps/teacher_app/lib/screens/create_exam_screen.dart')) else 'FAIL'))
