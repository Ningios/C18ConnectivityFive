#import "C18Five.h"
#import "C18HookRuntime.h"
#import "C18PowerBackend.h"
#import "C18PowerPaths.h"
#import <spawn.h>
#import <dlfcn.h>
#import <errno.h>
#import <limits.h>
#import <stdlib.h>
#import <string.h>
#import <unistd.h>

extern char **environ;
extern void MSHookMessageEx(Class,SEL,IMP,IMP *);
static char kC18PowerMenu;
static BOOL gC18PowerHooked;
static BOOL gC18PowerRetryPending;
static int gC18PowerInstallAttempts;
static Class gC18PowerOwner;
static void (*gC18PowerOriginal)(id,SEL);

@interface C18PowerSelection : NSObject
@property(nonatomic) BOOL consumed;
@end
@implementation C18PowerSelection @end

@interface C18PowerMenuBridge : NSObject <UIContextMenuInteractionDelegate>
@property(nonatomic,strong) UIContextMenuInteraction *interaction;
@property(nonatomic,strong) UIMenu *menu;
@property(nonatomic,weak) UIView *anchor;
@property(nonatomic,strong) NSObject *session;
@end
@implementation C18PowerMenuBridge
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction configurationForMenuAtLocation:(CGPoint)location {
    (void)interaction;(void)location;
    UIMenu *menu=self.menu;
    return menu?[UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested){(void)suggested;return menu;}]:nil;
}
- (UITargetedPreview *)preview {
    UIView *view=self.anchor;if (!view.window) return nil;
    UIPreviewParameters *parameters=[UIPreviewParameters new];parameters.backgroundColor=UIColor.clearColor;
    parameters.visiblePath=[UIBezierPath bezierPathWithOvalInRect:view.bounds];
    return [[UITargetedPreview alloc] initWithView:view parameters:parameters];
}
- (UITargetedPreview *)contextMenuInteraction:(UIContextMenuInteraction *)interaction previewForHighlightingMenuWithConfiguration:(UIContextMenuConfiguration *)configuration {(void)interaction;(void)configuration;return [self preview];}
- (UITargetedPreview *)contextMenuInteraction:(UIContextMenuInteraction *)interaction previewForDismissingMenuWithConfiguration:(UIContextMenuConfiguration *)configuration {(void)interaction;(void)configuration;return [self preview];}
- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction willEndForConfiguration:(UIContextMenuConfiguration *)configuration animator:(id<UIContextMenuInteractionAnimating>)animator {
    (void)interaction;(void)configuration;
    __weak C18PowerMenuBridge *weakSelf=self;NSObject *session=self.session;
    void (^clear)(void)=^{C18PowerMenuBridge *bridge=weakSelf;if (!bridge || bridge.session!=session) return;bridge.menu=nil;bridge.session=nil;};
    if (animator)[animator addCompletion:clear];else clear();
}
@end

