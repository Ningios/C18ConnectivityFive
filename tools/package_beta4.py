#!/usr/bin/env python3
"""Overlay the companion engine onto our beta4 without touching the reference sample."""
import io, tarfile, gzip, hashlib, re
from pathlib import Path
from mkdeb import pack

BASE=Path('dist/base'); PKG=Path('dist/pkg'); MEMBERS=Path('dist/members')
OUT=Path('dist/com.evgeniy558.controlcenter18_3.0-beta4-five2_iphoneos-arm64e.deb')

def copy_member(tar, member, root):
    name=member.name
    if not name or name in ('./','.'):
        return
    rel=Path(name.removeprefix('./'))
    if rel.is_absolute() or '..' in rel.parts: raise RuntimeError('unsafe path '+name)
    dst=root/rel
    if member.isdir(): dst.mkdir(parents=True,exist_ok=True)
    elif member.issym():
        dst.parent.mkdir(parents=True,exist_ok=True)
        try: dst.unlink()
        except FileNotFoundError: pass
        dst.symlink_to(member.linkname)
    elif member.isfile():
        dst.parent.mkdir(parents=True,exist_ok=True); dst.write_bytes(tar.extractfile(member).read()); dst.chmod(member.mode & 0o7777)
    else: raise RuntimeError('unsupported tar member '+name)

def extract_deb(path, root):
    b=Path(path).read_bytes(); assert b[:8]==b'!<arch>\n'; data=None; control=None; q=8
    while q<len(b):
        h=b[q:q+60]; assert h[58:]==b'`\n'; name=h[:16].decode().strip().rstrip('/'); z=int(h[48:58]); q+=60; body=b[q:q+z]; q+=z+z%2
        if name.startswith('control.tar'): control=body
        elif name.startswith('data.tar'): data=body
    assert control is not None and data is not None
    (root/'DEBIAN').mkdir(parents=True,exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(control),mode='r:*') as tar:
        for m in tar: copy_member(tar,m,root/'DEBIAN')
    with tarfile.open(fileobj=io.BytesIO(data),mode='r:*') as tar:
        for m in tar: copy_member(tar,m,root)
    assert (root/'DEBIAN/control').exists()

def write_tar_gz(path, root, exclude_debian):
    buf=io.BytesIO()
    with tarfile.open(fileobj=buf,mode='w',format=tarfile.USTAR_FORMAT) as tar:
        for p in [root]+sorted(root.rglob('*')):
            rel=p.relative_to(root)
            if exclude_debian and rel.parts and rel.parts[0]=='DEBIAN': continue
            name='.' if p==root else './'+rel.as_posix()
            info=tarfile.TarInfo(name); info.uid=info.gid=0; info.uname=info.gname='root'; info.mtime=0
            if p.is_symlink(): info.type=tarfile.SYMTYPE; info.linkname=p.readlink().as_posix(); info.mode=0o777; tar.addfile(info)
            elif p.is_dir(): info.type=tarfile.DIRTYPE; info.mode=0o755; tar.addfile(info)
            elif p.is_file():
                data=p.read_bytes(); info.size=len(data); info.mode=p.stat().st_mode & 0o7777; tar.addfile(info,io.BytesIO(data))
    with open(path,'wb') as f:
        with gzip.GzipFile(fileobj=f,mode='wb',mtime=0) as g:g.write(buf.getvalue())

def main():
    for p in (PKG,MEMBERS):
        if p.exists():
            import shutil; shutil.rmtree(p)
        p.mkdir(parents=True)
    extract_deb('dist/beta4.deb',PKG)
    lib=PKG/'Library/MobileSubstrate/DynamicLibraries/C18ConnectivityFive.dylib'; lib.parent.mkdir(parents=True,exist_ok=True); lib.write_bytes(Path('build/C18ConnectivityFive.dylib').read_bytes()); lib.chmod(0o755)
    plist=PKG/'Library/MobileSubstrate/DynamicLibraries/C18ConnectivityFive.plist'; plist.write_bytes(Path('C18ConnectivityFive.plist').read_bytes()); plist.chmod(0o644)
    control=PKG/'DEBIAN/control'; text=control.read_text()
    text=re.sub(r'^Version: .*$', 'Version: 3.0-beta4-five2', text, flags=re.M)
    text=re.sub(r'^Maintainer: .*$', 'Maintainer: Ning&evgeniy558', text, flags=re.M)
    text=re.sub(r'^Author: .*$', 'Author: Ning&evgeniy558', text, flags=re.M)
    text=re.sub(r'^Description: .*$', 'Description: ControlCenter18 beta4 with five-slot connectivity editor', text, count=1, flags=re.M)
    installed=sum(p.stat().st_size for p in PKG.rglob('*') if p.is_file())//1024
    text=re.sub(r'^Installed-Size: .*$', f'Installed-Size: {installed}', text, flags=re.M)
    control.write_text(text)
    (MEMBERS/'debian-binary').write_bytes(b'2.0\n'); write_tar_gz(MEMBERS/'control.tar.gz',PKG/'DEBIAN',False); write_tar_gz(MEMBERS/'data.tar.gz',PKG,True)
    pack(str(OUT),str(MEMBERS)); print(OUT,OUT.stat().st_size,hashlib.sha256(OUT.read_bytes()).hexdigest())
if __name__=='__main__': main()
