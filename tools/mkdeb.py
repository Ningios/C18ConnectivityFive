#!/usr/bin/env python3
import os,sys,time

def pack(out, d):
    names=['debian-binary','control.tar.gz','data.tar.xz']
    with open(out,'wb') as f:
        f.write(b'!<arch>\n')
        for name in names:
            data=open(os.path.join(d,name),'rb').read()
            h=f"{name:<16}{int(time.time()):<12}{0:<6}{0:<6}{'100644':<8}{len(data):<10}`\n".encode()
            if len(h)!=60: raise SystemExit(f'bad ar header {len(h)}')
            f.write(h); f.write(data)
            if len(data)&1: f.write(b'\n')
if __name__=='__main__':
    if len(sys.argv)!=3: raise SystemExit('mkdeb.py OUT MEMBER_DIR')
    pack(sys.argv[1],sys.argv[2]); print(sys.argv[1],os.path.getsize(sys.argv[1]))
