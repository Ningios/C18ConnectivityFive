#import "C18Five.h"
#import <dlfcn.h>
#import <string.h>
#import "C18HookRuntime.h"

extern void MSHookMessageEx(Class,SEL,IMP,IMP *);
static char kC18PowerMenu, kC18PowerAction, kC18PowerToken;
static __thread void *gC18PowerScope;
static BOOL gC18PowerHooked, gC18PowerFactoriesHooked;
static Class gC18PowerOwner;
static void (*gC18PowerOriginal)(id,SEL);
static UIAlertAction *(*gC18ActionOriginal)(id,SEL,NSString *,UIAlertActionStyle,void(^)(UIAlertAction *));
typedef void (*C18PowerPresentIMP)(id,SEL,UIViewController *,BOOL,void(^)(void));

@interface C18PowerRequest : NSObject
@property(nonatomic,weak) id owner;
@property(nonatomic,weak) UIViewController *presenter;
@property(nonatomic,weak) UIView *anchor;
@property(nonatomic,strong) NSObject *token;
@property(nonatomic,strong) UIAlertController *alert;
@property(nonatomic) BOOL animated;
@end
@implementation C18PowerRequest @end

// A permanent, typed trampoline and independent original for each concrete class.
// Never share a single original across a superclass/subclass or Power/DataSwitch.
@interface C18PowerPresenterHook : NSObject {
@public C18PowerPresentIMP original;
}
@property(nonatomic) Class owner;
@property(nonatomic) IMP replacement;
@end
@implementation C18PowerPresenterHook @end
static NSMutableArray<C18PowerPresenterHook *> *gC18PowerPresenters;
static BOOL C18PowerInstallPresenter(UIViewController *presenter);
static NSArray<UIAction *> *C18PowerItems(UIAlertController *alert,C18PowerRequest *request);
void C18PowerMenuInstall(void);

