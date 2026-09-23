# -*- coding: utf-8 -*-
import io, re, os, glob, json, urllib.request, urllib.error

ROOT = r'C:\Users\WALTON\Desktop\school-system'
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

def wsl(p):
    return p.replace('\\', '/').split('school-system/')[-1]

print('== [1] what is ACTUALLY listening (3000 vs 5000 vs 8899)? ==')
os.system('netstat -ano | findstr LISTENING | findstr ":3000 :5000 :8899"')

print()
print('== [2] the admin web index + main entry existence ==')
for p in ('apps/admin_app/build/web/index.html', 'apps/admin_app/build/web/main.dart.js'):
    print('   %-46s %s' % ('www=' + wsl(p), os.path.getsize(p) if os.path.exists(p) else 'MISSING'))

print()
print('== [3] server.js: api mount + port ==')
t = rdp('backend/server.js')
for i, l in enumerate(t.splitlines(), 1):
    if re.search(r"app\.use\('/api|listen\(|PORT|require\('\./routes/auth'", l):
        print('     %-4d %s' % (i, l.strip()[:98]))

print()
print('== [4] who requires auth (middleware) vs public from auth.js ==')
t = rdp('backend/routes/auth.js')
for i, l in enumerate(t.splitlines(), 1):
    if re.match(r"router\.|const pool|bcrypt|loginLimiter|auth\b", l) and i <= 12:
        print('     %-4d %s' % (i, l.strip()[:98]))

print()
print('== [5] probe login contract — is /login PUBLIC there? ==')

def call(m, p, body=None, tok=None, timeout=8):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request('http://127.0.0.1:3000' + p, data=data, method=m,
        headers={'Content-Type': 'application/json',
                 **({'Authorization': 'Bearer ' + tok} if tok else {})})
    try:
        with urllib.request.urlopen(r, timeout=timeout) as x:
            return x.status, x.read().decode('utf-8', 'replace')[:220]
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode('utf-8', 'replace')[:220]
    except Exception as e:
        return None, str(e)[:60]

for cand in (('rahim', 'rahim'), ('rahim', 'password'), ('rahim', '123456'),
             ('rahim', 'rahim123'), ('admin', 'admin'), ('admin', 'password'), ('admin', '123456')):
    s, b = call('POST', '/api/auth/login', {'username': cand[0], 'password': cand[1]})
    print('     %-6s/%-10s  -> %-4s  %s' % (cand[0], cand[1], s, b[:120].replace('\n', ' ')))
    if s == 200:
        print('         >>> LOGIN OK  (username=%s password=%s)' % cand)
        TOK = json.loads(b).get('token')
        break
else:
    print('     (200 not hit; the 401-string tells us whether login is PUBLIC:')
    print('        "Invalid username or password" = login ran fine, wrong creds')
    print('        "Authentication required"       = a token guard wraps /api/auth (*config issue*))')
    TOK = None

if TOK:
    print()
    print('== [6] authenticated writes (create→list→DELETE same exam) ==')
    s, b = call('POST', '/api/teacher/exams',
                {'name': 'E2E Delete Test - Math', 'class_id': 1, 'subject_id': 2}, tok=TOK)
    print('     POST /teacher/exams  ->  %s  %s' % (s, b[:110]))
    try:
        eid = json.loads(b)['id']
    except Exception:
        eid = None
    if eid:
        s, b2 = call('DELETE', '/api/teacher/exams/%s' % eid, tok=TOK)
        print('     DELETE /teacher/exams/%s -> %s %s' % (eid, s, b2[:90]))
        s, b3 = call('GET', '/api/teacher/exams', tok=TOK)
        print('     re-GET /teacher/exams    -> %s  (still contains deleted id=%s ? %s)'
              % (s, eid, (('"id": %s' % eid) in b3)))
