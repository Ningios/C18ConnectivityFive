#!/usr/bin/env python3
"""Verify final deb bytes, primary Mach-O architectures and macOS signatures."""
import hashlib,json,platform,plistlib,struct,subprocess,tempfile
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
            companion=data[folder+'C18ConnectivityFive.dylib'][1]
            # DataSwitch still uses UIKit alerts; check only deleted power classes.
            assert b'C18PowerRequest' not in companion and b'C18PowerPresenterHook' not in companion
            assert b'C18PowerSafe' not in companion and b'.C18SafeMode' not in companion
            assert '安全模式'.encode('utf-16le') not in companion
            names=[folder+n for n in ('ControlCenter18.dylib','ControlCenter18Modules.dylib','C18ConnectivityFive.dylib')]
            names.append(prefix+'Library/PreferenceBundles/ControlCenter18Prefs.bundle/ControlCenter18Prefs')
            helper=prefix+'usr/libexec/C18PowerHelper'
            helper_info,helper_content=data[helper]
            assert helper_info.isfile() and helper_info.mode==0o4755 and helper_info.uid==helper_info.gid==0
            names.append(helper)
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
                if name==helper:
                    entitlements=subprocess.run(['codesign','-d','--entitlements',':-',str(out)],check=True,capture_output=True).stdout
                    actual=plistlib.loads(entitlements)
                    expected=plistlib.loads((ROOT/'Resources/C18PowerHelper.entitlements').read_bytes())
                    assert all(actual.get(k)==v for k,v in expected.items()), 'Missing power helper entitlement'
                programs.append({'name':name,'sha256':hashlib.sha256(content).hexdigest(),'subtypes':[hex(n) for n in subtypes],'codesign_strict_all_architectures':True})
            report={'file':path.name,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),'arch':arch,'programs':programs,'device_tested':False}
            reports.append(report)
            print('FINAL_PACKAGE_VERIFIED',json.dumps(report),flush=True)
    (ROOT/'build/package-validation.json').write_text(json.dumps(reports,indent=2)+'\n')

if __name__=='__main__':verify()
