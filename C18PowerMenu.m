#import "C18Five.h"
#import "C18HookRuntime.h"
#import "C18PowerBackend.h"
#import <spawn.h>
#import <string.h>

extern void MSHookMessageEx(Class,SEL,IMP,IMP *);
static char kC18PowerMenu;
static BOOL gC18PowerHooked;
static Class gC18PowerOwner;
// Saved only for the hooking API. Deliberately NEVER called: no old popup path.
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
    (void)interaction;(void)location;UIMenu *menu=self.menu;
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
    (void)interaction;(void)configuration;__weak C18PowerMenuBridge *weakSelf=self;NSObject *session=self.session;
    void (^clear)(void)=^{C18PowerMenuBridge *bridge=weakSelf;if (!bridge || bridge.session!=session) return;bridge.menu=nil;bridge.session=nil;};
    if (animator) [animator addCompletion:clear];else clear();
}
@end

static int C18PowerSpawn(const char *path,const char *const *arguments,void *context) {
    (void)context;
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:[NSString stringWithUTF8String:path]]) return 0;
    // Original provider passes argv[0]=program, at most two arguments, envp=NULL.
    char *argv[4]={(char *)path,NULL,NULL,NULL};size_t count=0;
    while (arguments[count]) {if (count>=2) return 0;argv[count+1]=(char *)arguments[count];count++;}
    pid_t pid=0;return posix_spawn(&pid,path,NULL,NULL,argv,NULL)==0;
}
static void C18PowerSafeMarker(void *context) {
    (void)context;
    [[NSFileManager defaultManager] createFileAtPath:@"/var/mobile/Library/.C18SafeMode" contents:[NSData data] attributes:nil];
}
static UIView *C18PowerAnchor(id owner) {
    Ivar ivar=class_getInstanceVariable(object_getClass(owner),"_power");
    id value=ivar && C18HookTypeMatches(ivar_getTypeEncoding(ivar),"@")?object_getIvar(owner,ivar):nil;
    return [value isKindOfClass:UIView.class]?value:nil;
}
static void C18PowerUnavailable(UIView *anchor) {
    anchor.accessibilityValue=@"电源菜单暂不可用";
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,@"电源菜单暂不可用");
}
static void C18PowerTriggered(id self,SEL cmd) {
    (void)cmd;
    // A stale/non-live Shell cannot show either menu or invoke any backend.
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
    NSArray<NSString *> *titles=@[@"关机",@"注销",@"重启系统",@"重启用户空间",@"安全模式"];
    NSMutableArray<UIAction *> *items=[NSMutableArray arrayWithCapacity:5];
    __weak id weakOwner=self;__weak UIView *weakAnchor=anchor;
    NSUInteger generation=C18FivePresentationGeneration();C18PowerSelection *selection=[C18PowerSelection new];
    for (NSUInteger index=0;index<titles.count;index++) {
        C18PowerOperation operation=(C18PowerOperation)index;
        UIAction *item=[UIAction actionWithTitle:titles[index] image:nil identifier:nil handler:^(__kindof UIAction *action){
            (void)action;id owner=weakOwner;UIView *source=weakAnchor;
            if (selection.consumed || !NSThread.isMainThread || !source.window || !C18FiveIsPresented() || owner!=C18FiveLiveShell() || generation!=C18FivePresentationGeneration()) return;
            selection.consumed=YES;
            if (!C18PowerExecute(operation,C18PowerSpawn,C18PowerSafeMarker,NULL)) {
                source.accessibilityValue=@"电源操作未能启动";
                UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,@"电源操作未能启动");
            }
        }];
        if (operation==C18PowerShutdown) item.attributes=UIMenuElementAttributesDestructive;
        [items addObject:item];
    }
    bridge.session=[NSObject new];bridge.menu=[UIMenu menuWithTitle:@"" children:items];
    anchor.accessibilityValue=nil;
    CGPoint point=CGPointMake(CGRectGetMidX(anchor.bounds),CGRectGetMidY(anchor.bounds));
    @try {((void(*)(id,SEL,CGPoint))objc_msgSend)(bridge.interaction,present,point);}
    @catch (__unused NSException *error) {bridge.menu=nil;bridge.session=nil;C18PowerUnavailable(anchor);}
}
void C18PowerMenuInstall(void) {
    // Metadata-only registration; safe before first real presentation. The
    // obsolete C18PowerMenu.dylib/plist are removed at packaging, so its delayed
    // method_setImplementation can no longer overwrite this hook after restart.
    if (!NSThread.isMainThread || gC18PowerHooked) return;
    Class cls=objc_getClass("C18Shell");SEL selector=NSSelectorFromString(@"_powerTriggered");
    if (!C18HookCanInstall(cls,selector,"v",@[])) return;
    gC18PowerOwner=cls;gC18PowerHooked=YES;
    MSHookMessageEx(cls,selector,(IMP)C18PowerTriggered,(IMP *)&gC18PowerOriginal);
}
