#!/usr/bin/env python3
"""Overlay reviewed beta10 files onto the user-selected, SHA256-pinned five4."""
import argparse,copy,gzip,hashlib,io,os,plistlib,tarfile,json,lzma
from slim import put_localization,optimize
from pathlib import Path
from mkdeb import pack
from promo_cleanup import cleanup,verify_cleanup,verify_signed_main,MAIN
from settings_cleanup import PREFS,remove_resources,verify_signed_prefs
from power_cleanup import remove_old_power
VERSION='3.0-beta6'
BUNDLE_VERSION=VERSION.rsplit('beta',1)[1]
BASE_SHA256='4c2f36e17adbfe6d78412e629d749ac331d5eaabd003b18286ee37a14a2979e2'
BASE=Path(os.environ.get('CC18_BASE_DEB','dist/baseline.deb'))
OUT=Path('dist/com.evgeniy558.controlcenter18_'+VERSION+'_iphoneos-arm64e.deb')
PREFIX='Library/MobileSubstrate/DynamicLibraries/'
SIM='Library/ControlCenter/Bundles/CCSIM.bundle/'
RECORDING_RESOURCES=json.loads((Path(__file__).resolve().parents[1]/'Resources/Recording/manifest.json').read_text())
EXPECTED_RESOURCES={
 'Resources/CCSIM.bundle/CCSIM.png':'f7d5e9c9d43b1317c12cc631f48f04e04d57648fd6cfb67bcaae7a1b6f4c7743',
 'Resources/CCSIM.bundle/CCSIM@2x.png':'d300cd5e9d59ea6cd408fb474ebce41142768738e70d22a16a0c88ebdded8d01',
 'Resources/CCSIM.bundle/CCSIM@3x.png':'a447eea7f4a11f424615b4435589d65d1bf0db75901b9aa277bbdba6f3c18e5c',
 'Resources/C18DataSwitchGlyph.png':'34c2b0e4a79fa6a1b1b53f0c7e534519c4ad80bbd4c689ac58e88423fbaa6440',
 'Resources/CCSwitchDataModule.bundle/CCSwitchData.png':'11d26dfba96e925ee01efcf50856d680fd68ce0cd8101552ba6c77b45b2b5487',
 'Resources/CCSwitchDataModule.bundle/CCSwitchData@2x.png':'8d132b780847d5103bae0786bd48a09edae5106336eebdec18892d268d1e0a79',
 'Resources/CCSwitchDataModule.bundle/CCSwitchData@3x.png':'42012697d6c88ac4d063f0391908e11724e076315d15898cb75eb642c0579a65'}
def deb_members(data):
    assert data[:8]==b'!<arch>\n';p=8;members={}
    while p<len(data):
        h=data[p:p+60];assert len(h)==60 and h[58:]==b'`\n';name=h[:16].decode().strip().rstrip('/');n=int(h[48:58]);p+=60
        assert name not in members;members[name]=data[p:p+n];assert len(members[name])==n;p+=n+n%2
    assert p==len(data) and members['debian-binary']==b'2.0\n';return members

def archive(data):
    entries={}
    with tarfile.open(fileobj=io.BytesIO(data),mode='r:*') as t:
        for member in t:
            rel=member.name.removeprefix('./')
            assert not rel.startswith('/') and '..' not in Path(rel).parts
            assert rel not in entries
            entries[rel]=(copy.copy(member),t.extractfile(member).read() if member.isfile() else None)
    return entries

def overlay(entries,name,data,mode=0o644):
    if name in entries:info=copy.copy(entries[name][0]);assert info.isfile(),name
    else:info=tarfile.TarInfo('./'+name);info.uid=info.gid=0;info.uname=info.gname='root';info.mtime=0
    info.mode=mode;info.size=len(data);entries[name]=(info,data)

def serialize(entries,compressed=True):
    buf=io.BytesIO()
    with tarfile.open(fileobj=buf,mode='w',format=tarfile.USTAR_FORMAT) as t:
        for info,data in entries.values():
            info=copy.copy(info);info.pax_headers={}
            t.addfile(info,io.BytesIO(data) if info.isfile() else None)
    return gzip.compress(buf.getvalue(),compresslevel=9,mtime=0) if compressed else buf.getvalue()

def compression_order(entries):
    # Only archive order changes: all directories precede file entries, and
    # similar resource names stay close in LZMA's dictionary. No new links.
    def key(name):
        info,content=entries[name]
        if info.isdir():return ('0',name.count('/'),name)
        if info.issym():kind='2link'
        elif content and content[:4] in (b'\xca\xfe\xba\xbe',b'\xbe\xba\xfe\xca',b'\xcf\xfa\xed\xfe',b'\xfe\xed\xfa\xcf'):kind='1Mach-O'
        else:kind='1'+(Path(name).suffix.lower() or '(none)')
        digest=hashlib.sha256(content).hexdigest() if content is not None else ''
        return (kind,Path(name).name,digest,name)
    assert not any(t.islnk() for t,_ in entries.values()),'No archive hardlink reorder without dependency analysis'
    return {name:entries[name] for name in sorted(entries,key=key)}

# Python stdlib liblzma on Linux/macOS; <=40 MiB decoder working memory.
# Keep a 32 MiB dictionary rather than the default 9e 64 MiB dictionary.
XZ_FILTERS=[{'id':lzma.FILTER_LZMA2,'preset':9|lzma.PRESET_EXTREME,'dict_size':32*1024*1024}]
def compress_data(raw):
    compressed=lzma.compress(raw,format=lzma.FORMAT_XZ,check=lzma.CHECK_CRC64,filters=XZ_FILTERS)
    assert lzma.decompress(compressed,memlimit=40*1024*1024)==raw
    return compressed