typedef struct { int error; } C18PowerRunContext;
static int C18PowerSpawn(const char *logical,const char *const *arguments,void *context) {
    C18PowerRunContext *result=context;Dl_info image={0};char root[PATH_MAX],physical[PATH_MAX],resolved[PATH_MAX];
    const char *imagePath=NULL;
    if (dladdr((const void *)&kC18PowerMenu,&image) && image.dli_fname) {
        imagePath=realpath(image.dli_fname,physical) ?: image.dli_fname;
    }
    if (!logical || !arguments || !imagePath || !C18PowerInstallRoot(imagePath,root,sizeof(root)) ||
        !C18PowerResolvePath(root,logical,resolved,sizeof(resolved))) {
        if (result) result->error=ENOENT;
        return 0;
    }
    if (access(resolved,X_OK)!=0) {if (result) result->error=errno;return 0;}
    char *argv[4]={(char *)resolved,NULL,NULL,NULL};size_t count=0;
    while(arguments[count]) {if (count>=2){if(result)result->error=E2BIG;return 0;}argv[count+1]=(char *)arguments[count];count++;}
    pid_t pid=0;int error=posix_spawn(&pid,resolved,NULL,NULL,argv,environ);
    if (result) result->error=error;
    NSLog(@"[C18Power] spawn operation path=%s error=%d pid=%d",resolved,error,(int)pid);
    return error==0;
}
static UIView *C18PowerAnchor(id owner) {
    Ivar ivar=class_getInstanceVariable(object_getClass(owner),"_power");
    id value=ivar && C18HookTypeMatches(ivar_getTypeEncoding(ivar),"@")?object_getIvar(owner,ivar):nil;
    return [value isKindOfClass:UIView.class]?value:nil;
}
static void C18PowerUnavailable(UIView *anchor) {
    if (!anchor) return;
    anchor.accessibilityValue=@"电源菜单暂不可用";
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,@"电源菜单暂不可用");
}
static void C18PowerTriggered(id self,SEL cmd) {
    (void)cmd;
    if (!NSThread.isMainThread || !C18FiveIsPresented() || self!=C18FiveLiveShell() || ![self isKindOfClass:gC18PowerOwner]) return;
    UIView *anchor=C18PowerAnchor(self);if (!anchor.window) return;
    C18PowerMenuBridge *bridge=objc_getAssociatedObject(anchor,&kC18PowerMenu);if (bridge.menu) return;
    if (!bridge) {
        bridge=[C18PowerMenuBridge new];bridge.anchor=anchor;
        bridge.interaction=[[UIContextMenuInteraction alloc] initWithDelegate:bridge];
        [anchor addInteraction:bridge.interaction];objc_setAssociatedObject(anchor,&kC18PowerMenu,bridge,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    SEL present=NSSelectorFromString(@"_presentMenuAtLocation:");
    if (!C18HookCanInstall(object_getClass(bridge.interaction),present,"v",@[@(@encode(CGPoint))])) {C18PowerUnavailable(anchor);return;}
    NSArray<NSString *> *titles=@[@"关机",@"注销",@"重启系统",@"重启用户空间"];
    NSMutableArray<UIAction *> *items=[NSMutableArray arrayWithCapacity:4];
    __weak UIView *weakAnchor=anchor;C18PowerSelection *selection=[C18PowerSelection new];
    for (NSUInteger index=0;index<titles.count;index++) {
        C18PowerOperation operation=(C18PowerOperation)index;
        UIAction *item=[UIAction actionWithTitle:titles[index] image:nil identifier:nil handler:^(__kindof UIAction *action){
            (void)action;UIView *source=weakAnchor;
            // UIKit has already accepted the selection. Menu dismissal may
            // detach its anchor before this callback; that is not cancellation.
            if (selection.consumed || !NSThread.isMainThread) return;
            selection.consumed=YES;C18PowerRunContext run={0};
            if (!C18PowerExecute(operation,C18PowerSpawn,&run)) {
                NSString *message=[NSString stringWithFormat:@"电源操作未能启动（错误 %d）",run.error];
                source.accessibilityValue=message;UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,message);
            }
        }];
        if (operation==C18PowerShutdown)item.attributes=UIMenuElementAttributesDestructive;
        [items addObject:item];
    }
    bridge.session=[NSObject new];bridge.menu=[UIMenu menuWithTitle:@"" children:items];anchor.accessibilityValue=nil;
    CGPoint point=CGPointMake(CGRectGetMidX(anchor.bounds),CGRectGetMidY(anchor.bounds));
    @try {((void(*)(id,SEL,CGPoint))objc_msgSend)(bridge.interaction,present,point);}
    @catch (__unused NSException *error) {bridge.menu=nil;bridge.session=nil;C18PowerUnavailable(anchor);}
}
static void C18PowerMenuInstallRetry(void);
void C18PowerMenuInstall(void) {
    if (!NSThread.isMainThread) {dispatch_async(dispatch_get_main_queue(),^{C18PowerMenuInstall();});return;}
    if (gC18PowerHooked) return;
    Class cls=objc_getClass("C18Shell");SEL selector=NSSelectorFromString(@"_powerTriggered");
    if (!C18HookCanInstall(cls,selector,"v",@[])) {C18PowerMenuInstallRetry();return;}
    gC18PowerOwner=cls;gC18PowerHooked=YES;
    MSHookMessageEx(cls,selector,(IMP)C18PowerTriggered,(IMP *)&gC18PowerOriginal);
}
static void C18PowerMenuInstallRetry(void) {
    if (gC18PowerRetryPending || gC18PowerInstallAttempts++>=120) return;
    gC18PowerRetryPending=YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),dispatch_get_main_queue(),^{gC18PowerRetryPending=NO;C18PowerMenuInstall();});
}
