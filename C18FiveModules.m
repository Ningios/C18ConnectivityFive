#import "C18Five.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>

extern void MSHookMessageEx(Class, SEL, IMP, IMP *);
static char kC18ModuleOwner;
static BOOL gNativeHooksDone;
static BOOL (*gNativeAppearance)(id,SEL);
static NSHashTable *gNativeHosts;
static id C18FiveShell(void) {
    Class cls=objc_getClass("C18Shell"); SEL sel=NSSelectorFromString(@"shared");
    if (!cls || ![cls respondsToSelector:sel]) return nil;
    return ((id(*)(id,SEL))objc_msgSend)(cls,sel);
}
static BOOL C18FiveButtonController(id vc) {
    // The native C18ButtonModuleView is the common adapter for third-party
    // CC modules; do not require a particular private controller subclass.
    return [vc isKindOfClass:UIViewController.class];
}
static BOOL C18FiveHasSlider(UIView *view, NSInteger depth) {
    if (!view || depth>10) return NO;
    NSString *n=[NSStringFromClass(view.class) lowercaseString];
    if ([view isKindOfClass:UISlider.class] || [n containsString:@"slider"] || [n containsString:@"nowplaying"]) return YES;
    for (UIView *child in view.subviews) if (C18FiveHasSlider(child,depth+1)) return YES;
    return NO;
}
static BOOL C18FiveWantsAppearance(id self,SEL cmd) {
    NSHashTable *refs=objc_getAssociatedObject(self,&kC18ModuleOwner);
    C18FiveModuleHost *host=[refs anyObject];
    if (!host) return gNativeAppearance ? gNativeAppearance(self,cmd) : NO;
    return host.window && !host.hidden && host.alpha>0.01;
}
void C18FiveInstallModuleHooks(void) {
    if (gNativeHooksDone) return;
    Class cls=objc_getClass("C18ButtonModuleView");
    SEL sel=NSSelectorFromString(@"_wantsAppearance");
    Method method=class_getInstanceMethod(cls,sel);
    if (!method) return;
    char *type=method_copyReturnType(method); BOOL valid=type && (*type=='B'||*type=='c'); free(type);
    if (!valid) return;
    gNativeHooksDone=YES;
    MSHookMessageEx(cls,sel,(IMP)C18FiveWantsAppearance,(IMP *)&gNativeAppearance);
    gNativeHosts=[NSHashTable weakObjectsHashTable];
}
@interface C18FiveModuleHost ()
@property(nonatomic,copy,readwrite) NSString *slotID;
@property(nonatomic,copy,readwrite) NSString *failure;
@property(nonatomic,strong,readwrite) UIView *nativeHost;
@property(nonatomic,strong) UIView *moduleView;
@property(nonatomic,strong) id instance;
@end
@implementation C18FiveModuleHost
- (instancetype)initWithSlotID:(NSString *)slotID owner:(UIView *)owner {
    if (!(self=[super initWithFrame:CGRectZero])) return nil;
    _slotID=[slotID copy]; _owner=owner; self.clipsToBounds=YES;
    NSDictionary *entry=C18FiveEntry(slotID); NSString *identifier=C18FiveModuleID(slotID);
    id shell=C18FiveShell();
    SEL create=NSSelectorFromString(@"_instantiateModuleWithIdentifier:");
    SEL wrap=NSSelectorFromString(@"_makeModuleViewForIdentifier:size:instance:gallery:");
    @try {
        if (!entry || !identifier || C18FiveExcluded(identifier,entry[@"principal"])) self.failure=@"该项不支持圆形槽位";
        else if (!gNativeHooksDone || ![shell respondsToSelector:create] || ![shell respondsToSelector:wrap]) self.failure=@"原插件模块加载入口不可用";
        else {
            self.instance=((id(*)(id,SEL,id))objc_msgSend)(shell,create,identifier);
            if (!self.instance) self.failure=@"原模块未安装或加载失败";
            else {
                // Fresh original instances, never steal a view from the main control-center grid.
                id wrapper=((id(*)(id,SEL,id,long long,id,BOOL))objc_msgSend)(shell,wrap,identifier,1,self.instance,NO);
                UIView *native=C18FiveObject(wrapper,NSSelectorFromString(@"contentView"));
                Class cls=objc_getClass("C18ButtonModuleView");
                id vc=C18FiveGet(native,@"_vc");
                UIView *probe=[vc isKindOfClass:UIViewController.class] ? [vc viewIfLoaded] : nil;
                // Only reject a real slider/player view. A missing private controller
                // is not a failure: ordinary system/CC+ modules can load it lazily.
                if (!cls || ![native isKindOfClass:cls] || C18FiveHasSlider(probe,0)) self.failure=@"复杂模块，已排除";
                else {
                    self.nativeHost=native; self.moduleView=wrapper;
                    // NSHashTable holds the parent weakly; no child-parent retain cycle.
                    NSHashTable *ref=[NSHashTable weakObjectsHashTable]; [ref addObject:self];
                    objc_setAssociatedObject(native,&kC18ModuleOwner,ref,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    [gNativeHosts addObject:self]; [self addSubview:wrapper];
                }
            }
        }
    } @catch(NSException *e) { self.failure=@"原模块初始化异常"; }
    if (self.failure) {
        self.instance=nil;
        UILabel *label=[[UILabel alloc] initWithFrame:CGRectZero]; label.text=@"不可用";
        label.font=[UIFont systemFontOfSize:10]; label.textAlignment=NSTextAlignmentCenter;
        label.textColor=UIColor.secondaryLabelColor; label.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        [self addSubview:label]; self.backgroundColor=[UIColor colorWithWhite:0.5 alpha:0.18];
        self.accessibilityLabel=[NSString stringWithFormat:@"%@，%@",entry[@"title"]?:identifier,self.failure];
    }
    // Store only a capability result for the settings page; no action is executed here.
    if (identifier.length) {
        NSString *key=[@"Capability." stringByAppendingString:identifier];
        NSDictionary *value=@{@"available":@(!self.failure),@"reason":self.failure?:@""};
        CFPreferencesSetAppValue((__bridge CFStringRef)key,(__bridge CFPropertyListRef)value,(__bridge CFStringRef)C18FiveDomain);
        CFPreferencesAppSynchronize((__bridge CFStringRef)C18FiveDomain);
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews]; CGFloat side=MIN(self.bounds.size.width,self.bounds.size.height);
    self.layer.cornerRadius=side*0.5;
    if (self.moduleView) {
        self.moduleView.transform=CGAffineTransformIdentity;
        self.moduleView.bounds=CGRectMake(0,0,60,60);
        self.moduleView.center=CGPointMake(CGRectGetMidX(self.bounds),CGRectGetMidY(self.bounds));
        self.moduleView.transform=CGAffineTransformMakeScale(side/60.0,side/60.0);
        [self.moduleView setNeedsLayout]; [self.moduleView layoutIfNeeded];
    } else self.subviews.firstObject.frame=self.bounds;
}
- (void)didMoveToWindow { [super didMoveToWindow]; C18FiveVoid(self.nativeHost,NSSelectorFromString(@"ensureAppeared")); }
- (void)refresh { C18FiveVoid(self.nativeHost,NSSelectorFromString(@"refresh")); C18FiveVoid(self.nativeHost,NSSelectorFromString(@"ensureAppeared")); }
- (void)close {
    // Native didMoveToWindow handles disappearance after detaching.
    [self.moduleView removeFromSuperview];
    objc_setAssociatedObject(self.nativeHost,&kC18ModuleOwner,nil,OBJC_ASSOCIATION_ASSIGN);
    self.moduleView=nil; self.nativeHost=nil; self.instance=nil;
    [self removeFromSuperview];
}
- (void)dealloc { objc_setAssociatedObject(_nativeHost,&kC18ModuleOwner,nil,OBJC_ASSOCIATION_ASSIGN); }
@end
