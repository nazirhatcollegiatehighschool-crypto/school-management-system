# -*- coding: utf-8 -*-
import io, glob, os, re, json, urllib.request, urllib.error

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

print('== [1] vercel footprints ==')
found = False
for f in sorted(glob.glob('**/vercel.json', recursive=True)) + sorted(glob.glob('**/.vercel/**', recursive=True)):
    found = True
    if os.path.isdir(f):
        print('   dir   %s' % f.replace('\\', '/'))
    else:
        print('   file  %s' % f.replace('\\', '/'))
for f in glob.glob('**/vercel.json', recursive=True):
    t = rdp(f)
    print('   --- %s ---' % f.replace('\\', '/'))
    print(t[:700])
    print()
if not found:
    print('   (none — no Vercel config in this repo)')
print()
print('== [2] README / docs deployment mentions ==')
for f in ('README.md', 'backend/README.md'):
    if not os.path.exists(f):
        continue
    t = rdp(f)
    for i, l in enumerate(t.splitlines(), 1):
        if re.search(r'(?i)vercel|deploy|host|supabase|railway|online|serverless', l):
            print('   %-22s:%4d  %s' % (f.replace('\\', '/'), i, l.strip()[:92]))
print()
print('== [3] does the running backend already serve the admin web? ==')

def probe(m, p, body=None, tok=None, timeout=6):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request('http://127.0.0.1:3000' + p, data=data, method=m,
        headers={'Content-Type': 'application/json',
                 **({'Authorization': 'Bearer ' + tok} if tok else {})})
    try:
        with urllib.request.urlopen(r, timeout=timeout) as x:
            return x.status, x.read().decode('utf-8', 'replace')[:140]
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode('utf-8', 'replace')[:140]
    except Exception as e:
        return None, str(e)[:50]

for i, (u, pw) in enumerate((('admin', 'admin'), ('admin', 'admin123'), ('admin', '123456'),
                             ('admin', 'password'), ('admin', 'school123'),
                             ('rahim', 'rahim'), ('rahim', 'password'),
                             ('rahim', '123456'), ('karim', '123456'))):
    s, b = probe('POST', '/api/auth/login', {'username': u, 'password': pw})
    print('   login %-7s / %-10s -> %s  %s' % (u, pw, s, b[:70].replace('\n', ' ')))
    if s == 200:
        break

print()
print('== [4] admin_app api base URL + backend db (mysql or supabase?) ==')
for f in ('apps/admin_app/lib/api.dart', 'backend/db.js'):
    if not os.path.exists(f):
        continue
    t = rdp(f)
    print('   --- %s ---' % f.replace('\\', '/'))
    for i, l in enumerate(t.splitlines(), 1):
        if re.search(r"(?i)http|baseUrl|base_url|mysql|createPool|postgres|supabase|PGHOST|DATABASE_URL|new Pool|host\s*:", l):
            print('     %4d  %s' % (i, l.strip()[:100]))
    print()
