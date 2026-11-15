#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>
#import <notify.h>

FOUNDATION_EXPORT NSString * const C18FiveDomain;
FOUNDATION_EXPORT const char * const C18FiveReload;
FOUNDATION_EXPORT NSString *C18FiveBuiltinID(NSInteger item);
FOUNDATION_EXPORT NSInteger C18FiveBuiltinIndex(NSString *identifier);
FOUNDATION_EXPORT NSString *C18FiveModuleID(NSString *identifier);
FOUNDATION_EXPORT NSArray<NSString *> *C18FiveDefaultSlots(void);
FOUNDATION_EXPORT BOOL C18FiveRead(NSInteger *mode, NSArray<NSString *> **slots);
FOUNDATION_EXPORT BOOL C18FiveWrite(NSInteger mode, NSArray<NSString *> *slots);
FOUNDATION_EXPORT BOOL C18FiveExcluded(NSString *identifier, NSString *principal);
FOUNDATION_EXPORT NSArray<NSDictionary *> *C18FiveCatalog(void);
FOUNDATION_EXPORT NSDictionary *C18FiveEntry(NSString *slotID);
FOUNDATION_EXPORT id C18FiveGet(id object, NSString *key);
FOUNDATION_EXPORT id C18FiveObject(id object, SEL selector);
FOUNDATION_EXPORT BOOL C18FiveBool(id object, SEL selector);
FOUNDATION_EXPORT void C18FiveVoid(id object, SEL selector);
FOUNDATION_EXPORT void C18FiveSetInteger(id object, SEL selector, NSInteger value);
FOUNDATION_EXPORT void C18FiveInstallEditor(void);
FOUNDATION_EXPORT void C18FiveInstallModuleHooks(void);
FOUNDATION_EXPORT void C18FiveModulesSetPresented(BOOL presented);
// Only a real Shell presentation supplies this weak, non-creating reference.
FOUNDATION_EXPORT BOOL C18FiveIsPresented(void);
// True only inside a real Shell animation/presentation callback, never startup.
FOUNDATION_EXPORT BOOL C18FiveIsPreparing(void);
// Actual visible content for an independent five-key surface.
FOUNDATION_EXPORT UIView *C18FiveDisplayView(UIView *backend);
FOUNDATION_EXPORT id C18FiveLiveShell(void);
FOUNDATION_EXPORT NSUInteger C18FivePresentationGeneration(void);
FOUNDATION_EXPORT void C18DataSwitchActivate(void);
FOUNDATION_EXPORT UIView *C18FiveNativeMaterial(NSString *recipe);
FOUNDATION_EXPORT void C18FiveResolveCarrierNames(id client, void (^completion)(NSDictionary<NSNumber *,NSString *> *names));

// A real native C18ButtonModuleView owns its own module, controller, state and targets.
@interface C18FiveModuleHost : UIView
@property(nonatomic,copy,readonly) NSString *slotID;
@property(nonatomic,copy,readonly) NSString *failure;
@property(nonatomic,strong,readonly) UIView *nativeHost;
@property(nonatomic,weak) UIView *owner;
- (instancetype)initWithSlotID:(NSString *)slotID owner:(UIView *)owner;
- (void)refresh;
- (void)openNativePanel;
- (void)close;
- (id)c18ModuleInstance;
@end

FOUNDATION_EXPORT void C18DataSwitchOpenForHost(C18FiveModuleHost *host);
FOUNDATION_EXPORT void C18DataSwitchInstallGestures(C18FiveModuleHost *host);
FOUNDATION_EXPORT void C18DataSwitchRegisterHost(id module, C18FiveModuleHost *host);
FOUNDATION_EXPORT void C18NativeLayoutRestoreInstall(void);
