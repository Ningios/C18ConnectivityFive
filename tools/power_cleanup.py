"""Remove obsolete power UIAlert provider, including its delayed swizzle."""
import hashlib
PREFIX='Library/MobileSubstrate/DynamicLibraries/'
OLD_POWER_FILES={PREFIX+'C18PowerMenu.dylib',PREFIX+'C18PowerMenu.plist',PREFIX+'C18PowerMenu.dylib.roothidepatch'}
PINS={PREFIX+'C18PowerMenu.dylib':'5490c2a7ea6ebe4e4d0c2f568dccae4a609f69d9a9f0d9805e70c2749be6699b',PREFIX+'C18PowerMenu.plist':'29bbe36650150dbedd2f466bb84abefadfb54eb0a5bddd1e6814d40c607618f8'}
def remove_old_power(entries):
    assert OLD_POWER_FILES<=set(entries),'Missing original power provider entries'
    for name,digest in PINS.items():
        info,data=entries[name]
        assert info.isfile() and hashlib.sha256(data).hexdigest()==digest,('POWER_BASELINE_MISMATCH',name)
    marker=entries[PREFIX+'C18PowerMenu.dylib.roothidepatch'][0]
    assert marker.issym() and marker.linkname=='/usr/lib/DynamicPatches/AutoPatches.dylib'
    removed=[]
    for name in sorted(OLD_POWER_FILES):
        info,data=entries.pop(name);removed.append({'path':name,'bytes':len(data or b''),'type':info.type.decode()})
    assert not any('C18PowerMenu' in name for name in entries)
    return {'old_provider_removed':True,'removed':removed,'direct_backend':True,'runtime_verified':False}
