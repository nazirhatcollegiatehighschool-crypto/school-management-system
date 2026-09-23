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

print('SERVE-TEST (no loops, one shot):')
import http.server, threading, subprocess, time
ROOT_APP = 'C:/Users/WALTON/Desktop/school-system/apps/admin_app/build/web'

if not os.path.isdir(ROOT_APP):
    print('   !! build/web missing — run: cd apps/admin_app && flutter build web')
else:
    os.chdir(ROOT_APP)
    h = http.server.SimpleHTTPRequestHandler
    srv = http.server.ThreadingHTTPServer(('127.0.0.1', 8090), h)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    print('   admin web served at  http://127.0.0.1:8090/')
    for u in ('/', '/index.html', '/main.dart.js'):
        s = urllib.request.urlopen('http://127.0.0.1:8090' + u, timeout=15)
        print('      %-14s %s %6d B' % (u, s.status, len(s.read())))
    url = 'http://127.0.0.1:8090/'
    print()
    print('   >>> ADMIN PANEL URL: %s' % url)
    print('       (phone: adb reverse tcp:8090 tcp:8090 → open http://127.0.0.1:8090)')
