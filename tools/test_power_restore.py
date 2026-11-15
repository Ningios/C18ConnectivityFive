#!/usr/bin/env python3
"""Validate the original backend and bridge without invoking power actions."""
import hashlib
from pathlib import Path
from package import ROOT,BASELINES,archive,deb_members

bridge=(ROOT/'C18PowerMenu.m').read_bytes()
assert hashlib.sha256(bridge).hexdigest()=='377c45bacc976dff883fda926a4dd218930cfca78219073c5e09635e71aa2005', 'Historical bridge changed'
text=bridge.decode()
for marker in ('gC18PowerOriginal(self,cmd)', 'C18PowerItems(alert,request)', 'handler(original)', 'C18PowerInstallFactories()', 'C18PowerInstallPresenter(top)', 'C18PowerRequestLive(request)', 'C18PowerMenu.dylib'):
    assert marker in text,marker
for forbidden in ('C18PowerSpawn(', 'C18PowerExecute(', 'C18PowerPaths.h'):
    assert forbidden not in text,forbidden
for arch,prefix,digest in BASELINES:
    raw=(ROOT/f'Vendor/baseline-{arch}.deb').read_bytes()
    assert hashlib.sha256(raw).hexdigest()==digest
    contents=archive(next(v for k,v in deb_members(raw).items() if k.startswith('data.tar')))
    folder=prefix+'Library/MobileSubstrate/DynamicLibraries/'
    assert hashlib.sha256(contents[folder+'C18PowerMenu.dylib'][1]).hexdigest()=='5490c2a7ea6ebe4e4d0c2f568dccae4a609f69d9a9f0d9805e70c2749be6699b'
    assert hashlib.sha256(contents[folder+'C18PowerMenu.plist'][1]).hexdigest()=='29bbe36650150dbedd2f466bb84abefadfb54eb0a5bddd1e6814d40c607618f8'
    marker=folder+'C18PowerMenu.dylib.roothidepatch'
    if arch=='arm64e':
        assert contents[marker][0].issym() and contents[marker][0].linkname=='/usr/lib/DynamicPatches/AutoPatches.dylib'
    else:assert marker not in contents
    print('POWER_ORIGINAL_PROVIDER_OK',arch,flush=True)
assert (ROOT/'Tweak.m').read_text().count('C18PowerMenuInstall();')>=2
print('POWER_ORIGINAL_BRIDGE_OK; no power command executed',flush=True)
