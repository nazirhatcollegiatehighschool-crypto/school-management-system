# -*- coding: utf-8 -*-
"""ONE-shot audit — admin panel web (localhost serving) + vercel-footprints in repo.
Non-invasive: only probes localhost; never touches phone unless adb is up.
"""
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

print('== [1] vercel footprints in repo ==')
found = False
for f in sorted(glob.glob('**/vercel.json', recursive=True)) + sorted(glob.glob('**/.vercel/**', recursive=True)):
    found = True
    print('   %-9s %s' % ('dir' if os.path.isdir(f) else 'file', f.replace('\\', '/')))
for f in glob.glob('**/vercel.json', recursive=True):
    print('   --- %s ---' % f.replace('\\', '/'))
    try:
        print('   ' + rdp(f)[:700].replace('\n', '\n   '))
    except Exception:
        pass
if not found:
    print('   (none found)')
print()
print('== [2] README/deploy mentions ==')
for f in ('README.md', 'backend/README.md'):
    if not os.path.exists(f):
        continue
    t = rdp(f)
    for i, l in enumerate(t.splitlines(), 1):
        if re.search(r'(?i)vercel|deploy|host|supabase|railway|serverless', l):
            print('   %-22s:%4d  %s' % (f.replace('\\', '/'), i, l.strip()[:92]))
print()
print('== [3] admin_app web build artifact present? ==')
w = 'apps/admin_app/build/web'
if os.path.isdir(w):
    js = 'main.dart.js' if os.path.exists(os.path.join(w, 'main.dart.js')) else '(no main.js)'
    print('   %-24s  YES (index.html ✓ %s)' % (w, js))
else:
    print('   %-24s  MISSING — must run: cd apps/admin_app && flutter build web' % w)
print()
print('== [4] local static server for the admin panel (1 command, python http.server) ==')
import http.server, threading, time

ROOT_APP = os.path.join(ROOT, 'apps/admin_app/build/web')
if os.path.isdir(ROOT_APP):
    old = os.getcwd()
    os.chdir(ROOT_APP)
    handler = http.server.SimpleHTTPRequestHandler
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 8822), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    time.sleep(0.6)
    for u in ('/', '/index.html', '/main.dart.js'):
        try:
            r = urllib.request.urlopen('http://127.0.0.1:8822' + u, timeout=10)
            data = r.read()
            print('   http://127.0.0.1:8822%-11s -> %s  %8d B' % (u, r.status, len(data)))
        except Exception as e:
            print('   http://127.0.0.1:8822%-11s -> ERR %s' % (u, str(e)[:40]))
    os.chdir(old)
    print()
    print('   ► ► ►  ADMIN PANEL WEB URL  =  http://127.0.0.1:8822/')
    print('   (open it in any browser on THIS PC — it serves the built admin web)')
    print()
    print('   NOTE re: Vercel — this repo has NO vercel.json/.vercel; and the backend is')
    print('   Express+MySQL (not serverless). For a PUBLIC URL you would need to host the')
    print('   backend on a server (Railway/Render/VPS) and point the web build at it, or')
    print('   adapt to Supabase (supabase_migration_full.sql already exists in backend/).')
