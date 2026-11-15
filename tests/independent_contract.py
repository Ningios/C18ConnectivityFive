from pathlib import Path
import plistlib
r=Path(__file__).resolve().parents[1]
read=lambda n:(r/n).read_text()
shape=read('C18ConnectivityShape.h')
assert 'com.ning.c18connectivityfive' in shape
assert 'com.apple.control-center.ConnectivityModule' not in shape.split('static inline BOOL C18ShapeIdentifier')[1].split('static inline NSString *C18ShapeGridClass')[0]
assert 'com.evgeniy558.controlcenter18.connectivity2' not in shape.split('static inline BOOL C18ShapeIdentifier')[1].split('static inline NSString *C18ShapeGridClass')[0]
tweak=read('Tweak.m')
assert 'module && C18IsIndependentFiveModule(module) &&' in tweak
assert 'C18IsIndependentFiveModule(self)) size=C18CurrentNativeShapeSize(size)' in tweak
assert 'if (C18ShapeIdentifier(identifier)) return YES;' in tweak
editor=read('C18FiveEditor.m')
assert 'return _mode==0 ? 1 : 2;' in editor
assert 'return section==0 ? 1 : (_mode==4 ? 4 : 5);' in editor
entry=editor.split('static BOOL C18FiveEditorEntryIdentifier(id value) {',1)[1].split('static void C18FiveDragPressHook',1)[0]
assert 'com.apple.control-center.ConnectivityModule' in entry
assert 'com.evgeniy558.controlcenter18.connectivity2' in entry
assert 'C18ShapeIdentifier(value)' in entry
assert 'BOOL target=C18FiveEditorEntryIdentifier(C18FiveObject(module,NSSelectorFromString(@"identifier")))' in editor
assert 'C18FiveEditorEntryIdentifier' not in tweak
state=read('C18NativeLayoutRestore.m')
assert 'C18NativeEnsureIndependentModule' not in state
assert 'if (C18ShapeIdentifier(entry[@"id"]))' in state
reload=state.split('void C18NativeLayoutRestoreRequestReload(void) {',1)[1].split('BOOL C18NativeLayoutRestoreHasPendingReload',1)[0]
assert 'reloadFromDisk' not in reload
assert 'changeGridSizeClassForIdentifier:toGridSizeClass:' in reload
assert 'C18FiveNativeModuleIdentifier(),grid' in reload
info=plistlib.loads((r/'ConnectivityFiveModule.bundle/Info.plist').read_bytes())
assert info['CFBundleIdentifier']=='com.ning.c18connectivityfive'
assert info['NSPrincipalClass']=='C18ConnectivityFiveModule'
assert info['CFBundleExecutable']=='ConnectivityFiveModule'
assert 'CCUIConnectivityModule' in read('C18ConnectivityFiveModule.m')
assert 'ConnectivityFiveModule.bundle/ConnectivityFiveModule' in read('tools/package.py')
assert 'ConnectivityFiveModule.bundle/ConnectivityFiveModule' in read('tools/verify.py')
assert 'workflow_dispatch:' in read('.github/workflows/build.yml')
print('IDENTITY_AND_ORIGINAL_LAYOUT_CONTRACT_OK')
