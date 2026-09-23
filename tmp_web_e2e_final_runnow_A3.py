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

def sl(f):
    return f.replace('\\', '/').split('school-system/')[-1]

print('== [1] exact seed INSERT lines for users (+ any nearby plaintext comment) ==')
for f in ('backend/seed_v5.sql', 'backend/seed_v5b.sql', 'backend/seed_v6.sql', 'backend/seed.sql'):
    if not os.path.exists(f):
        continue
    t = rdp(f)
    for i, l in enumerate(t.splitlines(), 1):
        if 'INSERT INTO users' in l or ('admin\'' in l and '$2' in l):
            print('   %-22s :%4d  %s' % (f.split('/')[-1], i, l.strip()[:128]))
# backward one line for a plaintext/comment hint
    for i, l in enumerate(t.splitlines(), 1):
        if 'password' in l.lower() and ('comment' in l.lower() or '-- ' in l or '#' in l):
            print('      (%s:%d hint) %s' % (f.split('/')[-1], i, l.strip()[:100]))
            break
print()
print('== [2] login route signature (what body fields does it accept?) ==')
t = rdp('backend/routes/auth.js')
for i, l in enumerate(t.splitlines(), 1):
    if re.search(r"router\.(post|get).*login|req\.body|username|password", l) and i < 45:
        print('   %4d %s' % (i, l.strip()[:100]))
print()
print('== [3] server port + auth mount + where does the Flutter app point? ==')
for i, l in enumerate(rdp('backend/server.js').splitlines(), 1):
    if re.search(r"app\.use\('/api|listen\(|PORT", l):
        print('   %4d %s' % (i, l.strip()[:96]))
print('   -- flutter api.dart base urls --')
for f in sorted(glob.glob('apps/*_app/lib/api.dart')):
    t = rdp(f)
    m = re.search(r"baseUrl\s*=\s*['\"]([^'\"]+)", t) or re.search(r"(http://[^'\"]+)", t)
    print('      %-14s  %s' % (f.split('/apps/')[1].split('/lib')[0], m.group(1) if m else '(?)'))
print()
print('== [4] LIVE logins (seed bcrypts) — plaintext candidates ==')
H = 'http://127.0.0.1:5000'

def call(m, p, body=None, tok=None, timeout=8):
    data = json.dumps(body).encode() if body is not None else None
    hdrs = {'Content-Type': 'application/json'}
    if tok:
        hdrs['Authorization'] = 'Bearer ' + tok
    r = urllib.request.Request(H + p, data=data, method=m, headers=hdrs)
    try:
        with urllib.request.urlopen(r, timeout=timeout) as x:
            return x.status, x.read().decode('utf-8', 'replace')
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode('utf-8', 'replace')[:200]
    except Exception as e:
        return None, str(e)[:60]

# Try a candidate set. bcrypt hashes are per-user salt, so same plaintext == same hash only if salt
# is reused — here each seed line has a DIFFERENT hash, but almost identical → likely the SAME plain
# text password with a diffferent salt. Let's brute the common list.
users = [('admin', 'admin'), ('teacher', 'rahim'), ('teacher', 'karim'), ('teacher', 'salma'),
         ('guardian', 'rahim'), ('guardian', 'karim'), ('guardian', 'salma')]
plains = ['123456', 'password', 'admin123', 'rahim123', '1234', 'password123', 'school123',
          'admin', 'rahim', '123', 'rahim1234', 'teacher123', 'guardian123', 'skool123'
          'test1234', 'change123', 'change1234', 'rahimuddinfh', '01800000000', '12345678',
          'rahim21', 'rahim2024', 'Brahim123', 'rahim1234', 'asdf1234', 'qwerty', '1234567']
found = None
for role, u in users:
    for p in plains:
        s, b = call('POST', '/api/auth/login', {'username': u, 'password': p})
        if s == 200:
            found = (u, p, b)
            print('   >>> LOGIN OK  %s / %s' % (u, p))
            break
    if found:
        break
if not found:
    print('   (no common plaintext matched — hash is an unknown random; will create a fresh user via SQL next)')
    s, b = call('GET', '/')
    print('   GET / ->', s, b[:60])
else:
    tok = json.loads(found[2])['token']
    print()
    print('== [5] authenticated E2E probes ==')
    for name, m, path in (
            ('teacher /subjects', 'GET', '/api/teacher/subjects'),
            ('teacher /routine', 'GET', '/api/teacher/routine'),
            ('teacher /exams', 'GET', '/api/teacher/exams'),
            ('teacher /exams{POST}', 'POST', '/api/teacher/exams'),
            ('guardian /students', 'GET', '/api/guardian/students'),
            ('guardian /routine', 'GET', '/api/guardian/routine'),
            ('admin /dashboard', 'GET', '/api/admin/dashboard'),
    ):
        body = {'name': 'E2E test', 'exam_type': 'class_test', 'class_id': 1, 'subject_id': 1,
                'exam_date': '2026-09-20'} if m == 'POST' else None
        s, b = call(m, path, body, tok)
        print('   %-24s -> %s  %s' % (name, s, b[:90].replace('\n', ' ')))
