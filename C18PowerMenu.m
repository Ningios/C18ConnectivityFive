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
#import <signal.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <sys/wait.h>

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

static void C18PowerLog(NSString *message) {
    NSLog(@"[C18Power] %@",message);
    NSString *line=[NSString stringWithFormat:@"%@ %@\n",[NSDate date],message];
    NSData *bytes=[line dataUsingEncoding:NSUTF8StringEncoding];
    int fd=open("/var/mobile/Library/Logs/C18PowerActions.log",O_WRONLY|O_CREAT|O_APPEND|O_CLOEXEC|O_NOFOLLOW,0600);
    if (fd>=0) { (void)write(fd,bytes.bytes,bytes.length);close(fd); }
}
static void C18PowerFailure(UIView *anchor,NSString *message) {
    if (!NSThread.isMainThread) {dispatch_async(dispatch_get_main_queue(),^{C18PowerFailure(anchor,message);});return;}
    C18PowerLog(message);
    UIWindow *window=anchor.window;
    if (!window) for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) if (candidate.isKeyWindow) {window=candidate;break;}
        if (window) break;
    }
    if (!window) return;
    UILabel *label=[UILabel new];label.text=message;label.numberOfLines=0;label.textAlignment=NSTextAlignmentCenter;
    label.textColor=UIColor.whiteColor;label.backgroundColor=[UIColor.blackColor colorWithAlphaComponent:0.84];
    label.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];label.layer.cornerRadius=18;label.clipsToBounds=YES;
    CGFloat width=MIN(340,CGRectGetWidth(window.bounds)-36);
    label.frame=CGRectMake((CGRectGetWidth(window.bounds)-width)/2,MAX(60,window.safeAreaInsets.top+24),width,88);
    [window addSubview:label];UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,message);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(),^{[label removeFromSuperview];});
}
static NSString *C18PowerHelperPath(void) {
    // Use the official RootHide API first; dladdr is only a compatibility route.
    typedef const char *(*C18JBRoot)(const char *);
    static C18JBRoot convert;static void *library;static dispatch_once_t once;
    dispatch_once(&once,^{
        convert=(C18JBRoot)dlsym(RTLD_DEFAULT,"jbroot");
        if (!convert) {
            library=dlopen("@loader_path/.jbroot/usr/lib/libroothide.dylib",RTLD_NOW|RTLD_LOCAL);
            if (library) convert=(C18JBRoot)dlsym(library,"jbroot");
        }
    });
    const char *logical="/usr/libexec/C18PowerHelper";
    if (convert) {const char *path=convert(logical);if (path && path[0]=='/' && access(path,F_OK)==0) return [NSString stringWithUTF8String:path];}
    Dl_info image={0};char physical[PATH_MAX],root[PATH_MAX],path[PATH_MAX];
    if (dladdr((const void *)&kC18PowerMenu,&image) && image.dli_fname) {
        const char *name=realpath(image.dli_fname,physical) ?: image.dli_fname;
        if (C18PowerInstallRoot(name,root,sizeof(root)) && C18PowerResolveHelper(root,path,sizeof(path)) && access(path,F_OK)==0)
            return [NSString stringWithUTF8String:path];
        // RootHide's installer maintains this link beside the loaded library.
        NSString *link=[[[NSString stringWithUTF8String:image.dli_fname] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@".jbroot/usr/libexec/C18PowerHelper"];
        if (realpath(link.fileSystemRepresentation,path)) return [NSString stringWithUTF8String:path];
    }
    return @"/var/jb/usr/libexec/C18PowerHelper";
}
static void C18PowerUserspaceRun(UIView *anchor) {
    NSString *path=C18PowerHelperPath();
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        struct stat info={0};const char *file=path.fileSystemRepresentation;
        if (stat(file,&info)!=0) {C18PowerFailure(anchor,[NSString stringWithFormat:@"找不到电源执行器：%s",strerror(errno)]);return;}
        if (!S_ISREG(info.st_mode) || info.st_uid!=0 || !(info.st_mode&S_ISUID) || (info.st_mode&0022)) {
            C18PowerFailure(anchor,@"电源执行器安装权限不正确（需要 root / 4755）");return;
        }
        int descriptors[2];if (pipe(descriptors)!=0) {C18PowerFailure(anchor,@"无法读取电源执行结果");return;}
        fcntl(descriptors[0],F_SETFD,FD_CLOEXEC);fcntl(descriptors[1],F_SETFD,FD_CLOEXEC);
        posix_spawn_file_actions_t actions;int error=posix_spawn_file_actions_init(&actions);
        if (!error) {
            error=posix_spawn_file_actions_adddup2(&actions,descriptors[1],STDOUT_FILENO);
            if (!error) error=posix_spawn_file_actions_adddup2(&actions,descriptors[1],STDERR_FILENO);
            if (!error) error=posix_spawn_file_actions_addclose(&actions,descriptors[0]);
            if (!error) error=posix_spawn_file_actions_addclose(&actions,descriptors[1]);
            pid_t pid=0;char *argv[]={(char *)file,"--userspace",NULL};
            if (!error) error=posix_spawn(&pid,file,&actions,NULL,argv,environ);
            posix_spawn_file_actions_destroy(&actions);close(descriptors[1]);
            if (!error) {
                C18PowerLog([NSString stringWithFormat:@"helper spawned pid=%d path=%@",(int)pid,path]);
                NSMutableData *output=[NSMutableData data];char buffer[512];ssize_t size;
                while ((size=read(descriptors[0],buffer,sizeof(buffer)))!=0) {
                    if (size<0) {if (errno==EINTR)continue;break;}
                    if (output.length<4096) [output appendBytes:buffer length:MIN((NSUInteger)size,4096-output.length)];
                }
                close(descriptors[0]);int status=0;pid_t waited;
                do {waited=waitpid(pid,&status,0);} while (waited<0 && errno==EINTR);
                NSString *detail=[[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding] ?: @"";
                C18PowerLog([NSString stringWithFormat:@"helper wait=%d status=%d output=%@",(int)waited,status,detail]);
                if (waited<0 || !WIFEXITED(status) || WEXITSTATUS(status)!=0)
                    C18PowerFailure(anchor,[NSString stringWithFormat:@"用户空间重启失败（状态 %d）\n%@",status,detail]);
                return;
            }
        } else close(descriptors[1]);
        close(descriptors[0]);C18PowerFailure(anchor,[NSString stringWithFormat:@"电源执行器启动失败：%s",strerror(error)]);
    });
}
static void C18PowerPerform(C18PowerOperation operation,UIView *anchor) {
    C18PowerLog([NSString stringWithFormat:@"selected operation=%d uid=%u euid=%u",operation,(unsigned)getuid(),(unsigned)geteuid()]);
    if (strcmp(getprogname(),"SpringBoard") || ![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
        C18PowerFailure(anchor,@"电源操作只能由 SpringBoard 执行");return;
    }
    if (operation==C18PowerRespring) {
        if (kill(getpid(),SIGKILL)!=0) C18PowerFailure(anchor,[NSString stringWithFormat:@"注销失败：%s",strerror(errno)]);
        return;
    }
    if (operation==C18PowerUserspace) {C18PowerUserspaceRun(anchor);return;}
    if (operation!=C18PowerShutdown && operation!=C18PowerReboot) {C18PowerFailure(anchor,@"未知电源操作");return;}
    Class cls=objc_getClass("FBSystemService");SEL shared=NSSelectorFromString(@"sharedInstance"),shutdown=NSSelectorFromString(@"shutdownAndReboot:");
    if (!C18HookSignatureMatches(class_getClassMethod(cls,shared),"@",@[])) {C18PowerFailure(anchor,@"系统电源服务不可用");return;}
    @try {
        id service=((id(*)(id,SEL))objc_msgSend)(cls,shared);
        if (!service || !C18HookCanInstall(object_getClass(service),shutdown,"v",@[@"B"])) {C18PowerFailure(anchor,@"系统电源接口签名不匹配");return;}
        C18PowerLog([NSString stringWithFormat:@"FBSystemService shutdownAndReboot=%d",operation==C18PowerReboot]);
        ((void(*)(id,SEL,BOOL))objc_msgSend)(service,shutdown,operation==C18PowerReboot);
    } @catch (NSException *error) {C18PowerFailure(anchor,[NSString stringWithFormat:@"系统电源调用失败：%@",error.reason]);}
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
            (void)action;
            // UIKit has accepted the selection. Dismissal is not cancellation.
            // Serialize selection on main instead of dropping off-main delivery.
            void (^perform)(void)=^{
                if (selection.consumed) return;
                selection.consumed=YES;C18PowerPerform(operation,weakAnchor);
            };
            if (NSThread.isMainThread) perform();else dispatch_async(dispatch_get_main_queue(),perform);
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
