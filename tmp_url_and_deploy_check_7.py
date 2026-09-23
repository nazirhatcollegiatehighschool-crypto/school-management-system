# -*- coding: utf-8 -*-
import io, glob, os, re, json, urllib.request, urllib.error

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

print('== [1] each Flutter app URL config ==')
for f in sorted(glob.glob('apps/*/lib/config.dart')):
    t = rdp(f)
    m = re.search(r"defaultValue:\s*'([^']+)'", t)
    print('   %-52s %s' % (f.replace('\\', '/'), (m.group(1) if m else '(none)')))
print()
print('== [2] active API_URL overrides (build --dart-define)? read .env / README ==')
for f in ('apps/README.md', 'apps/teacher_app/README.md', 'README.md'):
    if not os.path.exists(f):
        continue
    t = rdp(f)
    for i, l in enumerate(t.splitlines(), 1):
        if re.search(r'(?i)API_URL|vercel|dart-define|build web|flutter build', l):
            print('   %-30s:%4d  %s' % (f.replace('\\', '/'), i, l.strip()[:96]))
print()
print('== [3] backend: db provider + README for deploy ==')
for f in ('backend/README.md', 'backend/server.js', 'backend/.env.example'):
    if not os.path.exists(f):
        continue
    t = rdp(f)
    print('   --- %s ---' % f.replace('\\', '/'))
    for i, l in enumerate(t.splitlines(), 1):
        if re.search(r'(?i)supabase|mysql|CLEARDB|DB_|pooler|DATABASE_URL|port\b|listen\b', l):
            print('      %4d  %s' % (i, l.strip()[:92]))
    print()
print('== [4] live backend status now ==')
probes = [('GET', '/api/health'), ('POST', '/api/auth/login'),
          ('GET', '/api/routine/slots'), ('GET', '/api/teacher/routine/mine')]
for m, p in probes:
    req = urllib.request.Request('http://127.0.0.1:3000' + p, method=m,
        headers={'Content-Type': 'application/json'})
    try:
        r = urllib.request.urlopen(req, timeout=6)
        print('   %-5s %-32s -> %s  %s' % (m, p, r.status, r.read().decode('utf-8', 'replace')[:54]))
    except urllib.error.HTTPError as e:
        print('   %-5s %-32s -> %s  %s' % (m, p, e.code, e.read().decode('utf-8', 'replace')[:54]))
    except Exception as e:
        print('   %-5s %-32s -> ERR %s' % (m, p, str(e)[:44]))
