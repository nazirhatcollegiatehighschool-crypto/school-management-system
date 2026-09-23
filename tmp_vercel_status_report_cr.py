# -*- coding: utf-8 -*-
import io, glob, os, re

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

print('== [1] Vercel footprints ==')
found = False
for f in sorted(set(glob.glob('**/vercel.json', recursive=True)) |
                set(glob.glob('**/.vercel/*', recursive=True)) |
                set(glob.glob('**/vercel/**', recursive=True))):
    if any(x in f.replace('\\', '/') for x in ('node_modules', 'build/web/assets')):
        continue
    found = True
    try:
        kind = 'dir ' if os.path.isdir(f) else 'file'
    except Exception:
        continue
    print('     %-46s  %s' % (kind, f.replace('\\', '/')))
if not found:
    print('     (none — no Vercel config, no .vercel deploy lock, no vercel.json)')
print()
print('== [2] rewrite/hosting hints in README(s) ==')
for f in ('README.md', 'backend/README.md'):
    if not os.path.exists(f):
        continue
    t = rdp(f)
    for i, l in enumerate(t.splitlines(), 1):
        if re.search(r'(?i)vercel|deploy|hosting|supabase|railway|আনলাইন|serverless|localhost|PORT|proxy', l):
            print('     %-22s : %4d  %s' % (f.replace('\\', '/'), i, l.strip()[:92]))
print()
print('== [3] where each app (web build) points its API base URL ==')
for A in ('admin_app', 'guardian_app', 'teacher_app'):
    f = 'apps/%s/lib/api.dart' % A
    if not os.path.exists(f):
        continue
    t = rdp(f)
    for i, l in enumerate(t.splitlines(), 1):
        if re.search(r"baseUrl|BaseUrl|http://|https://|String\s+\w*[uU]rl|Api\.", l) and 'import' not in l:
            print('     %-12s : %4d  %s' % (A, i, l.strip()[:92]))
            if 'http' in l:
                break
print()
print('== [4] supabase / serverless-ready migration already present? ==')
for f in glob.glob('backend/supabase*.sql') + glob.glob('backend/*supabase*'):
    if os.path.isfile(f):
        print('     ✓ %s' % f.replace('\\', '/'))
PY