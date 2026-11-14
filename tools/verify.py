#!/usr/bin/env python3
import gzip,hashlib,json,plistlib,struct,sys,lzma
from slim import LOCALIZATION,put_localization,optimize,resolved,verify_png_equivalent
from pathlib import Path
from promo_cleanup import MAIN,removable,verify_signed_main,TOKENS
from package import BASE,BASE_SHA256,VERSION,BUNDLE_VERSION,PREFIX,SIM,EXPECTED_RESOURCES,RECORDING_RESOURCES,deb_members,archive
from integrity import checked_slices,signature_check,fields as control_fields,entry_meta
from settings_cleanup import PREFS,screenshot,verify_signed_prefs

def verify(path):
    raw=path.read_bytes();members=deb_members(raw)
    assert set(members)=={'debian-binary','control.tar.gz','data.tar.xz'}
    for name in ('control.tar.gz','data.tar.xz'):
        data=(gzip.decompress(members[name]) if name.endswith('.gz') else lzma.decompress(members[name],memlimit=40*1024*1024));off=0
        while data[off:off+512]!=bytes(512):
            header=data[off:off+512];assert len(header)==512 and header[257:263]==b'ustar\0' and header[156:157] not in (b'x',b'g',b'L',b'K')
            size=int(header[124:136].rstrip(b'\0 ') or b'0',8);off+=512+((size+511)//512)*512
    assert hashlib.sha256(BASE.read_bytes()).hexdigest()==BASE_SHA256
    baseline=deb_members(BASE.read_bytes())
    old=archive(next(v for k,v in baseline.items() if k.startswith('data.tar')))
    new=archive(members['data.tar.xz']);control=archive(members['control.tar.gz'])
    assert len(raw)<3793436,'Package size exceeds issued compact beta6'
    assert new['usr/local/bin/CCSIMTool'][1]==old['usr/local/bin/CCSIMTool'][1]
    original_control=archive(next(v for k,v in baseline.items() if k.startswith('control.tar')))
    assert set(control)==set(original_control)=={'.','control'}
    original_fields=control_fields(original_control['control'][1]);actual_fields=control_fields(control['control'][1])
    assert set(original_fields)==set(actual_fields)
    permitted={'Version':VERSION,'Author':'Ning&evgeniy558','Maintainer':'Ning&evgeniy558','Installed-Size':str(sum(len(e[1]) for e in new.values() if e[1] is not None)//1024)}
    for key,value in original_fields.items():
        if key=='Description':assert actual_fields[key]=='ControlCenter18 beta6 with configurable connectivity and cellular controls'+value[value.index('\n'):]
        else:assert actual_fields[key]==permitted.get(key,value),key
    for name in control:assert entry_meta(control[name],False)==entry_meta(original_control[name],False),name
    text=control['control'][1].decode();assert text.endswith('\n')
    fields=dict(line.split(': ',1) for line in text.splitlines() if ': ' in line and not line[0].isspace())
    assert fields['Version']==VERSION and fields['Architecture']=='iphoneos-arm64e'
    assert fields['Maintainer']==fields['Author']=='Ning&evgeniy558'
    allowed={SIM+'CCSIM',SIM+'Info.plist',PREFIX+'C18ConnectivityFive.dylib',PREFIX+'C18ConnectivityFive.plist',PREFIX+'C18DataSwitchGlyph.png'}|{SIM+Path(n).name for n in EXPECTED_RESOURCES if 'CCSIM.bundle' in n}|{'Library/ControlCenter/Bundles/CCSwitchDataModule.bundle/'+Path(n).name for n in EXPECTED_RESOURCES if 'CCSwitchDataModule.bundle' in n}
    allowed|={entry['target'] for entry in RECORDING_RESOURCES.values()}|{PREFS}
    def record(entry):
        info,data=entry
        return (info.type,info.mode,info.uid,info.gid,info.linkname,data)
    removed={name for name in old if removable(name)}
    drafts={n for n in old if n.endswith(('.ai','.eps')) and '/Packages/' in n}
    for n in drafts:
        needle=Path(n).name.encode();assert not any(needle in b for k,(i,b) in old.items() if b and k!=n and not k.endswith(('.ai','.eps')))
    localization_targets={e['target'] for e in LOCALIZATION}
    expected_static=dict(old)
    static_report=optimize(expected_static)
    png_changes=static_report['png_recompressed']
    jpeg_changes=static_report['jpeg_optimized']
    unused=set(static_report['removed_unused_assets'])
    assert len(unused)==8 and static_report['removed_unused_bytes']==337584
    assert not (unused&(allowed|localization_targets|removed|drafts)), 'Unused asset scope overlaps runtime'
    assert not (set(png_changes)&(allowed|localization_targets|removed|drafts)), 'PNG scope overlaps runtime overlays'
    directory_targets={p for n in localization_targets for p in ['/'.join(n.split('/')[:i]) for i in range(1,len(n.split('/')))] if p not in old}
    shots={n for n in old if screenshot(n)}
    assert len(shots)==15 and sum(len(old[n][1] or b'') for n in shots)==1663235
    assert set(old)-set(new)==removed|drafts|shots|unused and len(removed)==31 and len(drafts)==14
    assert not any(screenshot(n) for n in new)
    settings_signature=verify_signed_prefs(old[PREFS][1],new[PREFS][1])
    assert set(new)-set(old)<=allowed|localization_targets|directory_targets
    for e in LOCALIZATION:
        digest=e.get('sha256',e.get('resolved_sha256'));assert hashlib.sha256(resolved(new,e['target'])).hexdigest()==digest,e['target']
    for n in directory_targets:
        i,b=new[n];assert i.isdir() and i.mode==0o755 and i.uid==i.gid==0,n
    assert not any(removable(name) for name in new)
    main_signature=verify_signed_main(old[MAIN][1],new[MAIN][1])
    for name in old:
        if name in removed|drafts|shots|unused or name==MAIN:continue
        assert name in new,'Baseline entry removed: '+name
        if name not in allowed|localization_targets:
            oi,ob=old[name];ni,nb=new[name]
            if name in png_changes:
                assert oi.isfile() and ni.isfile() and entry_meta(old[name],False)==entry_meta(new[name],False),name
                verify_png_equivalent(ob,nb)
                assert ni.size==len(nb) and nb==expected_static[name][1], 'Unexpected optimized PNG: '+name
            elif name in jpeg_changes:
                assert oi.isfile() and ni.isfile() and entry_meta(old[name],False)==entry_meta(new[name],False),name
                assert ni.size==len(nb) and nb==expected_static[name][1] and hashlib.sha256(nb).hexdigest()==jpeg_changes[name]['after_sha256'],name
            else:assert record(old[name])==record(new[name]),'Baseline entry changed: '+name
    executables={MAIN,SIM+'CCSIM',PREFIX+'C18ConnectivityFive.dylib',PREFS}
    for name in allowed|{MAIN}:
        if name not in new:continue
        info,content=new[name];expected_mode=0o755 if name in executables else 0o644
        assert info.isfile() and info.mode==expected_mode and info.uid==info.gid==0 and info.uname==info.gname=='root',name
        assert info.size==len(content) and info.linkname=='',name
        if name in old:
            meta=list(entry_meta(old[name],False));meta[1]=expected_mode
            assert entry_meta(new[name],False)==tuple(meta),name
    for name,(_,content) in new.items():
        if content is not None:assert not any(token.encode() in content for token in TOKENS),name
    assert new[PREFIX+'C18ConnectivityFive.plist'][1]==Path('C18ConnectivityFive.plist').read_bytes()
    assert plistlib.loads(new[PREFIX+'C18ConnectivityFive.plist'][1])=={'Filter':{'Bundles':['com.apple.springboard']}}
    for resource,digest in EXPECTED_RESOURCES.items():
        target=(PREFIX+'C18DataSwitchGlyph.png' if resource=='Resources/C18DataSwitchGlyph.png' else
                'Library/ControlCenter/Bundles/CCSwitchDataModule.bundle/'+Path(resource).name if 'CCSwitchDataModule.bundle' in resource else SIM+Path(resource).name)
        assert hashlib.sha256(resolved(new,target)).hexdigest()==digest
    for entry in RECORDING_RESOURCES.values():assert hashlib.sha256(resolved(new,entry['target'])).hexdigest()==entry['sha256']
    sim=new[SIM+'CCSIM'][1]
    assert sim==Path('build/CCSIM').read_bytes() and sim!=old[SIM+'CCSIM'][1]
    simInfo=plistlib.loads(new[SIM+'Info.plist'][1])
    assert simInfo['CFBundleIdentifier']=='netskao.ccsim' and simInfo['NSPrincipalClass']=='CCSIM'
    assert simInfo['CFBundleShortVersionString']==VERSION and simInfo['CFBundleVersion']==BUNDLE_VERSION
    strict_integrity={}
    for label,name in [('main',MAIN),('companion',PREFIX+'C18ConnectivityFive.dylib'),('ccsim',SIM+'CCSIM')]:
        strict_integrity[label]={hex(sub):signature_check(slice_data) for sub,slice_data in checked_slices(new[name][1]).items()}
    assert new['usr/local/bin/CCSIMTool'][1]==old['usr/local/bin/CCSIMTool'][1]
    banned=('UIAlertController','UIAlertAction','UIAlertView','UIActionSheet','presentViewController:animated:completion:','onSelected','setSelected:')
    for name in banned:assert name.encode() not in sim,'Old SIM presentation entry retained: '+name
    assert b'requestExpandModule' not in sim,'Compact controller must never expand/reparent itself'
    for name in ('C18SIMController','C18SIMPanelController','C18SIMService','posix_spawn','CCSIMTool','c18PerformLongPress','dismissMenu','presentMenuViewController:fromModuleView:'):
        assert name.encode() in sim,'Missing new SIM entry: '+name
    assert struct.unpack_from('>II',sim)==(0xcafebabe,2)
    for i in range(2):
        cpu,sub,offset,size,align=struct.unpack_from('>IIIII',sim,8+i*20)
        assert sub in (0,0x80000002) and len(sim[offset:offset+size])==size
    lib=new[PREFIX+'C18ConnectivityFive.dylib'][1];assert struct.unpack_from('>II',lib)==(0xcafebabe,2)
    assert b'C18FiveColumnInstall' not in lib and b'C18FiveColumnApply' not in lib
    slices=[]
    for i in range(2):
        cpu,sub,offset,size,align=struct.unpack_from('>IIIII',lib,8+i*20);b=lib[offset:offset+size]
        magic,icpu,isub,typ,ncmds,cmdsize,flags,res=struct.unpack_from('<8I',b)
        assert magic==0xfeedfacf and cpu==icpu==0x100000c and sub==isub and typ==6
        pos=32;signature=False;formats=[]
        for j in range(ncmds):
            cmd,cs=struct.unpack_from('<II',b,pos);assert cs>=8 and pos+cs<=32+cmdsize
            if cmd==0x1d:
                do,ds=struct.unpack_from('<II',b,pos+8);assert do+ds<=size and struct.unpack_from('>I',b,do)[0]==0xfade0cc0;signature=True
            if cmd==0x80000034:
                do,ds=struct.unpack_from('<II',b,pos+8);fix=b[do:do+ds];start=struct.unpack_from('<I',fix,4)[0];nseg=struct.unpack_from('<I',fix,start)[0]
                for k in range(nseg):
                    so=struct.unpack_from('<I',fix,start+4+k*4)[0]
                    if so:formats.append(struct.unpack_from('<H',fix,start+so+6)[0])
            pos+=cs
        assert signature
        if sub==0x80000002:assert formats and all(f in (1,7,9,10,12) for f in formats)
        else:assert sub==0
        slices.append({'subtype':hex(sub),'signature':signature,'fixups':formats})
    assert {s['subtype'] for s in slices}=={'0x0','0x80000002'}
    report={'version':VERSION,'sha256':hashlib.sha256(raw).hexdigest(),'size':len(raw),'baseline_sha256':BASE_SHA256,'baseline_data_entries':len(old),'preserved_original_entries':sum(name in new and record(old[name])==record(new[name]) for name in old),'retained_original_entries':len(set(old)&set(new)),'strict_integrity':strict_integrity,'sim_internal_build':simInfo['CFBundleVersion'],'dylib_sha256':hashlib.sha256(lib).hexdigest(),'sim_module_sha256':hashlib.sha256(sim).hexdigest(),'old_sim_presentation_removed':True,'main_five_column_feature_removed':True,'slices':slices,'runtime_verified':False,'promotion_removed_entries':len(removed),'unused_design_sources_removed':len(drafts),'localization_resources':len(LOCALIZATION),'compression':'xz-lzma2; decoder<=40MiB','jpeg_lossless_resources':len(jpeg_changes),'jpeg_uncompressed_saved_bytes':static_report['jpeg_uncompressed_saved_bytes'],'png_recompressed_resources':len(png_changes),'png_uncompressed_saved_bytes':static_report['png_uncompressed_saved_bytes'],'smaller_than_issued_compact_beta6':True,'main_library_signature':main_signature,'settings_carousel_removed':True,'settings_screenshot_files_removed':14,'settings_screenshot_bytes_removed':1663235,'settings_signature':settings_signature}
    path.with_suffix('.verification.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));return report
if __name__=='__main__':verify(Path(sys.argv[1]))
