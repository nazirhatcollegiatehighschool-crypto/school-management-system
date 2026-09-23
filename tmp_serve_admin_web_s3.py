# -*- coding: utf-8 -*-
"""Admin panel web — local static server on 127.0.0.1:8822 (this PC's browser)."""
import http.server, threading, os, urllib.request, io

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

import glob, os
WEB = None
for c in ('apps/admin_app/build/web', 'apps/admin_app/build/web/'):
    if os.path.isdir(c):
        WEB = c
        break
print('== admin_app web build fold ==')
if WEB is None:
    print('   !! BUILD NOT FOUND — need `flutter build web` in apps/admin_app')
    raise SystemExit
for x in ('index.html', 'main.dart.js', 'flutter_bootstrap.js'):
    p = os.path.join(WEB, x)
    print('   %-18s %s  %d B' % (x, 'OK' if os.path.exists(p) else '—', os.path.getsize(p) if os.path.exists(p) else 0))
