#!/usr/bin/env python3
import io, tarfile, sys
from pathlib import Path

def safe_name(name):
    name=name.removeprefix('./')
    p=Path(name)
    if p.is_absolute() or '..' in p.parts: raise RuntimeError('unsafe path '+name)
    return p

def extract_tar(payload, root):
    with tarfile.open(fileobj=io.BytesIO(payload),mode='r:*') as tar:
        for m in tar:
            rel=safe_name(m.name)
            if not str(rel) or str(rel)=='.': continue
            dst=root/rel
            if m.isdir(): dst.mkdir(parents=True,exist_ok=True); dst.chmod(m.mode & 0o7777)
            elif m.issym():
                dst.parent.mkdir(parents=True,exist_ok=True)
                try: dst.unlink()
                except FileNotFoundError: pass
                dst.symlink_to(m.linkname)
            elif m.isfile():
                dst.parent.mkdir(parents=True,exist_ok=True); dst.write_bytes(tar.extractfile(m).read()); dst.chmod(m.mode & 0o7777)
            else: raise RuntimeError('unsupported member '+m.name)

def main(inp,out):
    b=Path(inp).read_bytes(); assert b[:8]==b'!<arch>\n'; q=8; control=data=None
    while q<len(b):
        h=b[q:q+60]; assert h[58:]==b'`\n'; name=h[:16].decode().strip().rstrip('/'); size=int(h[48:58]); q+=60; body=b[q:q+size]; q+=size+size%2
        if name.startswith('control.tar'): control=body
        elif name.startswith('data.tar'): data=body
    assert control is not None and data is not None
    root=Path(out); root.mkdir(parents=True,exist_ok=True); (root/'DEBIAN').mkdir(exist_ok=True)
    extract_tar(control,root/'DEBIAN'); extract_tar(data,root)
    assert (root/'DEBIAN/control').is_file()
if __name__=='__main__': main(sys.argv[1],sys.argv[2])