@interface C18PowerMenuBridge : NSObject <UIContextMenuInteractionDelegate>
@property(nonatomic,strong) UIContextMenuInteraction *interaction;
@property(nonatomic,strong) UIAlertController *originalAlert;
@property(nonatomic,strong) UIMenu *menu;
@property(nonatomic,weak) UIView *anchor;
@property(nonatomic,strong) NSObject *session;
@end
@implementation C18PowerMenuBridge
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction configurationForMenuAtLocation:(CGPoint)location {
    (void)interaction; (void)location;
    UIMenu *menu=self.menu;
    return menu?[UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested){ (void)suggested; return menu; }]:nil;
}
- (UITargetedPreview *)preview {
    UIView *view=self.anchor;
    if (!view.window) return nil;
    UIPreviewParameters *parameters=[UIPreviewParameters new]; parameters.backgroundColor=UIColor.clearColor;
    parameters.visiblePath=[UIBezierPath bezierPathWithOvalInRect:view.bounds];
    return [[UITargetedPreview alloc] initWithView:view parameters:parameters];
}
- (UITargetedPreview *)contextMenuInteraction:(UIContextMenuInteraction *)interaction previewForHighlightingMenuWithConfiguration:(UIContextMenuConfiguration *)configuration { (void)interaction; (void)configuration; return [self preview]; }
- (UITargetedPreview *)contextMenuInteraction:(UIContextMenuInteraction *)interaction previewForDismissingMenuWithConfiguration:(UIContextMenuConfiguration *)configuration { (void)interaction; (void)configuration; return [self preview]; }
- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction willEndForConfiguration:(UIContextMenuConfiguration *)configuration animator:(id<UIContextMenuInteractionAnimating>)animator {
    (void)interaction; (void)configuration;
    // The session retains original UIAlertActions/handlers only until dismissal.
    __weak C18PowerMenuBridge *weakSelf=self; NSObject *session=self.session;
    void (^clear)(void)=^{
        C18PowerMenuBridge *bridge=weakSelf;
        if (!bridge || bridge.session!=session) return;
        bridge.originalAlert=nil; bridge.menu=nil; bridge.session=nil;
    };
    if (animator) [animator addCompletion:clear]; else clear();
}
@end
static BOOL C18PowerRequestLive(C18PowerRequest *request) {
    id owner=request.owner; UIView *anchor=request.anchor;
    return NSThread.isMainThread && C18FiveIsPresented() && owner && owner==C18FiveLiveShell() &&
        anchor.window && request.token && objc_getAssociatedObject(owner,&kC18PowerToken)==request.token;
}
static UIAlertAction *C18PowerAction(id self,SEL cmd,NSString *title,UIAlertActionStyle style,void(^handler)(UIAlertAction *)) {
    UIAlertAction *action=gC18ActionOriginal(self,cmd,title,style,handler);
    C18PowerRequest *request=(__bridge C18PowerRequest *)gC18PowerScope;
    if (action && handler && C18PowerRequestLive(request)) {
        objc_setAssociatedObject(action,&kC18PowerAction,[handler copy],OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(action,&kC18PowerToken,request.token,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return action;
}
static BOOL C18PowerInstallFactories(void) {
    if (gC18PowerFactoriesHooked) return gC18ActionOriginal!=NULL;
    SEL selector=@selector(actionWithTitle:style:handler:); Class meta=object_getClass(UIAlertAction.class);
    if (!C18HookCanInstall(meta,selector,"@",@[@"@",@(@encode(UIAlertActionStyle)),@"@?"])) return NO;
    gC18PowerFactoriesHooked=YES;
    MSHookMessageEx(meta,selector,(IMP)C18PowerAction,(IMP *)&gC18ActionOriginal);
    return gC18ActionOriginal!=NULL;
}
static void C18PowerPresent(C18PowerPresenterHook *hook,id self,UIViewController *controller,BOOL animated,void(^completion)(void)) {
    C18PowerRequest *request=(__bridge C18PowerRequest *)gC18PowerScope;
    // A non-nil completion must retain UIKit's original scheduling/count semantics.
    if (!completion && !request.alert && self==request.presenter && C18PowerRequestLive(request) &&
        [controller isKindOfClass:UIAlertController.class] && C18PowerItems((UIAlertController *)controller,request).count==5) {
        request.alert=(UIAlertController *)controller; request.animated=animated; return;
    }
    hook->original(self,@selector(presentViewController:animated:completion:),controller,animated,completion);
}
static BOOL C18PowerInstallPresenter(UIViewController *presenter) {
    Class cls=object_getClass(presenter); SEL selector=@selector(presentViewController:animated:completion:);
    if (!NSThread.isMainThread || ![presenter isKindOfClass:UIViewController.class] || cls==UIViewController.class ||
        !C18HookCanInstall(cls,selector,"v",@[@"@",@"B",@"@?"])) return NO;
    for (C18PowerPresenterHook *known in gC18PowerPresenters)
        if (known.owner==cls) return known->original!=NULL;
    C18PowerPresenterHook *hook=[C18PowerPresenterHook new]; hook.owner=cls;
    IMP prior=class_getMethodImplementation(cls,selector);
    // Typed block includes the receiver; _cmd is fixed to the validated selector.
    hook.replacement=imp_implementationWithBlock(^(id receiver,UIViewController *controller,BOOL animated,void(^completion)(void)) {
        C18PowerPresent(hook,receiver,controller,animated,completion);
    });
    if (!prior || !hook.replacement) return NO;
    hook->original=(C18PowerPresentIMP)prior;
    if (!gC18PowerPresenters) gC18PowerPresenters=[NSMutableArray array];
    [gC18PowerPresenters addObject:hook];
    MSHookMessageEx(cls,selector,hook.replacement,(IMP *)&hook->original);
    return hook->original!=NULL;
}
static UIView *C18PowerAnchor(id owner) {
    Ivar ivar=class_getInstanceVariable(object_getClass(owner),"_power");
    return ivar && C18HookTypeMatches(ivar_getTypeEncoding(ivar),"@") ? object_getIvar(owner,ivar) : nil;
}
static UIViewController *C18PowerTop(UIView *anchor) {
    // beta9 C18TopVC selects the existing keyWindow (or first window), root, then presented chain.
    // Do this only during a real tap; no +[C18Shell shared], overlay getter or forced view load.
    UIWindow *window=anchor.window; if (!window) return nil;
    for (UIWindow *candidate in window.windowScene.windows) if (candidate.isKeyWindow) { window=candidate; break; }
    UIViewController *top=window.rootViewController;
    for (NSUInteger depth=0;top && depth<32;depth++) {
        UIViewController *next=top.presentedViewController;
        if (!next) return top; if (next==top) return nil; top=next;
    }
    return nil;
}
static NSArray<UIAction *> *C18PowerItems(UIAlertController *alert,C18PowerRequest *request) {
    NSArray<NSString *> *titles=@[@"关机",@"注销",@"重启系统",@"重启用户空间",@"安全模式"];
    NSMutableArray<UIAction *> *items=[NSMutableArray array];
    for (NSString *title in titles) {
        UIAlertAction *original=nil;
        for (UIAlertAction *candidate in alert.actions)
            if ([candidate.title isEqualToString:title] && objc_getAssociatedObject(candidate,&kC18PowerToken)==request.token) {
                if (original) return nil; original=candidate;
            }
        void(^handler)(UIAlertAction *)=original?objc_getAssociatedObject(original,&kC18PowerAction):nil;
        if (!original || !handler) return nil;
        UIAction *item=[UIAction actionWithTitle:original.title image:nil identifier:nil handler:^(__kindof UIAction *action){ (void)action; handler(original); }];
        if ([title isEqualToString:@"关机"]) item.attributes=UIMenuElementAttributesDestructive;
        if (!original.enabled) item.attributes|=UIMenuElementAttributesDisabled;
        [items addObject:item];
    }
    return items;
}
static void C18PowerTriggered(id self,SEL cmd) {
    // The method may also be sent to stale/non-live shells; they keep their exact original behavior.
    if (!NSThread.isMainThread || !C18FiveIsPresented() || self!=C18FiveLiveShell() ||
        ![self isKindOfClass:gC18PowerOwner] || gC18PowerScope) {
        if (gC18PowerOriginal) gC18PowerOriginal(self,cmd); return;
    }
    UIView *anchor=C18PowerAnchor(self);
    if (![anchor isKindOfClass:UIView.class] || !anchor.window) {
        if (gC18PowerOriginal) gC18PowerOriginal(self,cmd); return;
    }
    C18PowerMenuBridge *bridge=objc_getAssociatedObject(anchor,&kC18PowerMenu);
    if (bridge.menu) return;
    if (!bridge) {
        bridge=[C18PowerMenuBridge new]; bridge.anchor=anchor;
        bridge.interaction=[[UIContextMenuInteraction alloc] initWithDelegate:bridge];
        [anchor addInteraction:bridge.interaction];
        objc_setAssociatedObject(anchor,&kC18PowerMenu,bridge,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    SEL present=NSSelectorFromString(@"_presentMenuAtLocation:");
    UIViewController *top=C18PowerTop(anchor);
    if (!C18HookCanInstall(object_getClass(bridge.interaction),present,"v",@[@(@encode(CGPoint))]) ||
        !C18PowerInstallPresenter(top) || !C18PowerInstallFactories()) {
        if (gC18PowerOriginal) gC18PowerOriginal(self,cmd); return;
    }
    C18PowerRequest *request=[C18PowerRequest new]; request.owner=self; request.anchor=anchor;
    request.presenter=top; request.token=[NSObject new];
    objc_setAssociatedObject(self,&kC18PowerToken,request.token,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    void *previous=gC18PowerScope; gC18PowerScope=(__bridge void *)request;
    @try { if (gC18PowerOriginal) gC18PowerOriginal(self,cmd); }
    @finally {
        gC18PowerScope=previous;
        if (objc_getAssociatedObject(self,&kC18PowerToken)==request.token)
            objc_setAssociatedObject(self,&kC18PowerToken,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIAlertController *alert=request.alert; if (!alert) return;
    NSArray<UIAction *> *items=C18PowerItems(alert,request);
    if (items.count!=5 || !anchor.window || C18FiveLiveShell()!=self || !C18FiveIsPresented()) {
        // TLS is already cleared. A normal message safely traverses every per-class original.
        [top presentViewController:alert animated:request.animated completion:nil]; return;
    }
    bridge.session=request.token; bridge.originalAlert=alert;
    bridge.menu=[UIMenu menuWithTitle:@"" children:items];
    CGPoint point=CGPointMake(CGRectGetMidX(anchor.bounds),CGRectGetMidY(anchor.bounds));
    ((void(*)(id,SEL,CGPoint))objc_msgSend)(bridge.interaction,present,point);
}
void C18PowerMenuInstall(void) {
    if (!NSThread.isMainThread || !C18FiveIsPresented() || !C18FiveLiveShell() || gC18PowerHooked) return;
    Class cls=objc_getClass("C18Shell"); SEL selector=NSSelectorFromString(@"_powerTriggered");
    if (!C18HookCanInstall(cls,selector,"v",@[])) return;
    Method method=class_getInstanceMethod(cls,selector); Dl_info image={0}; IMP current=method_getImplementation(method);
    // The original provider owns all five backends. Never hook an unknown/stub implementation.
    BOOL ready=current && dladdr((const void *)current,&image) && image.dli_fname && strstr(image.dli_fname,"C18PowerMenu.dylib");
    if (!ready) return; // Next overlay/tap/data-host flow may try; no startup polling.
    gC18PowerOwner=cls; gC18PowerHooked=YES; gC18PowerOriginal=(void(*)(id,SEL))current;
    MSHookMessageEx(cls,selector,(IMP)C18PowerTriggered,(IMP *)&gC18PowerOriginal);
}
