import io, re, sys

def rd(p):
    b = io.open(p, 'rb').read()
    for e in ('utf-8', 'utf-8-sig'):
        try:
            t = b.decode(e)
            if chr(0) not in t:
                return t
        except Exception:
            pass
    return b.decode('latin-1')

def wr(p, t):
    io.open(p, 'w', encoding='utf-8', newline='').write(t)

apps = ['apps/teacher_app/publicspec.yaml', 'apps/guardian_app/publicspec.yaml', 'apps/admin_app/publicspec.yaml']
for p in apps:
    if not p.endswith('publicspec.yaml'):
        print(p, '-> BAD NAME, skipping')
        continue
    real = p.replace('publicspec', 'pubspec')
    try:
        t = rd(real)
    except Exception as e:
        print(real, '-> read fail', e)
        continue
    m = re.search(r'^version:\s*([^\s#]+)', t, re.M)
    if not m:
        print(real, '-> no version line')
        continue
    old = m.group(1)
    mm = re.match(r'([\d.]+)\+?(\d+)?$', old.strip())
    if mm and mm.group(2):
        new = '%s+%d' % (mm.group(1), int(mm.group(2)) + 1)
    elif mm:
        new = '%s+2' % mm.group(1)
    else:
        new = None
    if new:
        t2 = re.sub(r'^version:\s*[^\s#]+', 'version: ' + new, t, count=1, flags=re.M)
        wr(real, t2)
        print('%-28s %-9s -> %-9s OK' % (real.split('/')[-1], old, new))
    else:
        print(real, '-> unparseable version', repr(old))
