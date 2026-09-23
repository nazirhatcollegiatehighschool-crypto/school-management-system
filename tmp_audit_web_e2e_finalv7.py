# -*- coding: utf-8 -*-
import io, re, glob, os
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

print('== [1] who makes the seed bcrypt hashes (plaintext clue) ==')
for f in sorted(glob.glob('backend/**/*', recursive=True)):
    if not os.path.isfile(f):
        continue
    ff = f.replace('\\', '/')
    if 'node_modules' in ff or 'build' in ff or 'outputs' in ff:
        continue
    t = rdp(f)
    if '$2a$' not in t and '$2b$' not in t:
        continue
    clue = ''
    for m in re.finditer(r'(.{0,46})(\$2[aby]\$[A-Za-z0-9./$]{53,60})', t):
        pre = m.group(1)
        if re.search(r'password|passwd|hash|bcrypt|password_hash', pre, re.I):
            clue = '  <-- ' + pre[-50:].replace('\n', '\\n')
            break
    print('     %-52s  %s' % (ff.split('backend/')[-1], clue.strip()))
    # also detect an in-repo generator script that WROTE the hashes
re_js = []
for f in sorted(glob.glob('backend/**/*.js', recursive=True)) + sorted(glob.glob('scripts/*.js') if os.path.isdir('scripts') else []):
    t = rdp(f)
    if re.search(r'bcrypt\.(hash|hashSync)|password_hasher|genSeed|seedPassword', t, re.I):
        for i, l in enumerate(t.splitlines(), 1):
            if re.search(r'bcrypt\.(hash|hashSync)|password_hasher|"password"|password\s*=\s*["\']', l, re.I):
                print('        %-34s :%-4d %s' % (f.replace('\\', '/').split('backend/')[-1], i, l.strip()[:92]))
                break
print()
print('== [2] backend port + auth mount ==')
for i, l in enumerate(rdp('backend/server.js').splitlines(), 1):
    if re.search(r"app\.use\('/api|listen\(|PORT", l):
        print('     %s' % l.strip()[:92])
print()
print('== [3] login screen hardcode? (teacher/guardian/admin screens keys + base-url) ==')
for f in sorted(glob.glob('apps/*_app/lib/screens/login_screen.dart') + glob.glob('apps/*_app/lib/api.dart')):
    t = rdp(f)
    kind = 'login-screen' if f.endswith('login_screen.dart') else 'api'
    print('   ---- %s (%s) ----' % (f.split('/apps/')[1].split('/lib')[0], kind))
    if kind == 'login-screen':
        for i, l in enumerate(t.splitlines(), 1):
            if re.search(r"username|password|controller|login", l, re.I) and 'Text(' not in l:
                print('        %4d %s' % (i, l.strip()[:88]))
    else:
        for i, l in enumerate(t.splitlines(), 1):
            if re.search(r"http://|https://|baseUrl|BaseUrl|ip|Ip|const .*Url|String .*= ", l) and 'import' not in l:
                print('        %4d %s' % (i, l.strip()[:88]))
        print()
print('== [4] live probe (3000) routes with no auth / any plaintext ==')
PY