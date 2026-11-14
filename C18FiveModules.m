#import "C18Five.h"
#import "C18GlyphSources.h"
#import "C18GlyphGeometry.h"
#import "C18PressDriver.h"
#import "C18HookRuntime.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <string.h>

extern void MSHookMessageEx(Class,SEL,IMP,IMP *);
UIView *C18FiveNativeMaterial(NSString *recipe) {
    typedef UIView *(*Factory)(NSString *,CGFloat);
    Factory factory=(Factory)dlsym(RTLD_DEFAULT,"C18Material");
    if (!factory) {
        Class cls=objc_getClass("C18ConnectivityView"); const char *path=cls?class_getImageName(cls):NULL;
        void *image=path?dlopen(path,RTLD_LAZY|RTLD_NOLOAD):NULL;
        if (image) { factory=(Factory)dlsym(image,"C18Material"); dlclose(image); }
    }
    UIView *view=nil; if (factory) { @try { view=factory(recipe?:@"modulesSheer",1.0); } @catch (__unused NSException *e) {} }
    if (![view isKindOfClass:UIView.class]) view=[[UIView alloc] initWithFrame:CGRectZero];
    view.userInteractionEnabled=NO; return view;
}
static char kModuleOwner;
static BOOL gPresented;
static NSHashTable<C18FiveModuleHost *> *gHosts;
static void C18CompactSync(C18FiveModuleHost *);
static void C18Isolation(C18FiveModuleHost *);
static void C18RestoreLiveGlyph(C18FiveModuleHost *);
static BOOL C18UseLiveGlyph(C18FiveModuleHost *,UIView *);
static BOOL C18Method(id,SEL,const char *,NSArray<NSString *> *);
static BOOL C18State(id,NSString *,BOOL);
static id C18Object(id,NSString *);
static void C18Void(id,NSString *);
static void C18Set(id,NSString *,id);
static C18FiveModuleHost *C18Owner(id);
extern BOOL C18CellularRateOpenForController(id controller,UIView *source);
static BOOL C18RateController(id controller) {
    Class cls=objc_getClass("CCCellularRateModuleViewController");
    return cls && [controller isKindOfClass:cls];
}

