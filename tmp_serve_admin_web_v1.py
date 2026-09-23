# -*- coding: utf-8 -*-
"""Serve the BUILT admin Flutter web (apps/admin_app/build/web) on 127.0.0.1:8822
and give login credentials by resetting a known admin password in the LOCAL MySQL
(only for this machine's demo; live Vercel deploy is separate)."""
import http.server, threading, io, os, glob, re, subprocess

WEB = 'C:/Users/WALTON/Desktop/school-system/apps/admin_app/build/web'

# ---------- 1) start static server on 8822 ----------
old = os.getcwd()
os.chdir(WEB)
srv = http.server.ThreadingHTTPServer(('127.0.0.1', 8822), http.server.SimpleHTTPRequestHandler)
threading.Thread(target=srv.serve_forever, daemon=True).start()
os.chdir(old)

print('== [1] admin panel web — local static server ==')
print('   ►►  URL  http://127.0.0.1:8822/   (এই PC-তে এখন খুলুন)')
for u in ('/', '/index.html', '/main.dart.js'):
    try:
        r = urllib.request.urlopen('http://127.0.0.1:8822' + u, timeout=10)
        print('       GET %-13s -> %s  %d B' % (u, r.status, len(r.read())))
    except Exception as e:
        print('       GET %-13s -> %s' % (u, str(e)[:60]))
