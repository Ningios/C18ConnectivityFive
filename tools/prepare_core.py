#!/usr/bin/env python3
"""Renew the pinned core's ad-hoc requirements without changing section bytes."""
import hashlib,json,platform,struct,subprocess
from package import ROOT,BASELINES,archive,deb_members
from prefs_cleanup import slices


def sections(blob):
    result={}
    for sub,offset,size in slices(blob):
        image=blob[offset:offset+size];position=32
        for _ in range(struct.unpack_from('<I',image,16)[0]):
            cmd,length=struct.unpack_from('<II',image,position)
            if cmd==0x19:
                count=struct.unpack_from('<I',image,position+64)[0]
                for index in range(count):
                    sec=position+72+index*80
                    name=image[sec:sec+16].rstrip(b'\0');segment=image[sec+16:sec+32].rstrip(b'\0')
                    address,nbytes,fileoff=struct.unpack_from('<QQI',image,sec+32)
                    flags=struct.unpack_from('<I',image,sec+64)[0]
                    key=(sub,segment.decode(),name.decode())
                    assert key not in result
                    zerofill=(flags&0xff) in (1,12,18)
                    assert zerofill or fileoff+nbytes<=len(image)
                    result[key]=(address,nbytes,flags,None if zerofill else hashlib.sha256(image[fileoff:fileoff+nbytes]).hexdigest())
            position+=length
    return result


def prepare():
    assert platform.system()=='Darwin'
    build=ROOT/'build';build.mkdir(exist_ok=True);reports=[]
    for arch,prefix,digest in BASELINES:
        raw=(ROOT/f'Vendor/baseline-{arch}.deb').read_bytes();assert hashlib.sha256(raw).hexdigest()==digest
        members=deb_members(raw);data=archive(next(v for k,v in members.items() if k.startswith('data.tar')))
        for stem in ('ControlCenter18','ControlCenter18Modules'):
            name=prefix+f'Library/MobileSubstrate/DynamicLibraries/{stem}.dylib'
            original=data[name][1];before=sections(original)
            out=build/f'Core-{arch}-{stem}.dylib';out.write_bytes(original)
            # Preserve runtime entitlements/flags and identity; regenerate requirements.
            subprocess.run(['codesign','--force','--sign','-','--timestamp=none','--preserve-metadata=identifier,entitlements,flags',str(out)],check=True)
            subprocess.run(['codesign','--verify','--strict','--all-architectures','--verbose=2',str(out)],check=True)
            signed=out.read_bytes();assert sections(signed)==before,'Signing changed runtime section data'
            assert {sub for sub,_,_ in slices(signed)}=={0,0x80000002}
            reports.append({'arch':arch,'stem':stem,'name':name,'file':out.name,'original_sha256':hashlib.sha256(original).hexdigest(),'signed_sha256':hashlib.sha256(signed).hexdigest(),'runtime_sections_unchanged':True,'section_count':len(before),'macos_codesign_strict_all_architectures':True})
    (build/'core-signing.json').write_text(json.dumps(reports,indent=2)+'\n')
    print('CORE_REQUIREMENTS_RENEWED_RUNTIME_SECTIONS_UNCHANGED',json.dumps(reports),flush=True)

if __name__=='__main__':prepare()
