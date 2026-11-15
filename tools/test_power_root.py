#!/usr/bin/env python3
"""Power-only regression checks; never run any device action."""
from pathlib import Path
import runpy
ROOT=Path(__file__).resolve().parents[1]
menu=(ROOT/'C18PowerMenu.m').read_text()
backend=(ROOT/'C18PowerBackend.h').read_text()
for token in ('UIAlertController','UIAlertAction','C18PowerPresent','C18PowerRequest','C18PowerSafe','C18SafeMode','安全模式','gC18PowerOriginal(self','presentViewController:'):
    assert token not in menu,token
for token in ('SafeMode','PowerMark','SafeMarker','C18SafeMode','安全模式'):
    assert token not in backend,token
assert 'NSArray<NSString *> *titles=@[@"关机",@"注销",@"重启系统",@"重启用户空间"];' in menu
assert 'arrayWithCapacity:4' in menu
assert 'operation>C18PowerUserspace' in backend
assert 'dladdr((const void *)&kC18PowerMenu' in menu
assert 'gC18PowerHooked=YES;' in menu and 'if (gC18PowerHooked) return;' in menu
selection=menu.split('handler:^(__kindof UIAction *action){',1)[1].split('}];',1)[0]
assert 'C18FiveIsPresented' not in selection and 'source.window' not in selection
assert 'if (selection.consumed || !NSThread.isMainThread) return;' in selection
package=(ROOT/'tools/package.py').read_text()
assert 'for name in old_power:\n            del data[name]' in package
assert 'original.keys() - slim_removed - old_power' in package
assert '.roothidepatch' in package
runpy.run_path(str(ROOT/'tools/test_power_paths.py'),run_name='__main__')
print('POWER_ROOT_SOURCE_OK: four actions; old popup, original call and removed action absent')
