#!/usr/bin/env python3
"""Verify strict signatures on the final DEB payload, never execute target code."""
from pathlib import Path
import hashlib,json,plistlib,subprocess,sys,tempfile
from package import deb_members,archive,PREFIX,SIM,VERSION,BUNDLE_VERSION
from settings_cleanup import PREFS
p=Path(sys.argv[1]);members=deb_members(p.read_bytes());data=archive(members['data.tar.xz'])
info=plistlib.loads(data[SIM+'Info.plist'][1]);assert info['CFBundleShortVersionString']==VERSION and info['CFBundleVersion']==BUNDLE_VERSION
checks=[]
with tempfile.TemporaryDirectory(prefix='cc18-final-codesign-') as d:
 for name in (PREFIX+'ControlCenter18.dylib',PREFIX+'C18ConnectivityFive.dylib',SIM+'CCSIM',PREFS):
  b=data[name][1];out=Path(d)/Path(name).name;out.write_bytes(b)
  subprocess.run(['xcrun','codesign','--verify','--strict','--all-architectures',str(out)],check=True)
  checks.append({'path':name,'sha256':hashlib.sha256(b).hexdigest(),'strict_all_architectures':True})
report={'version':VERSION,'sim_internal_build':BUNDLE_VERSION,'package_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'checks':checks,'runtime_verified':False}
p.with_suffix('.codesign.json').write_text(json.dumps(report,indent=2)+'\n');print('FINAL_DEB_MACOS_CODESIGN_OK',json.dumps(report),flush=True)
