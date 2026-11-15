#!/usr/bin/env python3
"""Power-only regression checks; never run any device action."""
from pathlib import Path
import hashlib, plistlib, runpy
ROOT=Path(__file__).resolve().parents[1]
menu=(ROOT/'C18PowerMenu.m').read_text()
backend=(ROOT/'C18PowerBackend.h').read_text()
helper=(ROOT/'C18PowerHelper.c').read_text()
entitlements=plistlib.loads((ROOT/'Resources/C18PowerHelper.entitlements').read_bytes())
for token in ('UIAlertController','UIAlertAction','C18PowerPresent','C18PowerRequest','C18PowerSafe','C18SafeMode','安全模式','gC18PowerOriginal(self','presentViewController:','C18PowerSpawn','C18PowerExecute'):
    assert token not in menu,token
for token in ('SafeMode','PowerMark','SafeMarker','C18SafeMode','安全模式','C18PowerSpawn','C18PowerExecute','launchctl','ldrestart'):
    assert token not in backend,token
assert 'NSArray<NSString *> *titles=@[@"关机",@"注销",@"重启系统",@"重启用户空间"];' in menu
assert 'arrayWithCapacity:4' in menu
assert 'C18PowerReboot' in backend and 'C18PowerUserspace' in backend
assert 'FBSystemService' in menu and 'shutdownAndReboot:' in menu
assert 'kill(getpid(),SIGKILL)' in menu
assert 'C18PowerHelperPath' in menu and 'jbroot' in menu
assert 'if (selection.consumed) return;' in menu
assert 'if (NSThread.isMainThread) perform();else dispatch_async(dispatch_get_main_queue(),perform);' in menu
assert 'reboot3(C18_USERSPACE_REBOOT)' in helper
assert 'getuid() != 0 || geteuid() != 0' in helper
assert entitlements['com.apple.private.xpc.launchd.userspace-reboot'] is True
package=(ROOT/'tools/package.py').read_text()
assert 'install_power_helper' in package and '0o4755' in package
assert 'for name in old_power:\n            del data[name]' in package
assert '.roothidepatch' in package
runpy.run_path(str(ROOT/'tools/test_power_paths.py'),run_name='__main__')
print('POWER_ROOT_SOURCE_OK: native shutdown/reboot, direct respring, checked userspace helper; old popup and command table absent')
