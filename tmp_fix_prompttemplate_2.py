# -*- coding: utf-8 -*-
import io, re

def rd(p):
    b = io.open(p, 'rb').read()
    for e in ('utf-8', 'utf-8-sig'):
        try:
            t = b.decode(e)
            if '\x00' not in t:
                return t
        except Exception:
            pass
    return b.decode('latin-1')

def wr(p, t):
    io.open(p, 'w', encoding='utf-8', newline='').write(t)

P = 'apps/teacher_app/lib/screens/student_registration_screen.dart'
t = rd(P)

# 1) the definition around line 125: change  String _promptTemplate()  ->  String get _promptTemplate
for m in re.finditer(r'\n(\s*)String\s+_promptTemplate\s*\(\)\s*\{', t):
    print('   def at %d: %r' % (m.start(), m.group(0)[:60]))
pre, post = re.split(r'(?<=\})\n\s*/// চ structural', t, maxsplit=1) if False else (None, None)

# replace the function header only
t2 = re.sub(r'\n(\s*)String\s+_promptTemplate\s*\(\)\s*\{',
            r'\n\1String get _promptTemplate {', t, count=1)
print('   header->getter changed:', t2 != t)

# 2) line 444 call site:  _promptTemplate  (already a getter, keep bare)
# 3) ensure the trailing closing of that method has no leftover, verify braces balance within the method body
seg = t2[t2.find('String get _promptTemplate {'):]
seg = seg[:seg.find('\n  }')+4]
print('   getter body head: %r' % seg[:120])

# 4) extract _promptTemplate body for a brace-balance sanity (lines 125-141 region)
L = t2.splitlines()
print('\n   lines 123-142:')
for i in range(123, 143):
    print('%5d %s' % (i, L[i-1][:110]))

wr(P, t2)
print('\nwrote %s' % P)