@interface C18FiveModuleHost () <UIGestureRecognizerDelegate,UIContextMenuInteractionDelegate>
@property(nonatomic,copy,readwrite) NSString *slotID;
@property(nonatomic,copy,readwrite) NSString *failure;
@property(nonatomic,strong,readwrite) UIView *nativeHost;
@property(nonatomic,strong) UIView *moduleView;
@property(nonatomic,strong) UIControl *roundButton;
@property(nonatomic,strong) id instance;
@property(nonatomic) BOOL syncing;
@property(nonatomic) BOOL closed;
@property(nonatomic,strong) UIImage *sourceGlyph;
@property(nonatomic,strong) UIImage *boundedGlyph;
@property(nonatomic) CGFloat glyphSide;
@property(nonatomic,strong) UIView *glyphContainer;
@property(nonatomic,strong) UIView *liveGlyph;
@property(nonatomic,strong) UIView *glyphHome;
@property(nonatomic) NSUInteger glyphHomeIndex;
@property(nonatomic) CGAffineTransform glyphHomeTransform;
@property(nonatomic) CATransform3D glyphHomeLayerTransform;
@property(nonatomic) CGPoint glyphHomeCenter;
@property(nonatomic) CGRect glyphHomeBounds;
@property(nonatomic) UIViewAutoresizing glyphHomeAutoresizing;
@property(nonatomic,copy) NSArray<NSLayoutConstraint *> *glyphHomeConstraints;
- (BOOL)canHold;
@end
static const char *C18Type(const char *t) { if (!t) return ""; while (*t && strchr("rnNoORV",*t)) t++; return t; }
static BOOL C18EqualType(const char *a,const char *b) {
    a=C18Type(a); if (!strcmp(b,"@")) return a[0]=='@' && a[1]!='?';
    if (!strcmp(b,"B")) return !strcmp(a,"B") || !strcmp(a,"c"); return !strcmp(a,b);
}
static BOOL C18Method(id object,SEL sel,const char *ret,NSArray<NSString *> *args) {
    Method m=object?class_getInstanceMethod(object_getClass(object),sel):NULL;
    if (!m || method_getNumberOfArguments(m)!=args.count+2) return NO;
    char *t=method_copyReturnType(m); BOOL valid=C18EqualType(t,ret); free(t);
    for (NSUInteger i=0;valid && i<args.count;i++) { t=method_copyArgumentType(m,(unsigned)i+2); valid=C18EqualType(t,args[i].UTF8String); free(t); }
    return valid;
}
static id C18Object(id object,NSString *name) {
    SEL sel=NSSelectorFromString(name); if (!C18Method(object,sel,"@",@[])) return nil;
    @try { return ((id(*)(id,SEL))objc_msgSend)(object,sel); } @catch (__unused NSException *e) { return nil; }
}
static void C18Void(id object,NSString *name) { SEL sel=NSSelectorFromString(name); if (C18Method(object,sel,"v",@[])) ((void(*)(id,SEL))objc_msgSend)(object,sel); }
static void C18Set(id object,NSString *name,id value) { SEL sel=NSSelectorFromString(name); if (C18Method(object,sel,"v",@[@"@"])) ((void(*)(id,SEL,id))objc_msgSend)(object,sel,value); }
static BOOL C18State(id object,NSString *name,BOOL fallback) { SEL sel=NSSelectorFromString(name); return C18Method(object,sel,"B",@[])?((BOOL(*)(id,SEL))objc_msgSend)(object,sel):fallback; }
static id C18Shell(void) { return C18FiveLiveShell(); }
static BOOL C18Editing(void) { return C18State(C18Shell(),@"isEditing",NO); }
static C18FiveModuleHost *C18Owner(id object) { NSHashTable *refs=objc_getAssociatedObject(object,&kModuleOwner); return refs.anyObject; }
static BOOL C18Detached(C18FiveModuleHost *host) { return host.nativeHost && host.moduleView && ![host.nativeHost isDescendantOfView:host.moduleView]; }
static BOOL C18Expanded(C18FiveModuleHost *host) { return C18State(host.nativeHost,@"isExpanded",NO) || C18Detached(host); }
static id C18Controller(C18FiveModuleHost *host) { return C18FiveGet(host.nativeHost,@"_vc"); }
static id C18Module(C18FiveModuleHost *host) { return C18FiveGet(host.nativeHost,@"_module")?:host.instance; }
static UIControl *C18FirstControl(UIView *view,NSUInteger depth) {
    if (!view || depth>6) return nil;
    if ([view isKindOfClass:UIControl.class]) return (UIControl *)view;
    for (UIView *child in view.subviews) { UIControl *control=C18FirstControl(child,depth+1); if (control) return control; }
    return nil;
}
static id C18Button(C18FiveModuleHost *host) {
    id vc=C18Controller(host); id button=C18Object(vc,@"buttonView")?:C18Object(vc,@"compactButton");
    if (!button && [vc isKindOfClass:UIViewController.class]) button=C18FirstControl([(UIViewController *)vc viewIfLoaded],0);
    return button;
}
static void C18Remember(id object,C18FiveModuleHost *host) {
    if (!object) return; NSHashTable *refs=[NSHashTable weakObjectsHashTable]; [refs addObject:host];
    objc_setAssociatedObject(object,&kModuleOwner,refs,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static UIImage *C18ImageInView(UIView *view,NSUInteger depth) {
    if (!view || depth>7) return nil;
    if ([view isKindOfClass:UIImageView.class]) { UIImage *image=C18GlyphImageIfVisible([(UIImageView *)view image]); if (image) return image; }
    for (UIView *sub in view.subviews) { UIImage *image=C18ImageInView(sub,depth+1); if (image) return image; }
    return nil;
}
static UIImage *C18Glyph(C18FiveModuleHost *host,BOOL selected) {
    id vc=C18Controller(host), module=C18Module(host), button=C18Button(host);
    NSArray *sources=@[button?:NSNull.null,vc?:NSNull.null,module?:NSNull.null,host.instance?:NSNull.null];
    for (id source in sources) {
        UIImage *image=selected?C18GlyphImageIfVisible(C18Object(source,@"selectedGlyphImage")):nil;
        if (!image) image=C18GlyphImageIfVisible(C18Object(source,@"glyphImage"));
        if (!image) image=C18GlyphImageIfVisible(C18Object(source,@"iconGlyph"));
        if (image) return image;
    }
    UIImage *image=[button isKindOfClass:UIButton.class]?C18GlyphImageIfVisible([(UIButton *)button currentImage]):nil;
    if (!image && [button isKindOfClass:UIView.class]) image=C18ImageInView(button,0);
    if (!image && [vc isKindOfClass:UIViewController.class]) image=C18ImageInView([(UIViewController *)vc viewIfLoaded],0);
    if (!image) image=C18GlyphImageIfVisible(C18Object(vc,@"c18ControlIconImage"));
    return image;
}
static CGFloat C18GlyphTarget(C18FiveModuleHost *host) {
    NSArray *buttons=C18FiveGet(host.owner,@"_buttons");
    id reference=[buttons isKindOfClass:NSArray.class] && buttons.count>2?buttons[2]:nil;
    UIImage *image=C18Object(reference,@"glyphImage");
    CGRect ink=C18GlyphImageVisibleBounds(image);
    CGFloat side=CGRectIsNull(ink)?0:MAX(ink.size.width,ink.size.height);
    // Fixed primary items use glyphScale 1.0. Compare their visible ink, not
    // their transparent UIImage canvas or a hidden auxiliary item's scale.
    return isfinite(side) && side>0 && side<100?side:25.0;
}
static CGFloat C18GlyphLegacyTarget(C18FiveModuleHost *host) {
    NSArray *buttons=C18FiveGet(host.owner,@"_buttons");
    id reference=[buttons isKindOfClass:NSArray.class] && buttons.count>2?buttons[2]:nil;
    UIImage *image=C18Object(reference,@"glyphImage");
    CGFloat side=[image isKindOfClass:UIImage.class]?MAX(image.size.width,image.size.height):0;
    return isfinite(side) && side>0 && side<100?side:25.0;
}
static UIImage *C18BoundedGlyph(UIImage *source,CGFloat legacyTarget,CGFloat referenceInk) {
    CGRect ink=C18GlyphImageVisibleBounds(source);
    CGFloat desired=C18GlyphDesiredVisibleSide(MAX(ink.size.width,ink.size.height),
        MAX(source.size.width,source.size.height),legacyTarget,referenceInk);
    return desired>0?C18GlyphImageWithVisibleSide(source,desired):nil;
}
static void C18RestoreLiveGlyph(C18FiveModuleHost *host) {
    UIView *glyph=host.liveGlyph, *home=host.glyphHome;
    if (glyph && home && glyph.superview==host.glyphContainer) {
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        [UIView performWithoutAnimation:^{
            [home insertSubview:glyph atIndex:MIN(host.glyphHomeIndex,home.subviews.count)];
            glyph.bounds=host.glyphHomeBounds;
            glyph.transform=host.glyphHomeTransform; glyph.layer.transform=host.glyphHomeLayerTransform;
            glyph.center=host.glyphHomeCenter; glyph.autoresizingMask=host.glyphHomeAutoresizing;
            [NSLayoutConstraint activateConstraints:host.glyphHomeConstraints];
        }];
        [CATransaction commit]; [home setNeedsLayout];
    }
    // If UIKit already reparented the view, it owns the new geometry. Do not
    // overwrite it with a compact snapshot or pull it out of an expanded card.
    if (glyph) { host.sourceGlyph=nil; host.boundedGlyph=nil; }
    host.liveGlyph=nil; host.glyphHome=nil; host.glyphHomeConstraints=nil; host.glyphContainer.hidden=YES;
}
static NSArray<NSLayoutConstraint *> *C18GlyphParentConstraints(UIView *glyph) {
    NSMutableArray *result=[NSMutableArray array];
    for (UIView *parent=glyph.superview;parent;parent=parent.superview) for (NSLayoutConstraint *c in parent.constraints)
        if (c.active && (c.firstItem==glyph || c.secondItem==glyph)) [result addObject:c];
    return result;
}
static BOOL C18UseLiveGlyph(C18FiveModuleHost *host,UIView *glyph) {
    if (C18Expanded(host)) { C18RestoreLiveGlyph(host); return NO; }
    if (!glyph || !glyph.superview) { C18RestoreLiveGlyph(host); return NO; }
    CGRect ink=C18GlyphPackageVisibleBounds(glyph);
    if (CGRectIsNull(ink) || CGRectIsEmpty(ink)) { C18RestoreLiveGlyph(host); return NO; }
    if (host.liveGlyph!=glyph || glyph.superview!=host.glyphContainer) {
        C18RestoreLiveGlyph(host);
        if (!host.glyphContainer) {
            host.glyphContainer=[[UIView alloc] initWithFrame:CGRectZero];
            host.glyphContainer.userInteractionEnabled=NO; host.glyphContainer.backgroundColor=UIColor.clearColor;
            [host.roundButton addSubview:host.glyphContainer];
        }
        host.glyphHome=glyph.superview;host.glyphHomeIndex=[glyph.superview.subviews indexOfObjectIdenticalTo:glyph];
        host.glyphHomeTransform=glyph.transform;host.glyphHomeLayerTransform=glyph.layer.transform;
        host.glyphHomeCenter=glyph.center;host.glyphHomeBounds=glyph.bounds;
        host.glyphHomeAutoresizing=glyph.autoresizingMask;host.glyphHomeConstraints=C18GlyphParentConstraints(glyph);
        host.liveGlyph=glyph;
        [NSLayoutConstraint deactivateConstraints:host.glyphHomeConstraints];
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        [UIView performWithoutAnimation:^{ [host.glyphContainer addSubview:glyph]; glyph.autoresizingMask=UIViewAutoresizingNone; }];
        [CATransaction commit];
    }
    // Keep CCUICAPackageView.scale, its original transform and every animation
    // layer intact. Converting actual ink into our container includes all inner
    // package scale/sublayerTransform/anchorPoint values (including non-1 ones).
    CGRect painted=[glyph.layer convertRect:ink toLayer:host.glyphContainer.layer];
    CGFloat side=MAX(painted.size.width,painted.size.height);
    if (!isfinite(side) || side<=0 || !isfinite(painted.origin.x) || !isfinite(painted.origin.y)) { C18RestoreLiveGlyph(host); return NO; }
    CGFloat localSide=MAX(ink.size.width,ink.size.height),canvas=MAX(glyph.bounds.size.width,glyph.bounds.size.height);
    CGFloat target=C18GlyphDesiredVisibleSide(localSide,canvas,C18GlyphLegacyTarget(host),C18GlyphTarget(host));
    if (!isfinite(target) || target<=0) { C18RestoreLiveGlyph(host); return NO; }
    CGFloat scale=target/side;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    [UIView performWithoutAnimation:^{
        host.glyphContainer.transform=CGAffineTransformIdentity;
        host.glyphContainer.bounds=CGRectMake(0,0,side,side);
        CGPoint anchor=host.glyphContainer.layer.anchorPoint;
        host.glyphContainer.bounds=CGRectMake(CGRectGetMidX(painted)-anchor.x*side,CGRectGetMidY(painted)-anchor.y*side,side,side);
        host.glyphContainer.center=CGPointMake(CGRectGetMidX(host.roundButton.bounds),CGRectGetMidY(host.roundButton.bounds));
        host.glyphContainer.transform=CGAffineTransformMakeScale(scale,scale); host.glyphContainer.hidden=NO;
        C18Set(host.roundButton,@"setGlyphImage:",nil);
        [host.roundButton bringSubviewToFront:host.glyphContainer];
    }];
    [CATransaction commit]; return YES;
}
static void C18CompactSync(C18FiveModuleHost *host) {
    if (!C18FiveIsPresented() || !host || host.closed || host.syncing || !host.roundButton) return;
    host.syncing=YES;
    @try {
        id vc=C18Controller(host), module=C18Module(host), button=C18Button(host);
        C18Remember(button,host); C18Remember(vc,host); C18Remember(module,host);
        BOOL selected=C18State(button,@"isSelected",C18State(vc,@"isSelected",C18State(module,@"isSelected",NO)));
        BOOL enabled=C18State(button,@"isEnabled",C18State(vc,@"isEnabled",YES));
        host.roundButton.selected=selected; host.roundButton.enabled=enabled;
        NSArray *buttons=C18FiveGet(host.owner,@"_buttons");
        UIColor *color=[buttons isKindOfClass:NSArray.class] && buttons.count>2?C18Object(buttons[2],@"highlightColor"):nil;
        if ([color isKindOfClass:UIColor.class]) C18Set(host.roundButton,@"setHighlightColor:",color);
        if (C18Expanded(host)) { C18RestoreLiveGlyph(host); return; }
        // Use the module's visible native source, rather than its off-screen
        // UIImage alternative. Modules with an active package also expose a
        // small static glyph; preferring that image discarded the real sizing.
        UIView *package=C18GlyphPackageView(button);
        if (package && C18UseLiveGlyph(host,package)) return;
        C18RestoreLiveGlyph(host);
        UIImage *image=C18Glyph(host,selected);
        if (!image) image=C18GlyphFallbackForSlot(host.slotID);
        CGFloat reference=C18GlyphTarget(host),legacy=C18GlyphLegacyTarget(host);
        CGFloat metric=reference+legacy*1024;
        if (image && (host.sourceGlyph!=image || fabs(host.glyphSide-metric)>.01)) {
            host.sourceGlyph=image; host.glyphSide=metric; host.boundedGlyph=C18BoundedGlyph(image,legacy,reference);
            C18Set(host.roundButton,@"setGlyphImage:",host.boundedGlyph);
        }
        SEL scale=NSSelectorFromString(@"setGlyphScale:");
        if (C18Method(host.roundButton,scale,"v",@[@"d"])) ((void(*)(id,SEL,double))objc_msgSend)(host.roundButton,scale,1.0);
    } @finally { host.syncing=NO; }
}
static void C18Isolation(C18FiveModuleHost *host) {
    if (!host || host.closed || !host.moduleView) return;
    // Original surface remains untouched. Only its outer compact wrapper is
    // hidden; when Shell reparents content to its expanded container it is
    // fully visible, with the original platter/material and controller intact.
    host.moduleView.hidden=YES;
    host.moduleView.userInteractionEnabled=NO;
    C18CompactSync(host);
}
static void (*oLayout)(id,SEL), (*oRefresh)(id,SEL), (*oMove)(id,SEL), (*oPrepare)(id,SEL), (*oState)(id,SEL);
static void (*oExpanded)(id,SEL,BOOL);
static void (*oObserve)(id,SEL,NSString *,id,NSDictionary *,void *);
static BOOL (*oAppearance)(id,SEL);
static void C18NativeLayout(id self,SEL cmd) { if (oLayout) oLayout(self,cmd); C18Isolation(C18Owner(self)); }
static void C18NativeRefresh(id self,SEL cmd) { if (oRefresh) oRefresh(self,cmd); C18CompactSync(C18Owner(self)); }
static void C18NativeMove(id self,SEL cmd) { if (oMove) oMove(self,cmd); C18Isolation(C18Owner(self)); }
static void C18NativeState(id self,SEL cmd) { if (oState) oState(self,cmd); C18CompactSync(C18Owner(self)); }
static void C18NativePrepare(id self,SEL cmd) {
    C18RestoreLiveGlyph(C18Owner(self));
    if (oPrepare) oPrepare(self,cmd);
}
static void C18NativeExpanded(id self,SEL cmd,BOOL expanded) { if (oExpanded) oExpanded(self,cmd,expanded); C18Isolation(C18Owner(self)); }
static void C18NativeObserve(id self,SEL cmd,NSString *path,id object,NSDictionary *change,void *context) {
    if (oObserve) oObserve(self,cmd,path,object,change,context); C18CompactSync(C18Owner(self));
}
static BOOL C18NativeAppearance(id self,SEL cmd) {
    C18FiveModuleHost *host=C18Owner(self);
    if (!host) return oAppearance?oAppearance(self,cmd):NO;
    if (!gPresented || !C18FiveIsPresented()) return NO;
    if (C18Expanded(host)) return host.nativeHost.window && !host.closed;
    return gPresented && host.window && !host.hidden && !host.closed && host.alpha>.01;
}
void C18FiveInstallModuleHooks(void) {
    if (!gHosts) gHosts=[NSHashTable weakObjectsHashTable];
    Class cls=objc_getClass("C18ButtonModuleView"); if (!cls) return;
    static BOOL done[8];
    NSString *names[8]={@"layoutSubviews",@"refresh",@"didMoveToWindow",@"prepareToExpand",@"_toggleStateChanged",@"setExpanded:",@"observeValueForKeyPath:ofObject:change:context:",@"_wantsAppearance"};
    IMP hooks[8]={(IMP)C18NativeLayout,(IMP)C18NativeRefresh,(IMP)C18NativeMove,(IMP)C18NativePrepare,(IMP)C18NativeState,(IMP)C18NativeExpanded,(IMP)C18NativeObserve,(IMP)C18NativeAppearance};
    IMP *originals[8]={(IMP *)&oLayout,(IMP *)&oRefresh,(IMP *)&oMove,(IMP *)&oPrepare,(IMP *)&oState,(IMP *)&oExpanded,(IMP *)&oObserve,(IMP *)&oAppearance};
    for (NSUInteger i=0;i<8;i++) if (!done[i]) {
        SEL sel=NSSelectorFromString(names[i]); NSArray<NSString *> *args=i==5?@[@"B"]:i==6?@[@"@",@"@",@"@",@"^v"]:@[];
        if (!C18HookCanInstall(cls,sel,i==7?"B":"v",args)) continue;
        done[i]=YES; MSHookMessageEx(cls,sel,hooks[i],originals[i]);
    }
}
void C18FiveModulesSetPresented(BOOL presented) {
    gPresented=presented;
    for (C18FiveModuleHost *host in gHosts.allObjects) {
        if (presented && host.window && !host.hidden) [host refresh];
        else { C18RestoreLiveGlyph(host); C18Void(host.nativeHost,@"controlCenterDidDismiss"); }
    }
}
static BOOL C18HasSlider(UIView *view,NSUInteger depth) {
    if (!view || depth>8) return NO;
    NSString *name=NSStringFromClass(view.class).lowercaseString;
    if ([view isKindOfClass:UISlider.class] || [name containsString:@"slider"] || [name containsString:@"nowplaying"]) return YES;
    for (UIView *child in view.subviews) if (C18HasSlider(child,depth+1)) return YES;
    return NO;
}
@implementation C18FiveModuleHost
- (instancetype)initWithSlotID:(NSString *)slotID owner:(UIView *)owner {
    if (!C18FiveIsPresented() || !owner.window) return nil;
    if (!(self=[super initWithFrame:CGRectZero])) return nil;
    _slotID=[slotID copy]; _owner=owner; self.backgroundColor=UIColor.clearColor; self.clipsToBounds=NO;
    C18FiveInstallModuleHooks(); Class round=objc_getClass("C18RoundButton");
    if (round && [round isSubclassOfClass:UIControl.class]) self.roundButton=[(UIControl *)[round alloc] initWithFrame:CGRectZero];
    [self.roundButton addTarget:self action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];
    NSString *identifier=C18FiveModuleID(slotID); NSDictionary *entry=C18FiveEntry(slotID); id shell=C18Shell();
    SEL create=NSSelectorFromString(@"_instantiateModuleWithIdentifier:"),wrap=NSSelectorFromString(@"_makeModuleViewForIdentifier:size:instance:gallery:");
    @try {
        if (!identifier || !entry || C18FiveExcluded(identifier,entry[@"principal"])) self.failure=@"该项不支持圆形槽位";
        else if (!self.roundButton || !C18Method(shell,create,"@",@[@"@"]) || !C18Method(shell,wrap,"@",@[@"@",@"q",@"@",@"B"])) self.failure=@"原插件模块入口不可用";
        else {
            self.instance=((id(*)(id,SEL,id))objc_msgSend)(shell,create,identifier);
            id wrapper=self.instance?((id(*)(id,SEL,id,long long,id,BOOL))objc_msgSend)(shell,wrap,identifier,0,self.instance,NO):nil;
            UIView *native=C18Object(wrapper,@"contentView"); Class nativeClass=objc_getClass("C18ButtonModuleView");
            id vc=C18FiveGet(native,@"_vc"); UIView *probe=[vc isKindOfClass:UIViewController.class]?[(UIViewController *)vc viewIfLoaded]:nil;
            if (![wrapper isKindOfClass:UIView.class] || !nativeClass || ![native isKindOfClass:nativeClass]) self.failure=@"原模块未创建圆形内容";
            else if (C18HasSlider(probe,0)) self.failure=@"滑杆或播放器不支持圆形槽位";
            else {
                self.moduleView=wrapper; self.nativeHost=native; C18Remember(native,self);
                self.moduleView.hidden=YES; self.moduleView.userInteractionEnabled=NO;
                [self addSubview:self.moduleView]; [gHosts addObject:self];
                C18DataSwitchRegisterHost(C18Module(self),self);
            }
        }
    } @catch (__unused NSException *e) { self.failure=@"原模块初始化异常"; }
    if (self.roundButton) [self addSubview:self.roundButton];
    __weak C18FiveModuleHost *weakHost=self;
    C18PressAttach(self.roundButton,^BOOL{
        C18FiveModuleHost *host=weakHost;
        return host && [host canHold];
    },^{ [weakHost openNativePanel]; });
    if (self.failure) {
        self.roundButton.enabled=NO; self.instance=nil;
        UILabel *label=[[UILabel alloc] initWithFrame:self.bounds]; label.text=@"不可用"; label.font=[UIFont systemFontOfSize:10]; label.textColor=UIColor.secondaryLabelColor; label.textAlignment=NSTextAlignmentCenter;
        label.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; [self addSubview:label];
    }
    self.accessibilityLabel=entry[@"title"]?:identifier;
    if (identifier.length) {
        NSString *key=[@"Capability." stringByAppendingString:identifier]; NSDictionary *value=@{@"available":@(!self.failure),@"reason":self.failure?:@""};
        CFPreferencesSetAppValue((__bridge CFStringRef)key,(__bridge CFPropertyListRef)value,(__bridge CFStringRef)C18FiveDomain);
        CFPreferencesAppSynchronize((__bridge CFStringRef)C18FiveDomain);
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];if (!CGRectEqualToRect(self.roundButton.frame,self.bounds)) self.roundButton.frame=self.bounds;
    C18PressUpdate(self.roundButton,!self.closed && !self.failure && !C18Editing() && !C18Expanded(self));
    if (!C18Expanded(self)) {
        self.moduleView.transform=CGAffineTransformIdentity; self.moduleView.frame=self.bounds;
        [self.moduleView setNeedsLayout]; [self.moduleView layoutIfNeeded];
    }
    C18Isolation(self);
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window && gPresented) [self refresh];
    else if (!self.window) { C18RestoreLiveGlyph(self); C18Void(self.nativeHost,@"controlCenterDidDismiss"); }
}
- (BOOL)isDataSwitch { Class cls=objc_getClass("CCSwitchDataModuleViewController"); return cls && [C18Controller(self) isKindOfClass:cls]; }
- (void)tap:(id)sender {
    (void)sender; if (!C18FiveIsPresented() || C18Editing() || self.closed || self.failure) return;
    if (C18RateController(C18Controller(self))) { C18CellularRateOpenForController(C18Controller(self),self.nativeHost); return; }
    if ([self isDataSwitch]) { C18DataSwitchOpenForHost(self); return; }
    id button=C18Button(self); id vc=C18Controller(self); SEL action=NSSelectorFromString(@"buttonTapped:forEvent:");
    if (C18Method(vc,action,"v",@[@"@",@"@"])) ((void(*)(id,SEL,id,id))objc_msgSend)(vc,action,button,nil);
    else if ([button isKindOfClass:UIControl.class]) {
        UIControlEvents events=[(UIControl *)button allControlEvents];
        [(UIControl *)button sendActionsForControlEvents:(events&UIControlEventTouchUpInside)?UIControlEventTouchUpInside:UIControlEventPrimaryActionTriggered];
    } else {
        SEL selected=NSSelectorFromString(@"setSelected:"); id module=C18Module(self);
        if (C18Method(module,selected,"v",@[@"B"])) ((void(*)(id,SEL,BOOL))objc_msgSend)(module,selected,!C18State(module,@"isSelected",NO));
    }
    C18CompactSync(self);
}
- (BOOL)canHold {
    if (!C18FiveIsPresented() || self.closed || self.failure || !self.window || self.hidden || !self.userInteractionEnabled || C18Editing() || C18Expanded(self)) return NO;
    if (C18RateController(C18Controller(self)) || [self isDataSwitch] || C18State(self.nativeHost,@"hasContextMenu",NO) || C18State(self.nativeHost,@"canExpand",NO)) return YES;
    // Preserve explicitly supported controller long-press actions; a simple
    // toggle with no panel must never be toggled a second time by a hold.
    return C18Method(C18Controller(self),NSSelectorFromString(@"c18PerformLongPress"),"B",@[]);
}
- (void)openNativePanel {
    if (![self canHold]) return;
    if (C18RateController(C18Controller(self))) { C18CellularRateOpenForController(C18Controller(self),self.nativeHost); return; }
    if ([self isDataSwitch]) { C18DataSwitchOpenForHost(self); return; }
    if (C18State(self.nativeHost,@"hasContextMenu",NO)) {
        __weak C18FiveModuleHost *weakHost=self;
        C18PressPresentMenu(self.roundButton,^UIContextMenuConfiguration *(UIContextMenuInteraction *interaction,CGPoint point){
            return [weakHost contextMenuInteraction:interaction configurationForMenuAtLocation:point];
        });return;
    }
    if (C18State(self.nativeHost,@"canExpand",NO)) {
        SEL expand=NSSelectorFromString(@"expandModuleView:"); id shell=C18Shell();
        if (C18Method(shell,expand,"v",@[@"@"])) {
            ((void(*)(id,SEL,id))objc_msgSend)(shell,expand,self.moduleView);
            C18Isolation(self); return;
        }
    }
    // Preserve the native module's own c18PerformLongPress/tap fallback.
    C18Void(self.nativeHost,@"performTapFromLongPress"); C18CompactSync(self);
}
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction configurationForMenuAtLocation:(CGPoint)point {
    if (C18Editing() || self.closed || self.failure) return nil;
    if ([self isDataSwitch]) { C18DataSwitchOpenForHost(self); return nil; }
    if (!C18State(self.nativeHost,@"hasContextMenu",NO)) return nil;
    SEL configure=@selector(contextMenuInteraction:configurationForMenuAtLocation:);
    if (C18Method(self.nativeHost,configure,"@",@[@"@",@"{CGPoint=dd}"]))
        return ((id(*)(id,SEL,id,CGPoint))objc_msgSend)(self.nativeHost,configure,interaction,point);
    return nil;
}
- (id)c18ModuleInstance { return C18Module(self); }
- (void)refresh {
    if (!gPresented || !self.window || self.hidden || self.closed) return;
    C18Void(self.nativeHost,@"refresh"); C18Void(self.nativeHost,@"ensureAppeared"); C18CompactSync(self); C18Isolation(self);
}
- (void)close {
    if (self.closed) return;
    C18PressUpdate(self.roundButton,NO);C18RestoreLiveGlyph(self); self.closed=YES;
    C18Void(self.nativeHost,@"controlCenterDidDismiss");
    for (id object in @[self.nativeHost?:NSNull.null,C18Controller(self)?:NSNull.null,C18Module(self)?:NSNull.null,C18Button(self)?:NSNull.null])
        if (C18Owner(object)==self) objc_setAssociatedObject(object,&kModuleOwner,nil,OBJC_ASSOCIATION_ASSIGN);
    [self.moduleView removeFromSuperview]; self.moduleView=nil; self.nativeHost=nil; self.instance=nil; [self removeFromSuperview];
}
@end
