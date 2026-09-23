# -*- coding: utf-8 -*-
import io, glob, re, os, subprocess

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

print('== [1] web folders present? ==')
for f in sorted(glob.glob('apps/*_app/web/*')):
    print('    %s' % f.replace('\\', '/'))

print('== [2] web-guards in each main.dart ==')
for f in sorted(glob.glob('apps/*_app/lib/main.dart')):
    app = f.split('apps/')[1].split('/lib')[0]
    t = rdp(f)
    print('    %-16s kIsWeb=%d dart:io=%d window.= %d' % (
        app, t.count('kIsWeb'), t.count("dart:io"), t.count('window.')))

print('== [3] backend: static html/web dashboard? ==')
for f in ('backend/index.js', 'backend/server.js', 'backend/app.js'):
    if not os.path.exists(f):
        continue
    for i, l in enumerate(rdp(f).splitlines(), 1):
        if re.search(r'express\.static|route|\.html|dashboard|admin', l, re.I):
            print('    %s:%d  %s' % (f, i, l.strip()[:90]))

print('== [4] flutter web device available? ==')
import subprocess
try:
    out = subprocess.run(['C:/Users/WALTON/flutter/bin/flutter.bat', 'devices'],
                         capture_output=True, text=True, timeout=120, env=dict(os.environ, PATH=r'C:\Users\WALTON\flutter\bin;' + os.environ.get('PATH', ''))).stdout
    for l in out.splitlines():
        if re.search(r'web-server|chrome', l):
            print('    %s' % l.strip()[:80])
except Exception as e:
    print('    flutter devices rm=%r' % e)
