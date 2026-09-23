# -*- coding: utf-8 -*-
import io, re, json, urllib.request, urllib.error

H = 'http://127.0.0.1:3000'

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
        return e.code, e.read().decode('utf-8', 'replace')[:220]
    except Exception as e:
        return None, str(e)[:50]

print('== [1] seed users table (id,role,username,hash,bcrypt-hash-base) ==')
t = rdp('backend/schema.sql')
rows = []
for i, l in enumerate(t.splitlines(), 1):
    if re.match(r"\s*\((\d+),\s*'", l) and ('admin' in l or 'teacher' in l or 'guardian' in l):
        m = re.match(r"\s*\(\d+,\s*'(\w+)',\s*'(\w+)',\s*'(\$2[aby]\$[^']+)'", l)
        if m:
            rows.append((i, m.group(1), m.group(2), m.group(3)[:31]))
            print('     %-36s :%3d  role=%-8s user=%-8s  hash=%s' % (
                'schema.sql', i, m.group(1), m.group(2), m.group(3)[:36]))

print()
print('   == brute list (common dev seeds) against each ==')
plains = ['123456', 'password', '1234', '12345678', 'admin123', 'password123',
          'rahim123', 'rahim', 'admin', 'ashif', 'karim', 'salma', 'priyanka',
          'admin@123', '12345', 'qwerty', 'school', 'school123', 'test123',
          'rahimuddin', 'rahim1234', 'admin@school', 'admin1234']
found = None
for _, role, u, h in rows:
    for p in plains:
        s, b = call('POST', '/api/auth/login', {'username': u, 'password': p})
        if s == 200:
            found = (u, p, json.loads(b)['token'])
            print('     >>> LOGIN OK  %s / %s' % (u, p))
            break
    if found:
        break

print()
print('== [2] auth.js router line (login body) + server mount/port ==')
for f in ('backend/routes/auth.js', 'backend/server.js'):
    for i, l in enumerate(rdp(f).splitlines(), 1):
        if re.search(r"router\.(post|get)\(|app\.use\('/api|listen\(|PORT\s*=", l):
            print('     %-18s:%4d  %s' % (f.split('backend/')[-1], i, l.strip()[:96]))
