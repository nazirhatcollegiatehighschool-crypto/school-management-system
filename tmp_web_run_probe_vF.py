import io
def rdp(p):
 b=io.open(p,'rb').read()
 for e in ('utf-8','utf-8-sig'):
  try:
   t=b.decode(e)
   if '\x00' not in t: return t
  except: pass
 return b.decode('latin-1')
print('  kind   build-folder(s)          index.html  build/web/')
import glob,os
for A in ('admin_app','teacher_app','guardian_app'):
 w=glob.glob('apps/%s/build/web/index.html'%A)
 b=glob.glob('apps/%s/build/web/main.dart.js'%A)
 print('  %-9s  build/web=%-6s index=%s  entry=%s'%(A,
   'YES' if os.path.isdir('apps/%s/build/web'%A) else 'no', 'ok' if w else '—', 'ok' if b else '—'))
