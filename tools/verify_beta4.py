#!/usr/bin/env python3
import io,tarfile,hashlib,struct,plistlib,sys
from pathlib import Path
p=Path(sys.argv[1]); b=p.read_bytes(); assert b[:8]==b'!<arch>\n'; q=8; members={}
while q<len(b):
 h=b[q:q+60]; assert h[58:]==b'`\n'; n=h[:16].decode().strip().rstrip('/');z=int(h[48:58]);q+=60;members[n]=b[q:q+z];q+=z+z%2
assert set(members)=={'debian-binary','control.tar.gz','data.tar.gz'} and members['debian-binary']==b'2.0\n'
control=''; files={}; links={}
for n,body in members.items():
 if n.startswith('control') or n.startswith('data'):
  with tarfile.open(fileobj=io.BytesIO(body),mode='r:*') as t:
   for m in t:
    name=m.name.removeprefix('./'); assert not name.startswith('/') and '..' not in Path(name).parts; assert m.uid==m.gid==0
    if m.issym(): links[name]=m.linkname
    elif m.isfile():
     data=t.extractfile(m).read(); files[name]=data
     if n.startswith('control') and name=='control': control=data.decode()
assert 'Version: 3.0-beta4-five2\n' in control and 'Maintainer: Ning&evgeniy558\n' in control
assert 'Author: Ning&evgeniy558\n' in control
new='Library/MobileSubstrate/DynamicLibraries/C18ConnectivityFive.dylib'; plist='Library/MobileSubstrate/DynamicLibraries/C18ConnectivityFive.plist'
assert new in files and plist in files
f=plistlib.loads(files[plist]); assert f['Filter']['Bundles']==['com.apple.springboard']
d=files[new]; assert struct.unpack_from('>II',d)==(0xcafebabe,2)
subs=[]
for i in range(2): subs.append(struct.unpack_from('>IIIII',d,8+20*i)[1])
assert set(subs)=={0,0x80000002}
print('VERIFY_OK',p.stat().st_size,hashlib.sha256(d).hexdigest(),[hex(x) for x in subs],'control/data members',len(files),'links',len(links))
