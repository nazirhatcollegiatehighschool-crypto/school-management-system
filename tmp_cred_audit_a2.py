# -*- coding: utf-8 -*-
import io, re, glob, os, json

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

print('== [1] every backend router file: login route path & its body keys ==')
for f in sorted(glob.glob('backend/**/*.js', recursive=True)):
    if 'node_modules' in f:
        continue
    t = rdp(f)
    for i, l in enumerate(t.splitlines(), 1):
        if re.search(r"router\.(post|get)\(['\"](?!.*:id)[^'\"]*(?:login|signin|auth)[^'\"]*['\"]", l, re.I):
            k = '|'.join(re.findall(r"req\.body\.(\w+)|\{\s*(\w+)\s*\}", l) or ['?'])
            print('    %-34s :%4d  %s' % (f.replace('\\', '/').split('backend/')[-1], i, l.strip()[:92]))

print()
print('== [2] FRONTEND: which login endpoint do the apps call? ==')
for f in sorted(glob.glob('apps/*_app/lib/**/*.dart', recursive=True)):
    try:
        t = rdp(f)
    except Exception:
        continue
    fn = f.replace('\\', '/').split('apps/')[1]
    if re.search(r"auth/(login|signin)|Api\.post\(['\"]/(auth|api/auth)", t, re.I):
        for i, l in enumerate(t.splitlines(), 1):
            if re.search(r"login|signin|auth", l, re.I) and "HttpHeaders" not in l:
                print('    %-32s :%4d  %s' % (fn, i, l.strip()[:84]))
                break
print()
print('== [3] bcrypt hashes in any seed = all same? (=> known plaintext?) ==')
hs = set()
for f in glob.glob('backend/*.sql'):
    t = rdp(f)
    for m in re.finditer(r"\$2[aby]\$[^\'\"]{50,80}", t):
        hs.add(m.group(0))
for h in sorted(hs):
    print('    %s' % h[:68])
print('    (unique hash count = %d)' % len(hs))

print()
print('== [4] server entry + port ==')
for f in ('backend/server.js', 'backend/index.js', 'backend/app.js'):
    if not os.path.exists(f):
        continue
    t = rdp(f)
    for i, l in enumerate(t.splitlines(), 1):
        if re.search(r"listen\(|PORT|express\(\)|\.use\(['\"]/api|routes", l):
            print('    %-10s :%4d  %s' % (f.split('/')[-1], i, l.strip()[:86]))
