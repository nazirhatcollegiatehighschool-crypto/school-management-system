# -*- coding: utf-8 -*-
import io, re, glob, os

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

print('== [1] secret/plaintext creator of seed hash ==')
for f in sorted(glob.glob('backend/**/*', recursive=True)):
    if not os.path.isfile(f) or any(x in f.replace('\\', '/') for x in ('node_modules', 'build', 'outputs')):
        continue
    t = rdp(f)
    if 'supabase_migration' in f.replace('\\', '/') or not re.search(r'\$2[aby]\$', t):
        continue
    ctx = ''
    for m in re.finditer(r'([^\n]{0,70}\$2[aby]\$[A-Za-z0-9./$]{53})', t):
        pre = m.group(1)[:m.group(1).find('$2')]
        if re.search(r'password|passwd|hash|bcrypt', pre, re.I):
            ctx = '   ▲ ' + pre[-62:]
            break
    print('     %-46s   hashes=%d%s' % (f.replace('\\', '/').split('backend/')[-1], t.count('$2a$') + t.count('$2b$'), ctx))

print()
print('== [2] auth route mount path + server port + static-tests ==')
for i, l in enumerate(rdp('backend/server.js').splitlines(), 1):
    if re.search(r"app\.use\('/api|listen\(|PORT", l):
        print('     %-70s' % l.strip()[:92])

print()
print('== [3] flutter Api.base  (does app talk to 3000?) ==')
for f in sorted(glob.glob('apps/*_app/lib/api.dart')):
    t = rdp(f)
    m = re.search(r'(?:static\s+)?(?:final|String)\s+\w*[uU]rl\w*\s*=\s*["\']([^"\']+)', t)
    print('     %-18s %s' % (f.split('/apps/')[1], m.group(1) if m else '(not found — searching http)'))
    if not m:
        for i, l in enumerate(t.splitlines(), 1):
            if 'http' in l and 'const' in l:
                print('            %d %s' % (i, l.strip()[:80]))
                break

print()
print('== [4] live probe: 3 logins (best-guess plaintexts) ==')
import urllib.request, urllib.error, json
H = 'http://127.0.0.1:3000'

def call(m, p, body=None, tok=None, timeout=8):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(H + p, data=data, method=m,
        headers={'Content-Type': 'application/json', **({'Authorization': 'Bearer ' + tok} if tok else {})})
    try:
        with urllib.request.urlopen(r, timeout=timeout) as x:
            return x.status, x.read().decode('utf-8', 'replace')
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode('utf-8', 'replace')[:300]
    except Exception as e:
        return None, str(e)[:60]

names = (('admin', 'admin'), ('rahim', 'rahim'), ('karim', 'karim'), ('salma', 'salma'))
plain = ('123456', 'password', 'admin123', 'rahim123', '1234', 'password123', 'school123', 'admin', 'rahim')
found = None
for u, _ in names:
    for p in plain:
        s, b = call('POST', '/api/auth/login', {'username': u, 'password': p})
        if s == 200:
            found = (u, p, b)
            print('     ✅ LOGIN  %-6s / %-12s -> 200 (token!)' % (u, p))
            break
    if found:
        break
if not found:
    for u, _ in names:
        s, b = call('POST', '/api/auth/login', {'username': u, 'password': u + '123'})
        print('     %-6s/%s123  ->  %s %s' % (u, u, s, b[:60]))
    print('     (none matched; passwords may be random per-hash — see [1] for the seed source file)')
else:
    _, pw, body = found
    tok = json.loads(body)['token']
    print()
    print('== [5] authenticated probes (token "%s") ==' % tok[:16])
    for name, m, p in (
            ('teacher /exams', 'GET', '/api/teacher/exams'),
            ('teacher /routine', 'GET', '/api/teacher/routine'),
            ('teacher /subjects', 'GET', '/api/teacher/subjects'),
            ('guardian /students', 'GET', '/api/guardian/students'),
            ('guardian /routine', 'GET', '/api/guardian/routine'),
            ('admin /dashboard', 'GET', '/api/admin/dashboard'),
    ):
        s, b = call(m, p, tok=tok)
        print('     %-20s  %s  %s' % (name, s, b[:120].replace('\n', ' ')))
