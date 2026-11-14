#import "C18Five.h"
#import "C18HookRuntime.h"
#import <math.h>
#import <string.h>
extern void MSHookMessageEx(Class,SEL,IMP,IMP *);
static char kC18UptimeState;
static BOOL gUptimeInstalled;
static NSHashTable *gUptimeControllers;
static void (*oUptimeLoad)(id,SEL),(*oUptimeLayout)(id,SEL),(*oUptimeRemove)(id,SEL);
static void (*oUptimeAdd)(id,SEL),(*oUptimeText)(id,SEL);
static Class gUptimeButtonClass,gUptimeContentClass;
static id C18UptimeIvar(id object,const char *name) {
    Ivar ivar=object?class_getInstanceVariable(object_getClass(object),name):NULL;
    return ivar && C18HookTypeMatches(ivar_getTypeEncoding(ivar),"@")?object_getIvar(object,ivar):nil;
}
@interface C18UptimeState:NSObject
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,weak) UIViewController *controller;
@end
@implementation C18UptimeState
- (void)dealloc {[_timer invalidate];}
@end
static void C18UptimeUpdate(id object) {
    if (!NSThread.isMainThread || ![object isKindOfClass:gUptimeButtonClass]) return;
    UIViewController *controller=object;UIView *view=controller.viewIfLoaded;
    UILabel *label=C18FiveObject(object,NSSelectorFromString(@"uptimeLabel"));
    if (!view || ![label isKindOfClass:UILabel.class]) return;
    // The old controller positions its fixed-width label before its parent
    // receives real bounds. Use the current local bounds, never view.center.
    CGRect frame=CGRectInset(view.bounds,6,0);
    if (frame.size.width<0) frame.size.width=0;
    if (!CGRectEqualToRect(label.frame,frame)) label.frame=frame;
    label.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    // Use the module's formatter verbatim: keep newlines, spaces and units.
    // Only remove a leading heart and its optional variation selector/space.
    if (oUptimeText) oUptimeText(object,NSSelectorFromString(@"setUptimeText"));
    NSString *text=label.text;
    if ([text hasPrefix:@"❤️"]) text=[text substringFromIndex:@"❤️".length];
    else if ([text hasPrefix:@"❤"]) text=[text substringFromIndex:@"❤".length];
    if (text!=label.text) {
        while ([text hasPrefix:@" "]) text=[text substringFromIndex:1];
        label.text=text;
    }
}
static void C18UptimeStop(id object) {
    C18UptimeState *state=objc_getAssociatedObject(object,&kC18UptimeState);
    [state.timer invalidate];state.timer=nil;
    // Also retires the timer that a naturally loaded old module may already
    // have created before this metadata hook was registered.
    if (oUptimeRemove) oUptimeRemove(object,NSSelectorFromString(@"removeTimer"));
}
static void C18UptimeAdd(id object,SEL cmd) {
    (void)cmd;if (!NSThread.isMainThread) return;
    if (!gUptimeControllers) gUptimeControllers=[NSHashTable weakObjectsHashTable];
    [gUptimeControllers addObject:object];
    C18UptimeStop(object);C18UptimeUpdate(object);
    if (!C18FiveIsPresented()) return;
    C18UptimeState *state=objc_getAssociatedObject(object,&kC18UptimeState);
    if (!state) {state=[C18UptimeState new];state.controller=object;objc_setAssociatedObject(object,&kC18UptimeState,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    __weak UIViewController *weakController=object;
    state.timer=[NSTimer timerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer){
        UIViewController *controller=weakController;
        if (!controller) {[timer invalidate];return;}
        C18UptimeUpdate(controller);
    }];
    // Tracking the control-center pull gesture must not pause the first tick.
    [NSRunLoop.mainRunLoop addTimer:state.timer forMode:NSRunLoopCommonModes];
}
static void C18UptimeRemove(id object,SEL cmd) {(void)cmd;if (NSThread.isMainThread) C18UptimeStop(object);}
static void C18UptimeText(id object,SEL cmd) {(void)cmd;C18UptimeUpdate(object);}
static void C18UptimeLoad(id object,SEL cmd) {if (oUptimeLoad) oUptimeLoad(object,cmd);C18UptimeUpdate(object);}
static void C18UptimeLayout(id object,SEL cmd) {if (oUptimeLayout) oUptimeLayout(object,cmd);C18UptimeUpdate(object);}
void C18UptimeFixInstall(void) {
    if (!NSThread.isMainThread || gUptimeInstalled) return;
    Class cls=objc_getClass("UptimeButtonController");const char *path=cls?class_getImageName(cls):NULL;
    if (!path || !strstr(path,"/UptimeModule.bundle/")) return;
    SEL selectors[5]={@selector(viewDidLoad),@selector(viewDidLayoutSubviews),NSSelectorFromString(@"addTimer"),NSSelectorFromString(@"removeTimer"),NSSelectorFromString(@"setUptimeText")};
    for (NSUInteger i=0;i<5;i++) if (!C18HookCanInstall(cls,selectors[i],"v",@[])) return;
    if (!C18HookCanInstall(cls,NSSelectorFromString(@"getDeviceUptime"),"q",@[]) ||
        !C18HookCanInstall(cls,NSSelectorFromString(@"uptimeLabel"),"@",@[])) return;
    gUptimeButtonClass=cls;gUptimeContentClass=objc_getClass("UptimeModuleContentViewController");gUptimeInstalled=YES;
    IMP hooks[5]={(IMP)C18UptimeLoad,(IMP)C18UptimeLayout,(IMP)C18UptimeAdd,(IMP)C18UptimeRemove,(IMP)C18UptimeText};
    IMP *originals[5]={(IMP *)&oUptimeLoad,(IMP *)&oUptimeLayout,(IMP *)&oUptimeAdd,(IMP *)&oUptimeRemove,(IMP *)&oUptimeText};
    for (NSUInteger i=0;i<5;i++) MSHookMessageEx(cls,selectors[i],hooks[i],originals[i]);
}
void C18UptimePrepareModule(UIView *module) {
    if (!NSThread.isMainThread || !gUptimeInstalled) return;
    id content=C18FiveObject(module,NSSelectorFromString(@"contentView"));
    id controller=C18UptimeIvar(content,"_vc");
    if (![controller isKindOfClass:gUptimeContentClass]) return;
    id button=C18UptimeIvar(controller,"_uptimeButton");
    if (![button isKindOfClass:gUptimeButtonClass]) return;
    if (!gUptimeControllers) gUptimeControllers=[NSHashTable weakObjectsHashTable];
    [gUptimeControllers addObject:button];
    // Adoption also handles a controller whose original wrapper has not yet
    // forwarded presentation. Shell retirement always stops every adopted timer.
    C18UptimeState *state=objc_getAssociatedObject(button,&kC18UptimeState);
    if (C18FiveIsPresented() && !state.timer) C18UptimeAdd(button,NSSelectorFromString(@"addTimer"));
    else if (!C18FiveIsPresented()) C18UptimeStop(button);
    C18UptimeUpdate(button);
}
void C18UptimeSetPresented(BOOL presented) {
    if (!NSThread.isMainThread || !gUptimeInstalled) return;
    for (id button in gUptimeControllers.allObjects) {
        C18UptimeState *state=objc_getAssociatedObject(button,&kC18UptimeState);
        if (presented && !state.timer) C18UptimeAdd(button,NSSelectorFromString(@"addTimer"));
        else if (!presented) C18UptimeStop(button);
    }
}
