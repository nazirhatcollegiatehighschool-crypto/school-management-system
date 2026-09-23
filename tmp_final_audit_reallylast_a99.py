# -*- coding: utf-8 -*-
import io, re, glob, os, json

ROOT = r'C:\Users\WALTON\Desktop\school-system'

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

def sl(x):
    return x.replace(chr(92), '/')

print('== [A] EVERY user-password ctx in README/*.md/docs + root files ==')
seen = set()
for f in glob.glob('**/*.md', recursive=True) + glob.glob('*.txt') + glob.glob('docs/**/*.md', recursive=True):
    ff = sl(f)
    if any(x in ff for x in ('node_modules', 'build', '.dart_tool')):
        continue
    try:
        t = rdp(f)
    except Exception:
        continue
    for i, l in enumerate(t.splitlines(), 1):
        ll = l.strip()
        if re.search(r'(?i)(username|login|log\s*in|password|পাসওয়ার্ড|লগইন).{0,44}(?:admin|teacher|guardian|rahim|karim|salma|123|school)', ll):
            key = (f, i)
            if key in seen:
                continue
            seen.add(key)
            print('     %-44s :%4d  %s' % (ff.split('school-system/')[-1], i, ll[:104]))
if not seen:
    print('     (none)')

print()
print('== [B] server.log tail: look for "curl", "login", seeded username prints ==')
if os.path.exists('backend/server.log'):
    t = rdp('backend/server.log')
    for i, l in enumerate(t.splitlines(), 1):
        if re.search(r'(?i)login|seed|rahim|karim|password|started|listening', l):
            print('     %4d  %s' % (i, l.strip()[:110]))
    print('     (total %d lines)' % len(t.splitlines()))

print()
print('== [C] pairing: auth.js line 10 SELECT — password_hash column; use that column to WIPE-test login? (we do NOT wipe — instead) list the 3 route mappers that RETURN is_escape in routine already ==')
for f in ('backend/routes/teacher.js', 'backend/routes/guardian.js', 'backend/routes/admin.js'):
    t = rdp(f)
    print('     %-14s is_escape-returning-select count=%d  escape-col reacts for routine=%d' % (
        f.split('backend/routes/')[-1], t.count('is_escape'), t.count('CASE WHEN a.is_escape')))

print()
print('== [D] do the 3 Flutter apps *already* have a working delete on their MY-EXAM list? verify 1 get each ==')
import urllib.request, urllib.error

H = 'http://127.0.0.1:3000'

def call(m, p, body=None, tok=None, timeout=6):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(H + p, data=data, method=m,
        headers={'Content-Type': 'application/json', **({'Authorization': 'Bearer ' + tok} if tok else {})})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as x:
            return x.status, x.read().decode('utf-8', 'replace')
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode('utf-8', 'replace')
    except Exception as e:
        return None, str(e)[:60]

# REAL seed creds hunt — this server was seeded by a pass of the previous session.
# We know the SHA of the seed comment: look for a `password` column comment in schema.sql users table
t = rdp('backend/schema.sql')
for i, l in enumerate(t.splitlines(), 1):
    if re.search(r"password_hash|username|role.*ENUM|users \(", l) and 100 < i < 138:
        print('     %4d  %s' % (i, l.strip()[:116]))
print()
print('     ----- seed INSERT (final 4 lines) -----')
for i, l in enumerate(t.splitlines(), 1):
    if 138 <= i <= 144:
        print('     %4d  %s' % (i, l.strip()[:150]))
