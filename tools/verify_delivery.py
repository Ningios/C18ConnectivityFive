#!/usr/bin/env python3
"""Verify final deb bytes, primary Mach-O architectures and macOS signatures."""
import hashlib,json,platform,struct,subprocess,tempfile
from pathlib import Path
from package import ROOT,VERSION,BASELINES,deb_members,archive


def verify():
    assert platform.system()=='Darwin', 'Run final codesign verification on macOS'
    reports=[]
    with tempfile.TemporaryDirectory(prefix='c18-final-signatures-') as temporary:
        for arch,prefix,_ in BASELINES:
            path=ROOT/'dist'/f'com.evgeniy558.controlcenter18_{VERSION}_iphoneos-{arch}.deb'
            raw=path.read_bytes();members=deb_members(raw)
            data=archive(next(v for k,v in members.items() if k.startswith('data.tar')))
            control=archive(next(v for k,v in members.items() if k.startswith('control.tar')))
            metadata=control['control'][1]
            assert f'Architecture: iphoneos-{arch}'.encode() in metadata
            assert f'Version: {VERSION}'.encode() in metadata
            folder=prefix+'Library/MobileSubstrate/DynamicLibraries/'
            assert not any(folder+n in data for n in ('C18PowerMenu.dylib','C18PowerMenu.plist','C18PowerMenu.dylib.roothidepatch'))
            names=[folder+n for n in ('ControlCenter18.dylib','ControlCenter18Modules.dylib','C18ConnectivityFive.dylib')]
            names.append(prefix+'Library/PreferenceBundles/ControlCenter18Prefs.bundle/ControlCenter18Prefs')
            programs=[]
            for index,name in enumerate(names):
                content=data[name][1];assert struct.unpack_from('>II',content)==(0xcafebabe,2), name
                subtypes=[]
                for i in range(2):
                    cpu,sub,offset,size,align=struct.unpack_from('>5I',content,8+i*20)
                    assert cpu==0x100000c and sub in (0,0x80000002) and offset+size<=len(content)
                    assert struct.unpack_from('<3I',content,offset)==(0xfeedfacf,cpu,sub)
                    subtypes.append(sub)
                assert set(subtypes)=={0,0x80000002}, name
                out=Path(temporary)/f'{arch}-{index}.dylib';out.write_bytes(content)
                subprocess.run(['codesign','--verify','--strict','--all-architectures','--verbose=2',str(out)],check=True)
                programs.append({'name':name,'sha256':hashlib.sha256(content).hexdigest(),'subtypes':[hex(n) for n in subtypes],'codesign_strict_all_architectures':True})
            report={'file':path.name,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),'arch':arch,'programs':programs,'device_tested':False}
            reports.append(report)
            print('FINAL_PACKAGE_VERIFIED',json.dumps(report),flush=True)
    (ROOT/'build/package-validation.json').write_text(json.dumps(reports,indent=2)+'\n')

if __name__=='__main__':verify()
