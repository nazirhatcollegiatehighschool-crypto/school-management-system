# -*- coding: utf-8 -*-
import io, re, glob, os, urllib.request, urllib.error, json, time

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

def hl(p):
    p = p.replace('\\', '/')
    return p.split('backend/')[-1] if 'backend/' in p else p.split('school-system/')[-1]

print('== [1] where are the seed bcrypt hashes produced? (plaintext hunt — server.log + generator) ==')
for f in sorted(glob.glob('backend/**/*', recursive=True)):
    if not os.path.isfile(f):
        continue
    ff = f.replace('\\', '/')
    if any(x in ff for x in ('node_modules', 'build', 'outputs', '.png', '.apk')):
        continue
    try:
        t = rdp(f)
    except Exception:
        continue
    if '$2a$' not in t and '$2b$' not in t:
        continue
    hit = ''
    for m in re.finditer(r'([^\n]{0,44})(\$2[aby]\$[A-Za-z0-9./$]{40,60})', t):
        pre = m.group(1)
        if re.search(r'password|passwd|hash|bcrypt', pre, re.I):
            hit = pre.replace('\n', '\\n')[-58:]
            break
    print('     %-44s  %s' % (hl(f), hit))
print()
print('== [2] auth router: exact route names ==')
t = rdp('backend/routes/auth.js')
for i, l in enumerate(t.splitlines(), 1):
    if re.match(r"\s*router\.(get|post|put|delete)\(", l):
        print('      %-5d %s' % (i, l.strip()[:88]))
print()
print('== [3] backend server port + API mount + static server check ==')
for i, l in enumerate(rdp('backend/server.js').splitlines(), 1):
    if re.search(r"app\.use\('/api|listen\(|PORT", l):
        print('      %-5d %s' % (i, l.strip()[:92]))
print()
print('== [4] live login probes (plaintext guesses against seed) ==')
H = 'http://127.0.0.1:5000'

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
        return None, str(e)[:90]

users = [('admin', 'admin'), ('teacher', 'rahim'), ('teacher', 'karim'), ('teacher', 'salma'), ('teacher', 'hasan')]
plains = ['123456', 'password', 'admin123', 'rahim123', '1234', 'password123', 'school123', 'admin', 'rahim', 'teacher123', '123']
found = None
for role, u in users:
    for p in plains:
        s, b = call('POST', '/api/auth/login', {'username': u, 'password': p})
        if s == 200:
            found = (u, p, b)
            print('      >>> LOGIN  OK  %s / %s' % (u, p))
            break
    if found:
        break
if not found:
    for role, u in users:
        s, b = call('POST', '/api/auth/login', {'username': u, 'password': u + '123'})
        print('      %-8s %-10s -> %s %s' % (role, u, s, b[:50]))
    print('      (no guess matched; see rows above for the generator file that has the real plaintext)')
else:
    u, pw, body = found
    tok = json.loads(body)['token']
    print('      token=%s...' % tok[:20])
    print()
    print('== [5] authenticated probes (CHIP/ASM routes this SESSION builds) ==')
    for name, m, path in (
        ('teacher /routine', 'GET', '/api/teacher/routine'),
        ('teacher /exams', 'GET', '/api/teacher/exams'),
        ('teacher /subjects', 'GET', '/api/teacher/subjects'),
        ('guardian /routine', 'GET', '/api/guardian/routine'),
        ('guardian /students', 'GET', '/api/guardian/students'),
        ('admin /dashboard', 'GET', '/api/admin/dashboard'),
    ):
        s, b = call(m, path, tok=tok)
        print('      %-24s %-4s %s' % (name, s, b[:110].replace('\n', ' ')))

PY