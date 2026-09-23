# -*- coding: utf-8 -*-
import io, re, glob, os, json, urllib.request, urllib.error

ROOT = 'C:/Users/WALTON/Desktop/school-system'

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

print('== [1] which sql files ACTUALLY contain the BCrypt seed for users? ==')
for f in sorted(glob.glob('backend/**/*.sql', recursive=True)):
    if 'node_modules' in f:
        continue
    ff = f.replace('\\', '/')
    try:
        t = rdp(f)
    except Exception:
        continue
    if re.search(r"INSERT INTO users.{0,900}\$2[aby]\$[A-Za-z0-9./$]{53}", t, re.S):
        hits = []
        for i, l in enumerate(t.splitlines(), 1):
            if 'INSERT INTO users' in l or re.search(r"\$2[aby]\$", l):
                hits.append((i, l))
        print('   %s   (%d insert/hash lines)' % (ff.split('backend/')[-1], len(hits)))
        for i, l in hits[:2]:
            print('      %4d  %s' % (i, l.strip()[:150]))

print()
print('== [2] the SECRET is which plaintext? look for a bcrypt hashing SCRIPT that made it ==')
for f in sorted(glob.glob('backend/**/*.js', recursive=True)) + sorted(glob.glob('**/*.js', recursive=True)):
    if any(x in f for x in ('node_modules', 'build', 'outputs')):
        continue
    try:
        t = rdp(f)
    except Exception:
        continue
    m = re.search(r"bcrypt\.(hash|hashSync)\(['\"]([^'\"]{2,40})['\"]", t)
    if m:
        print('   %-46s  plaintext-candidate = %r' % (f.replace('\\', '/').split('school-system/')[-1], m.group(2)))
print()
print('== [3] admin web build + flutter web devices (ready to serve?) ==')
import os
webf = glob.glob('apps/admin_app/build/web/*')
print('   admin build/web entries = %d' % len(webf))
for f in sorted(webf)[:6]:
    print('      %s' % f.replace('\\', '/').split('build/web/')[-1])

print()
print('== [4] backendserver: port + how it listens (config plan) ==')
for f in ('backend/server.js', 'backend/index.js'):
    if not os.path.exists(f):
        continue
    t = rdp(f)
    for i, l in enumerate(t.splitlines(), 1):
        if re.search(r"listen\(|PORT|process\.env\.PORT", l):
            print('   %s:%d  %s' % (f.split('backend/')[-1], i, l.strip()[:94]))

print()
print('== [5] e2e-login probe (live) — find a working account to drive admin web ==')
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
        return e.code, e.read().decode('utf-8', 'replace')[:220]
    except Exception as e:
        return None, str(e)[:60]

s, b = call('GET', '/api/health')
print('   /api/health -> %s %s' % (s, b[:60]))
TOK = None
for u, p in (('admin', 'admin123'), ('admin', '123456'), ('admin', 'password'),
             ('admin', 'admin'), ('rahim', '123456'), ('rahim', 'password'),
             ('rahim', 'rahim123'), ('rahim', 'rahim')):
    s, b = call('POST', '/api/auth/login', {'username': u, 'password': p})
    if s == 200:
        print('   >>> CORRECT LOGIN  %s / %s' % (u, p))
        try:
            TOK = json.loads(b)['token']
        except Exception:
            TOK = None
        break
    else:
        print('   %-8s / %-10s -> %s %s' % (u, p, s, b[:66].replace('\n', ' ')[:66]))
if not TOK:
    print('   (no candidate matched — the real password is generated at seed time;')
    print('    the plaintext is NOT stored — but the WEB panel will accept whatever the')
    print('    DATABASE current users hold; if you previously changed teacher accounts,')
    print('    those are the ones to use. None of our guesses matched.)')
else:
    print()
    t = ''
    for name, m, p, body in (
            ('teacher /routine ', 'GET', '/api/teacher/routine', None),
            ('teacher /exams   ', 'GET', '/api/teacher/exams', None),
            ('teacher exam POST', 'POST', '/api/teacher/exams',
             {'name': 'E2E Web', 'class_id': 1, 'subject_id': 1}),
            ('guardian /routine', 'GET', '/api/guardian/routine', None),
            ('admin /dashboard ', 'GET', '/api/admin/dashboard', None),
    ):
        try:
            s, b = call(m, p, body, TOK)
            print('      %-20s %s  %s' % (name, s, b[:80].replace('\n', ' ')[:80]))
        except Exception as e:
            print('      %-20s err %r' % (name, e))