def main():
    parser=argparse.ArgumentParser(description='Original beta6 overlay with pinned offline promotion cleanup')
    parser.add_argument('--promo-dry-run',action='store_true',help='Clean and round-trip real baseline data.tar in memory; never write a deb')
    parser.add_argument('--promo-report',type=Path,help='Write the dry-run JSON evidence')
    args=parser.parse_args()
    source=BASE.read_bytes();assert hashlib.sha256(source).hexdigest()==BASE_SHA256,'wrong baseline deb'
    raw=deb_members(source);control=archive(next(v for k,v in raw.items() if k.startswith('control.tar')));data=archive(next(v for k,v in raw.items() if k.startswith('data.tar')))
    original=dict(data);promo=cleanup(data)
    if args.promo_dry_run:
        # Exercise the actual serializer without creating any archive on disk.
        roundtrip=archive(serialize(data));promo['tar_roundtrip']=verify_cleanup(original,roundtrip)
        promo['baseline_deb_sha256']=BASE_SHA256
        promo['control_unchanged']=True
        if args.promo_report:args.promo_report.write_text(json.dumps(promo,indent=2,ensure_ascii=False)+'\n')
        print(json.dumps(promo,indent=2,ensure_ascii=False));return
    power=remove_old_power(data)
    Path('build/power-cleanup-validation.json').write_text(json.dumps(power,indent=2)+'\n')
    signed=Path('build/ControlCenter18-clean.dylib').read_bytes()
    promo['signature_verification']=verify_signed_main(original[MAIN][1],signed)
    promo['packaging_blocked']=False
    Path('build/promo-validation.json').write_text(json.dumps(promo,ensure_ascii=False,indent=2)+'\n')
    overlay(data,MAIN,signed,original[MAIN][0].mode)
    settings=remove_resources(data)
    settings_signed=Path('build/ControlCenter18Prefs-clean').read_bytes()
    settings['signature_verification']=verify_signed_prefs(original[PREFS][1],settings_signed)
    overlay(data,PREFS,settings_signed,original[PREFS][0].mode)
    Path('build/settings-cleanup-validation.json').write_text(json.dumps(settings,indent=2)+'\n')
    replacement={PREFIX+'C18ConnectivityFive.dylib':(Path('build/C18ConnectivityFive.dylib').read_bytes(),0o755),PREFIX+'C18ConnectivityFive.plist':(Path('C18ConnectivityFive.plist').read_bytes(),0o644),SIM+'CCSIM':(Path('build/CCSIM').read_bytes(),0o755)}
    moduleInfo=plistlib.loads(data[SIM+'Info.plist'][1]);moduleInfo.update({'NSPrincipalClass':'CCSIM','CFBundleDisplayName':'蜂窝管理','CFBundleVersion':BUNDLE_VERSION,'CFBundleShortVersionString':VERSION,'MinimumOSVersion':'15.0'})
    replacement[SIM+'Info.plist']=(plistlib.dumps(moduleInfo,fmt=plistlib.FMT_BINARY),0o644)
    for name,digest in EXPECTED_RESOURCES.items():
        content=Path(name).read_bytes();assert hashlib.sha256(content).hexdigest()==digest,name
        target=(PREFIX+'C18DataSwitchGlyph.png' if name=='Resources/C18DataSwitchGlyph.png' else
                'Library/ControlCenter/Bundles/CCSwitchDataModule.bundle/'+Path(name).name if 'CCSwitchDataModule.bundle' in name else SIM+Path(name).name)
        replacement[target]=(content,0o644)
    for name,entry in RECORDING_RESOURCES.items():
        content=Path(name).read_bytes();assert hashlib.sha256(content).hexdigest()==entry['sha256'],name
        assert entry['target'] in data,entry['target']
        replacement[entry['target']]=(content,0o644)
    for name,(content,mode) in replacement.items():overlay(data,name,content,mode)
    put_localization(data,overlay)
    slim=optimize(data)
    Path('build/slim-validation.json').write_text(json.dumps(slim,indent=2)+'\n')
    text=control['control'][1].decode();lines=text.splitlines();fields={'Version':VERSION,'Maintainer':'Ning&evgeniy558','Author':'Ning&evgeniy558','Description':'ControlCenter18 beta6 with configurable connectivity and cellular controls','Installed-Size':str(sum(len(x[1]) for x in data.values() if x[1] is not None)//1024)}
    seen=set();out=[]
    for line in lines:
        key=line.split(':',1)[0] if line and not line[0].isspace() else None
        if key in fields:out.append(key+': '+fields[key]);seen.add(key)
        else:out.append(line)
    for key in fields.keys()-seen:out.append(key+': '+fields[key])
    overlay(control,'control',('\n'.join(out).rstrip()+'\n').encode())
    from description import apply_description
    apply_description(control,data)
    members=Path('dist/members');members.mkdir(parents=True,exist_ok=True)
    (members/'debian-binary').write_bytes(b'2.0\n');(members/'control.tar.gz').write_bytes(serialize(control));(members/'data.tar.xz').write_bytes(compress_data(serialize(compression_order(data),False)))
    pack(str(OUT),str(members));assert OUT.stat().st_size<3793436,'Package must be smaller than issued compact beta6';print(OUT,OUT.stat().st_size,hashlib.sha256(OUT.read_bytes()).hexdigest())
if __name__=='__main__':main()
