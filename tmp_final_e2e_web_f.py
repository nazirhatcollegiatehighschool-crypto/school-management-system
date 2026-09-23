# -*- coding: utf-8 -*-
import io, re, os, glob, json, urllib.request, urllib.error

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

# ============================================================ PART A — seed plaintext discovery
print('== [A1] seed INSERT users rows (plaintext is NOT stored; hash is) — which file?)
for f in sorted(glob.glob('backend/**/*.sql', recursive=True)):
    ff = f.replace('\\', '/')
    t = rdp(f)
    if re.search(r"INSERT INTO users.{0,700}\$2[aby]\$", t, re.S):
        print('   %s  bcrypt-seed=YES' % ff.split('backend/')[-1])
        for i, l in enumerate(t.splitlines(), 1):
            if re.search(r"INSERT INTO users|password_hash", l) and i < 220:
                print('      %4d  %s' % (i, l.strip()[:132]))
                break
print()
print('== [A2] auth.js — json login body + first bcrypt line ==')
t = rdp('backend/routes/auth.js')
for i, l in enumerate(t.splitlines(), 1):
    if re.search(r"router\.post\('/login|req\.body|bcrypt|SELECT \* FROM users", l) and i < 30:
        print('      %4d  %s' % (i, l.strip()[:110]))

# ============================================================ PART B — live e2e (real login attempt)
print()
print('== [B1] backend reachable? (static files exist already) ==')
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
        return e.code, e.read().decode('utf-8', 'replace')[:240]
    except Exception as e:
        return None, str(e)[:60]

s, b = call('GET', '/api/health')
print('   /api/health -> %s  %s' % (s, b[:80]))
s, b = call('GET', '/')
print('   /           -> %s  %s' % (s, b[:60].replace('\n', ' ')))

cands = [
    ('admin', 'admin'), ('admin', 'admin123'), ('admin', '123456'),
    ('admin', 'password'), ('admin', 'school123'),
    ('rahim', 'rahim'), ('rahim', 'password'), ('rahim', '123456'),
    ('rahim', 'rahim123'), ('rahim', 'teacher123'),
    ('karim', 'karim'), ('karim', '123456'),
]
TOK = None
for u, p in cands:
    s, b = call('POST', '/api/auth/login', {'username': u, 'password': p})
    if s == 200:
        TOK = json.loads(b)['token']
        print('   >>> LOGIN OK  %s / %s' % (u, p))
        break
    elif 'token' in b and s == 200:
        TOK = json.loads(b)['token']
        print('   >>> LOGIN OK  %s / %s' % (u, p))
        break
else:
    print('   (no plain login among candidates — the running server may need seed')
print()
if TOK:
    print('== [B2] AUTHENTICATED feature probes (teacher route, full stack) ==')
    for name, m, p, body in (
            ('teacher /routine  ', 'GET', '/api/teacher/routine', None),
            ('teacher /subjects ', 'GET', '/api/teacher/subjects', None),
            ('teacher /exams    ', 'GET', '/api/teacher/exams', None),
            ('teacher/exam POST ', 'POST', '/api/teacher/exams',
             {'name': 'E2E Web Test - Math', 'class_id': 1, 'subject_id': 1, 'exam_type': 'class_test'}),
    ):
        s, b = call(m, p, body, TOK)
        head = b[:110].replace('\n', ' ')
        print('   %-20s -> %s  %s' % (name, s, head))
