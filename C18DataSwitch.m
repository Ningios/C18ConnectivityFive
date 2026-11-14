#import "C18Five.h"
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import <string.h>
#import "C18HookRuntime.h"

extern void C18PowerMenuInstall(void);

// Shared beta6 providers are implemented by Modules/SIM; keep this unit standalone while they land.
extern UIView *C18FiveNativeMaterial(NSString *recipe);
extern void C18FiveResolveCarrierNames(id client,void (^completion)(NSDictionary<NSNumber *,NSString *> *names));

extern void MSHookMessageEx(Class, SEL, IMP, IMP *);

// Original arm64e: updatedMenuItems @16@0:8; buttonTapped v32@0:8@16@24.
// CCUIMenuModuleItem's native performAction dispatches its v8@?0 handler.
// Never cast that handler to a UIAlertAction block or replace the CT backend.
@interface C18DSWeakView : NSObject
@property(nonatomic,weak) UIView *view;
@end
@implementation C18DSWeakView @end

@interface C18DSItem : NSObject
@property(nonatomic,copy) NSString *name;
@property(nonatomic,copy) NSString *nativeTitle; // Original line label, never a carrier-name substitute.
@property(nonatomic) NSInteger slot;
@property(nonatomic,strong) id nativeItem;
@property(nonatomic,copy) void (^invoke)(void);
@property(nonatomic) BOOL active;
@end
@implementation C18DSItem @end

@interface C18DSRequest : NSObject
@property(nonatomic,weak) id module;
@property(nonatomic,weak) id shell;
@property(nonatomic,weak) UIViewController *presenter;
@property(nonatomic,strong) NSObject *token;
@property(nonatomic) CFTimeInterval started;
@property(nonatomic) NSUInteger sessionGeneration;
@property(nonatomic) BOOL consumed;
@end
@implementation C18DSRequest @end

typedef void (*C18DSPresentIMP)(id,SEL,UIViewController *,BOOL,void(^)(void));
@interface C18DSPresenterHook : NSObject {
@public C18DSPresentIMP original;
}
@property(nonatomic) Class owner;
@property(nonatomic) IMP replacement;
@end
@implementation C18DSPresenterHook @end
static NSMutableArray<C18DSPresenterHook *> *gDSPresenters;

@class C18DSController;
static char kDSHost, kDSGestures, kDSRequest, kDSLastOpen, kDSStyling;
static char kDSCarrierNames, kDSCarrierPending, kDSCarrierDate, kDSCarrierToken;
static char kDSRequestToken, kDSNativeTried;
static const char *C18DSUnqualified(const char *type);
static NSInvocation *C18DSInvocation(id object,NSString *name);
static BOOL C18DSInvokeAction(id object,BOOL invoke);
static NSString *C18DSMethodTypes(id object,NSString *name);
static void C18DSReject(NSString *reason,id controller,UIView *source,id item);
static UIImage *C18DSBoundedImage(UIImage *source);
static NSInteger C18DSSlot(id identifier);
static NSString *C18DSDisplayName(C18DSItem *item,NSDictionary<NSNumber *,NSString *> *names);
static void C18DSResolveNames(id controller);
static __thread void *gDSScope;
static BOOL gDSButtonDone, gDSItemsDone, gDSShellDone;
static BOOL gDSMoveDone, gDSLayoutDone, gDSLongDone, gDSContextDone, gDSConfigurationDone;
static BOOL gDSAlertDone;
static void (*gDSButtonOriginal)(id,SEL,id,id);
static id (*gDSItemsOriginal)(id,SEL);
static void (*gDSShellOriginal)(id,SEL,id);
static void (*gDSMoveOriginal)(id,SEL);
static void (*gDSLayoutOriginal)(id,SEL);
static void (*gDSLongOriginal)(id,SEL);
static void (*gDSContextOriginal)(id,SEL);
static id (*gDSConfigurationOriginal)(id,SEL,id,CGPoint);
static UIAlertController *(*gDSAlertOriginal)(id,SEL,NSString *,NSString *,UIAlertControllerStyle);
static void C18DSPresent(C18DSPresenterHook *hook,id self,UIViewController *controller,BOOL animated,void (^completion)(void));
static BOOL C18DSInstallPresenter(UIViewController *presenter);
static BOOL C18DSPrepareCapture(C18DSRequest *request);
static BOOL C18DSRequestLive(C18DSRequest *request);

static BOOL C18DSType(const char *actual,const char *expected);
static BOOL C18DSMatch(Method method,const char *result,NSArray<NSString *> *arguments);
static NSString *C18DSText(id value);
static void C18DSButtonTapped(id self,SEL cmd,id sender,id event);
static id C18DSUpdatedItems(id self,SEL cmd);
static void C18DSShellExpand(id self,SEL cmd,id moduleView);
static void C18DSNativeMoved(id self,SEL cmd);
static void C18DSNativeLayout(id self,SEL cmd);
static void C18DSNativeLong(id self,SEL cmd);
static void C18DSNativeContext(id self,SEL cmd);
static id C18DSNativeConfiguration(id self,SEL cmd,id interaction,CGPoint point);
static UIAlertController *C18DSAlertCreate(id self,SEL cmd,NSString *title,NSString *message,UIAlertControllerStyle style);
void C18DataSwitchActivate(void);
static id C18DSObject(id object,NSString *selector);
static BOOL C18DSReadBool(id object,NSString *selector,BOOL *value);
static BOOL C18DSIsController(id object);
static id C18DSControllerForView(UIView *view);
static UIView *C18DSSource(id controller,UIView *hint);
static id C18DSShell(void);
static BOOL C18DSEditing(void);
static UIImage *C18DSGlyph(void);
static void C18DSApplyAppearance(id controller);
static NSArray<C18DSItem *> *C18DSReadItems(id controller);
static BOOL C18DSOpen(id controller,UIView *source);
static void C18DSInstallOnView(UIView *view);
static void C18DSInstallHooks(void);

// Check the complete explicit argument list, not just method availability.
static BOOL C18DSType(const char *actual,const char *expected) {
    if (!actual || !expected) return NO;
    while (*actual && strchr("rnNoORV",*actual)) actual++;
    if (!strcmp(expected,"@")) return actual[0]=='@' && actual[1]!='?';
    return !strcmp(actual,expected);
}
static BOOL C18DSMatch(Method method,const char *result,NSArray<NSString *> *arguments) {
    return C18HookSignatureMatches(method,result,arguments);
}
static const char *C18DSUnqualified(const char *type) {
    if (type) while (*type && strchr("rnNoORV",*type)) type++;
    return type ?: "";
}
static NSInvocation *C18DSInvocation(id object,NSString *name) {
    SEL selector=NSSelectorFromString(name);
    if (!object || ![object respondsToSelector:selector]) return nil;
    NSMethodSignature *signature=[object methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments!=2) return nil;
    NSInvocation *invocation=[NSInvocation invocationWithMethodSignature:signature];
    invocation.target=object; invocation.selector=selector; return invocation;
}
static id C18DSObject(id object,NSString *name) {
    @try {
        NSInvocation *invocation=C18DSInvocation(object,name); if (!invocation) return nil;
        NSMethodSignature *signature=invocation.methodSignature;
        if (!C18DSType(C18DSUnqualified(signature.methodReturnType),"@") || signature.methodReturnLength!=sizeof(id)) return nil;
        [invocation invoke]; __unsafe_unretained id result=nil; [invocation getReturnValue:&result]; return result;
    } @catch (__unused NSException *exception) { return nil; }
}
static BOOL C18DSReadBool(id object,NSString *name,BOOL *value) {
    @try {
        NSInvocation *invocation=C18DSInvocation(object,name); if (!invocation) return NO;
        NSMethodSignature *signature=invocation.methodSignature;
        const char *type=C18DSUnqualified(signature.methodReturnType); BOOL result=NO;
        if (C18DSType(type,"@")) {
            id number=C18DSObject(object,name); if (![number isKindOfClass:NSNumber.class]) return NO;
            result=[number boolValue];
        } else {
            if (!type[0] || type[1] || !strchr("BcCsSiIlLqQ",type[0])) return NO;
            [invocation invoke];
#define C18_DS_BOOL_CASE(code, ctype) case code: { ctype number=0; if (signature.methodReturnLength!=sizeof(number)) return NO; [invocation getReturnValue:&number]; result=number!=0; break; }
            switch (type[0]) {
                C18_DS_BOOL_CASE('B', _Bool)
                C18_DS_BOOL_CASE('c', signed char) C18_DS_BOOL_CASE('C', unsigned char)
                C18_DS_BOOL_CASE('s', short) C18_DS_BOOL_CASE('S', unsigned short)
                C18_DS_BOOL_CASE('i', int) C18_DS_BOOL_CASE('I', unsigned int)
                C18_DS_BOOL_CASE('l', long) C18_DS_BOOL_CASE('L', unsigned long)
                C18_DS_BOOL_CASE('q', long long) C18_DS_BOOL_CASE('Q', unsigned long long)
                default: return NO;
            }
#undef C18_DS_BOOL_CASE
        }
        if (value) *value=result; return YES;
    } @catch (__unused NSException *exception) { return NO; }
}
static BOOL C18DSInvokeAction(id object,BOOL invoke) {
    @try {
        NSInvocation *invocation=C18DSInvocation(object,@"performAction"); if (!invocation) return NO;
        const char *type=C18DSUnqualified(invocation.methodSignature.methodReturnType);
        // Accept only zero-argument, void/object/integer returns. NSInvocation owns the ABI.
        if (!C18DSType(type,"@") && !(type[0] && !type[1] && strchr("vBcCsSiIlLqQ",type[0]))) return NO;
        if (invoke) [invocation invoke]; return YES;
    } @catch (__unused NSException *exception) { return NO; }
}
static NSString *C18DSMethodTypes(id object,NSString *name) {
    Method method=class_getInstanceMethod(object_getClass(object),NSSelectorFromString(name));
    const char *types=method?method_getTypeEncoding(method):NULL;
    return types?[NSString stringWithUTF8String:types]:@"missing";
}
static void C18DSReject(NSString *reason,id controller,UIView *source,id item) {
    // No line identifiers, titles, carrier names, numbers or object descriptions in logs.
    static NSUInteger emitted; if (emitted>=24) return; emitted++;
    NSLog(@"[C18DS] Open reject=%@ controller=%@ source=%@ item=%@ updated=%@ menu=%@ title=%@ selected=%@ action=%@",
          reason,controller?NSStringFromClass([controller class]):@"nil",source?NSStringFromClass(source.class):@"nil",
          item?NSStringFromClass([item class]):@"nil",C18DSMethodTypes(controller,@"updatedMenuItems"),
          C18DSMethodTypes(controller,@"_menuItems"),C18DSMethodTypes(item,@"title"),
          C18DSMethodTypes(item,@"isSelected"),C18DSMethodTypes(item,@"performAction"));
}
static NSString *C18DSText(id value) {
    return [value isKindOfClass:NSString.class] && [value length] ? value : nil;
}
static BOOL C18DSIsController(id object) {
    Class cls=objc_getClass("CCSwitchDataModuleViewController"); return object && cls && [object isKindOfClass:cls];
}
static id C18DSShell(void) {
    // These accessors never materialize a singleton; prepare/visible owns the weak live shell.
    return NSThread.isMainThread && C18FiveIsPresented() ? C18FiveLiveShell() : nil;
}
static BOOL C18DSEditing(void) {
    BOOL editing=NO; C18DSReadBool(C18DSShell(),@"isEditing",&editing); return editing;
}
static id C18DSControllerForView(UIView *view) {
    if (!C18DSShell() || ![view isKindOfClass:UIView.class]) return nil;
    if ([view isKindOfClass:C18FiveModuleHost.class]) {
        UIView *native=[(C18FiveModuleHost *)view nativeHost];
        // Only the already-created native controller; module.contentViewController can instantiate.
        return native!=view ? C18DSControllerForView(native) : nil;
    }
    // _vc is an object ivar in C18ButtonModuleView (native offset table 0x100970).
    Class native=objc_getClass("C18ButtonModuleView");
    if (native && [view isKindOfClass:native]) {
        Ivar ivar=class_getInstanceVariable(object_getClass(view),"_vc");
        id controller=ivar && C18HookTypeMatches(ivar_getTypeEncoding(ivar),"@") ? object_getIvar(view,ivar) : nil;
        return C18DSIsController(controller)?controller:nil;
    }
    id content=C18DSObject(view,@"contentView");
    return [content isKindOfClass:UIView.class] && content!=view ? C18DSControllerForView(content) : nil;
}
static UIView *C18DSSource(id controller,UIView *hint) {
    // C18Shell expects a C18ModuleView wrapper, including wrappers embedded in four/five slots.
    Class wrapper=objc_getClass("C18ModuleView");
    C18DSWeakView *reference=objc_getAssociatedObject(controller,&kDSHost);
    UIView *start=hint ?: reference.view;
    if ([start isKindOfClass:C18FiveModuleHost.class]) start=[(C18FiveModuleHost *)start nativeHost];
    if (!start && [controller isKindOfClass:UIViewController.class]) start=[(UIViewController *)controller viewIfLoaded];
    for (UIView *view=start;view;view=view.superview) if (wrapper && [view isKindOfClass:wrapper]) return view;
    id views=C18DSObject(C18DSShell(),@"moduleViews");
    if ([views isKindOfClass:NSArray.class]) for (id view in views) {
        if (wrapper && [view isKindOfClass:wrapper] && C18DSControllerForView(view)==controller) return view;
    }
    return nil;
}
static UIImage *C18DSBoundedImage(UIImage *source) {
    if (!source || source.size.width<=0 || source.size.height<=0) return nil;
    CGSize target=CGSizeMake(32,32),size=source.size;
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat preferredFormat];
    format.opaque=NO; format.scale=MAX(1,UIScreen.mainScreen.scale);
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:target format:format];
    CGFloat factor=MIN(target.width/size.width,target.height/size.height);
    CGSize fit=CGSizeMake(size.width*factor,size.height*factor);
    UIImage *bounded=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [source drawInRect:CGRectMake((target.width-fit.width)*.5,(target.height-fit.height)*.5,fit.width,fit.height)];
    }];
    return [bounded imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}
static UIImage *C18DSGlyph(void) {
    static UIImage *image; if (image) return image;
    Dl_info info={0}; NSMutableArray<NSString *> *paths=[NSMutableArray array];
    if (dladdr((const void *)&C18DSGlyph,&info) && info.dli_fname) {
        NSString *directory=[[NSString stringWithUTF8String:info.dli_fname] stringByDeletingLastPathComponent];
        [paths addObject:[directory stringByAppendingPathComponent:@"C18DataSwitchGlyph.png"]];
        [paths addObject:[directory stringByAppendingPathComponent:@"Resources/C18DataSwitchGlyph.png"]];
    }
    [paths addObject:@"/Library/MobileSubstrate/DynamicLibraries/C18DataSwitchGlyph.png"];
    for (NSString *path in paths) { image=[UIImage imageWithContentsOfFile:path]; if (image) break; }
    // Retry a missing resource on the next appearance; never cache the fallback.
    if (image) image=C18DSBoundedImage(image);
    static UIImage *fallback;
    if (!image && !fallback) fallback=C18DSBoundedImage([UIImage systemImageNamed:@"simcard"]);
    return image ?: fallback;
}
static void C18DSApplyAppearance(id controller) {
    if (!C18DSShell() || !C18DSIsController(controller) || [objc_getAssociatedObject(controller,&kDSStyling) boolValue]) return;
    // The compact glyph is loaded correctly by the original module initializer
    // from CCSwitchData.png/@2x/@3x. Never replace it after the button is visible.
    objc_setAssociatedObject(controller,&kDSStyling,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        if ([controller isKindOfClass:UIViewController.class] && ![[(UIViewController *)controller title] isEqualToString:@"数据切换"])
            [(UIViewController *)controller setTitle:@"数据切换"];
        SEL selector=NSSelectorFromString(@"setSelectedGlyphColor:");
        if (C18DSMatch(class_getInstanceMethod(object_getClass(controller),selector),"v",@[@"@"]))
            ((void(*)(id,SEL,id))objc_msgSend)(controller,selector,UIColor.whiteColor);
    } @finally { objc_setAssociatedObject(controller,&kDSStyling,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
}
static NSInteger C18DSSlot(id identifier) {
    // arm64e updatedMenuItems: 0x10f80 -> SIM1, 0x10fa0 -> SIM2 (decoded 0x8884 XOR constants).
    if ([identifier isKindOfClass:NSString.class]) {
        if ([identifier isEqualToString:@"SIM1"]) return 1;
        if ([identifier isEqualToString:@"SIM2"]) return 2;
    }
    return 0;
}
static NSString *C18DSDisplayName(C18DSItem *item,NSDictionary<NSNumber *,NSString *> *names) {
    if (item.slot<1 || item.slot>2) return @"运营商未知";
    NSString *name=C18DSText(names[@(item.slot)]);
    // nativeTitle remains available for line identity/accessibility, never promoted to carrier data.
    return name ?: (names?@"运营商未知":@"运营商读取中");
}
static NSArray<C18DSItem *> *C18DSReadItems(id controller) {
    if (!C18DSIsController(controller)) return nil;
    id rawItems=C18DSObject(controller,@"updatedMenuItems");
    if (![rawItems isKindOfClass:NSArray.class] || ![rawItems count]) rawItems=C18DSObject(controller,@"_menuItems");
    if (![rawItems isKindOfClass:NSArray.class] || ![rawItems count]) {
        C18DSReject(@"items-unavailable",controller,nil,nil); return nil;
    }
    NSMutableArray<C18DSItem *> *items=[NSMutableArray array]; BOOL filtered=NO;
    for (id raw in rawItems) {
        BOOL placeholder=NO; C18DSReadBool(raw,@"isPlaceholder",&placeholder);
        if (placeholder) { filtered=YES; continue; }
        BOOL selected=NO; NSString *title=C18DSText(C18DSObject(raw,@"title"));
        if (!title || !C18DSReadBool(raw,@"isSelected",&selected) || !C18DSInvokeAction(raw,NO)) {
            C18DSReject(@"item-signature",controller,nil,raw); return nil;
        }
        C18DSItem *item=[C18DSItem new]; item.nativeTitle=title; item.active=selected; item.nativeItem=raw;
        item.slot=C18DSSlot(C18DSObject(raw,@"identifier"));
        item.invoke=^{ C18DSInvokeAction(raw,YES); }; [items addObject:item];
    }
    // Only the complete, unfiltered pair has the original slot1/slot2 construction order.
    if (!filtered && [rawItems count]==2 && items.count==2 &&
        (!items[0].slot || items[0].slot==1) && (!items[1].slot || items[1].slot==2)) {
        items[0].slot=1; items[1].slot=2;
    }
    NSDictionary *names=objc_getAssociatedObject(controller,&kDSCarrierNames);
    for (C18DSItem *item in items) item.name=C18DSDisplayName(item,names);
    if (items.count) C18DSResolveNames(controller);
    return items.count ? items : nil;
}

@interface C18DSRow : UIControl
@property(nonatomic,strong) UILabel *badge;
@property(nonatomic,strong) UILabel *carrier;
- (instancetype)initWithItem:(C18DSItem *)item;
@end
@implementation C18DSRow
- (instancetype)initWithItem:(C18DSItem *)item {
    if (!(self=[super initWithFrame:CGRectZero])) return nil;
    _badge=[UILabel new]; _badge.text=item.active?@"使用中":@"未选用";
    _badge.textAlignment=NSTextAlignmentCenter; _badge.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _badge.textColor=UIColor.whiteColor;
    _badge.backgroundColor=item.active?[UIColor colorWithRed:.20 green:.78 blue:.35 alpha:1]:[UIColor colorWithWhite:1 alpha:.16];
    _badge.layer.cornerRadius=12; _badge.layer.cornerCurve=kCACornerCurveContinuous; _badge.clipsToBounds=YES;
    _carrier=[UILabel new]; _carrier.text=C18DSText(item.name) ?: C18DSDisplayName(item,nil); _carrier.textColor=UIColor.whiteColor;
    _carrier.font=[UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    _carrier.adjustsFontSizeToFitWidth=YES; _carrier.minimumScaleFactor=.65;
    [self addSubview:_badge]; [self addSubview:_carrier];
    self.isAccessibilityElement=YES; self.accessibilityTraits=UIAccessibilityTraitButton|(item.active?UIAccessibilityTraitSelected:0);
    NSString *identity=item.slot?[NSString stringWithFormat:@"SIM%ld",(long)item.slot]:(item.nativeTitle ?: @"线路");
    self.accessibilityLabel=[NSString stringWithFormat:@"%@，%@，%@",_carrier.text,identity,_badge.text]; return self;
}
- (void)layoutSubviews {
    [super layoutSubviews]; CGFloat w=self.bounds.size.width,h=self.bounds.size.height,gap=12;
    CGFloat bw=MAX(64,ceil([self.badge sizeThatFits:CGSizeMake(CGFLOAT_MAX,24)].width)+20);
    CGFloat cw=MIN(ceil([self.carrier sizeThatFits:CGSizeMake(CGFLOAT_MAX,h)].width),MAX(0,w-40-bw-gap));
    CGFloat x=MAX(0,(w-bw-gap-cw)*.5);
    self.badge.frame=CGRectMake(x,(h-24)*.5,bw,24); self.carrier.frame=CGRectMake(x+bw+gap,0,cw,h);
}
- (void)setHighlighted:(BOOL)value { [super setHighlighted:value]; self.alpha=value?.65:1; }
@end

@interface C18DSController : UIViewController
@property(nonatomic,strong) NSArray<C18DSItem *> *items;
@property(nonatomic,weak) id dataController;
@property(nonatomic,weak) UIView *source;
@property(nonatomic,strong) UIView *material;
@property(nonatomic,strong) UIImageView *icon;
@property(nonatomic,strong) UILabel *heading;
@property(nonatomic,strong) UIView *divider;
@property(nonatomic,strong) UIScrollView *list;
@property(nonatomic,strong) NSArray<C18DSRow *> *rows;
@property(nonatomic,strong) NSTimer *refreshTimer;
@property(nonatomic) BOOL invoked;
- (void)reloadRows;
- (void)refreshState:(NSTimer *)timer;
- (void)selectRow:(C18DSRow *)row;
@end
@implementation C18DSController
- (CGFloat)preferredExpandedContentHeight { return 104+62*MIN((NSUInteger)5,self.items.count); }
- (void)loadView {
    self.title=@"数据切换";
    self.preferredContentSize=CGSizeMake(336,[self preferredExpandedContentHeight]);
    UIView *view=[[UIView alloc] initWithFrame:(CGRect){CGPointZero,self.preferredContentSize}]; self.view=view;
    view.backgroundColor=UIColor.clearColor; view.layer.cornerRadius=44;
    view.layer.cornerCurve=kCACornerCurveContinuous; view.clipsToBounds=YES;
    _material=C18FiveNativeMaterial(@"modulesSheer");
    _material.userInteractionEnabled=NO; if (_material) [view addSubview:_material];
    _icon=[[UIImageView alloc] initWithImage:C18DSGlyph()]; _icon.tintColor=UIColor.whiteColor;
    _icon.contentMode=UIViewContentModeScaleAspectFit; [view addSubview:_icon];
    _heading=[UILabel new]; _heading.text=@"数据切换"; _heading.textColor=UIColor.whiteColor;
    _heading.textAlignment=NSTextAlignmentCenter; _heading.font=[UIFont systemFontOfSize:18 weight:UIFontWeightSemibold]; [view addSubview:_heading];
    _divider=[UIView new]; _divider.backgroundColor=[UIColor colorWithWhite:1 alpha:.25]; [view addSubview:_divider];
    _list=[UIScrollView new]; _list.alwaysBounceVertical=NO; [view addSubview:_list]; [self reloadRows];
}
- (void)reloadRows {
    for (UIView *row in self.rows) [row removeFromSuperview];
    NSMutableArray *rows=[NSMutableArray array];
    for (NSUInteger index=0;index<self.items.count;index++) {
        C18DSRow *row=[[C18DSRow alloc] initWithItem:self.items[index]]; row.tag=index;
        [row addTarget:self action:@selector(selectRow:) forControlEvents:UIControlEventTouchUpInside];
        [self.list addSubview:row]; [rows addObject:row];
    }
    self.rows=rows; self.preferredContentSize=CGSizeMake(336,[self preferredExpandedContentHeight]); [self.view setNeedsLayout];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews]; CGFloat w=self.view.bounds.size.width,h=self.view.bounds.size.height;
    CGFloat scale=self.view.window.screen.scale ?: UIScreen.mainScreen.scale;
    self.material.frame=self.view.bounds; self.icon.frame=CGRectMake((w-32)*.5,20,32,32);
    self.heading.frame=CGRectMake(16,62,w-32,27); self.divider.frame=CGRectMake(0,102,w,1/MAX(1,scale));
    self.list.frame=CGRectMake(0,104,w,MAX(0,h-104));
    CGFloat rowHeight=MAX(56,MIN(66,MAX(0,h-104)/MAX((NSUInteger)1,self.rows.count)));
    self.list.contentSize=CGSizeMake(w,rowHeight*self.rows.count);
    for (NSUInteger i=0;i<self.rows.count;i++) self.rows[i].frame=CGRectMake(0,i*rowHeight,w,rowHeight);
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated]; [self.refreshTimer invalidate]; __weak C18DSController *weakSelf=self;
    self.refreshTimer=[NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) { [weakSelf refreshState:timer]; }];
}
- (void)viewWillDisappear:(BOOL)animated {
    [self.refreshTimer invalidate]; self.refreshTimer=nil; [super viewWillDisappear:animated];
}
- (void)refreshState:(NSTimer *)timer {
    if (self.invoked || !self.view.window) { [timer invalidate]; return; }
    NSArray<C18DSItem *> *fresh=C18DSReadItems(self.dataController); if (!fresh.count) return;
    BOOL changed=fresh.count!=self.items.count;
    for (NSUInteger i=0;!changed && i<fresh.count;i++)
        changed=fresh[i].active!=self.items[i].active || fresh[i].slot!=self.items[i].slot ||
            ![fresh[i].name isEqualToString:self.items[i].name] || ![fresh[i].nativeTitle isEqualToString:self.items[i].nativeTitle];
    self.items=fresh; if (changed) [self reloadRows];
}
- (void)selectRow:(C18DSRow *)row {
    if (self.invoked || row.tag<0 || (NSUInteger)row.tag>=self.items.count) return;
    C18DSItem *item=self.items[row.tag]; if (!item.invoke) return;
    self.invoked=YES; [self.refreshTimer invalidate]; self.list.userInteractionEnabled=NO;
    // Keep the original item alive until its native handler runs, even while dismissing the panel.
    void (^invoke)(void)=[item.invoke copy]; id controller=self.dataController; __weak UIView *source=self.source;
    NSUInteger session=C18FivePresentationGeneration();
    id shell=C18DSShell(); SEL dismiss=NSSelectorFromString(@"dismissMenu");
    if (C18DSMatch(class_getInstanceMethod(object_getClass(shell),dismiss),"v",@[]))
        ((void(*)(id,SEL))objc_msgSend)(shell,dismiss);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,350*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        invoke();
        if (!session || session!=C18FivePresentationGeneration()) return;
        C18DSApplyAppearance(controller);
        // Read back native state on the next open, never optimistically swap the selected line.
        SEL refresh=NSSelectorFromString(@"refresh"); id native=source;
        if ([native isKindOfClass:UIView.class]) native=C18DSObject(native,@"contentView");
        if (C18DSMatch(class_getInstanceMethod(object_getClass(native),refresh),"v",@[]))
            ((void(*)(id,SEL))objc_msgSend)(native,refresh);
    });
}
- (void)dealloc { [_refreshTimer invalidate]; }
@end

static void C18DSResolveNames(id controller) {
    if (!controller || [objc_getAssociatedObject(controller,&kDSCarrierPending) boolValue]) return;
    NSNumber *last=objc_getAssociatedObject(controller,&kDSCarrierDate);
    if (last && CACurrentMediaTime()-last.doubleValue<15) return;
    NSObject *token=[NSObject new];NSUInteger session=C18FivePresentationGeneration();
    objc_setAssociatedObject(controller,&kDSCarrierToken,token,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(controller,&kDSCarrierPending,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    id client=C18DSObject(controller,@"coreTelephonyClient"); __weak id weakController=controller;
    C18FiveResolveCarrierNames(client,^(NSDictionary<NSNumber *,NSString *> *names) {
        dispatch_block_t apply=^{
            id owner=weakController; if (!owner || objc_getAssociatedObject(owner,&kDSCarrierToken)!=token) return;
            NSMutableDictionary *valid=[NSMutableDictionary dictionary];
            for (NSNumber *slot in @[@1,@2]) {
                NSString *name=C18DSText(names[slot]); if (name) valid[slot]=name;
            }
            objc_setAssociatedObject(owner,&kDSCarrierNames,[valid copy],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(owner,&kDSCarrierDate,@(CACurrentMediaTime()),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(owner,&kDSCarrierPending,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (!session || session!=C18FivePresentationGeneration()) return;
            id panel=C18FiveGet(C18DSShell(),@"_menuController");
            if ([panel isKindOfClass:C18DSController.class] && [(C18DSController *)panel dataController]==owner) {
                for (C18DSItem *item in [(C18DSController *)panel items]) item.name=C18DSDisplayName(item,valid);
                if ([(C18DSController *)panel isViewLoaded]) [(C18DSController *)panel reloadRows];
            }
        };
        if (NSThread.isMainThread) apply(); else dispatch_async(dispatch_get_main_queue(),apply);
    });
}
static BOOL C18DSOpen(id controller,UIView *hint) {
    if (!controller) return NO; // Other modules also traverse the shared shell hook.
    if (!C18DSShell() || !C18DSIsController(controller) || C18DSEditing()) {
        C18DSReject(@"thread-controller-editing",controller,hint,nil); return NO;
    }
    id shell=C18DSShell(); SEL present=NSSelectorFromString(@"presentMenuViewController:fromModuleView:");
    if (!C18DSMatch(class_getInstanceMethod(object_getClass(shell),present),"v",@[@"@",@"@"])) {
        C18DSReject(@"shell-present-signature",controller,hint,nil); return NO;
    }
    id existing=C18FiveGet(shell,@"_menuController");
    // Only consume duplicate input when our panel actually belongs to this native controller.
    if ([existing isKindOfClass:C18DSController.class] && [(C18DSController *)existing dataController]==controller) return YES;
    if (existing) { C18DSReject(@"shell-menu-busy",controller,hint,existing); return NO; }
    UIView *source=C18DSSource(controller,hint);
    if (!source) { C18DSReject(@"source-wrapper-missing",controller,hint,nil); return NO; }
    NSArray<C18DSItem *> *items=C18DSReadItems(controller);
    if (!items.count) { C18DSReject(@"no-valid-items",controller,source,nil); return NO; }
    C18DSController *panel=[C18DSController new]; panel.items=items; panel.dataController=controller; panel.source=source;
    C18DSApplyAppearance(controller);
    ((void(*)(id,SEL,id,id))objc_msgSend)(shell,present,panel,source);
    BOOL shown=C18FiveGet(shell,@"_menuController")==panel;
    if (shown) objc_setAssociatedObject(controller,&kDSLastOpen,@(CACurrentMediaTime()),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    else C18DSReject(@"shell-did-not-accept-panel",controller,source,panel);
    return shown;
}

@interface C18DSGestureTarget : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic,weak) UIView *view;
- (void)tap:(UITapGestureRecognizer *)gesture;
- (void)press:(UILongPressGestureRecognizer *)gesture;
- (void)open;
@end
@implementation C18DSGestureTarget
- (void)open {
    if ([self.view isKindOfClass:C18FiveModuleHost.class]) {
        C18DataSwitchOpenForHost((C18FiveModuleHost *)self.view); return;
    }
    id controller=C18DSControllerForView(self.view);
    if (!controller || C18DSEditing() || C18DSOpen(controller,self.view)) return;
    SEL selector=NSSelectorFromString(@"buttonTapped:forEvent:");
    if (C18DSMatch(class_getInstanceMethod(object_getClass(controller),selector),"v",@[@"@",@"@"]))
        ((void(*)(id,SEL,id,id))objc_msgSend)(controller,selector,nil,nil);
}
- (void)tap:(UITapGestureRecognizer *)gesture {
    if (gesture.state==UIGestureRecognizerStateRecognized) [self open];
}
- (void)press:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state==UIGestureRecognizerStateBegan) [self open];
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    return !C18DSEditing() && self.view.window && C18DSIsController(C18DSControllerForView(self.view));
}
@end
static void C18DSInstallOnView(UIView *view) {
    id controller=C18DSControllerForView(view); if (!controller) return;
    if (!gDSButtonDone || !gDSItemsDone) C18DSInstallHooks();
    C18DSApplyAppearance(controller);
    // A native host already inside a custom four/five-key host is handled by the outer host.
    if (![view isKindOfClass:C18FiveModuleHost.class])
        for (UIView *parent=view.superview;parent;parent=parent.superview)
            if ([parent isKindOfClass:C18FiveModuleHost.class]) return;
    if (objc_getAssociatedObject(view,&kDSGestures)) return;
    C18DSGestureTarget *target=[C18DSGestureTarget new]; target.view=view;
    UILongPressGestureRecognizer *press=[[UILongPressGestureRecognizer alloc] initWithTarget:target action:@selector(press:)];
    press.minimumPressDuration=.45; press.cancelsTouchesInView=YES; press.delegate=target;
    UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] initWithTarget:target action:@selector(tap:)];
    tap.cancelsTouchesInView=YES; tap.delegate=target; [tap requireGestureRecognizerToFail:press];
    [view addGestureRecognizer:press]; [view addGestureRecognizer:tap];
    objc_setAssociatedObject(view,&kDSGestures,target,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void C18DSButtonTapped(id self,SEL cmd,id sender,id event) {
    if (!C18DSShell() || !C18DSIsController(self)) {
        if (gDSButtonOriginal) gDSButtonOriginal(self,cmd,sender,event); return;
    }
    C18DSInstallHooks();
    if (C18DSEditing() || C18DSOpen(self,nil)) return;
    C18DSRequest *request=[C18DSRequest new]; request.module=self; request.shell=C18DSShell();
    request.started=CACurrentMediaTime(); request.token=[NSObject new];request.sessionGeneration=C18FivePresentationGeneration();
    objc_setAssociatedObject(self,&kDSRequestToken,request.token,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BOOL capture=C18DSPrepareCapture(request);
    void *previous=gDSScope; gDSScope=capture?(__bridge void *)request:NULL;
    @try { if (gDSButtonOriginal) gDSButtonOriginal(self,cmd,sender,event); }
    @finally { gDSScope=previous; if (request.consumed && objc_getAssociatedObject(self,&kDSRequestToken)==request.token) objc_setAssociatedObject(self,&kDSRequestToken,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
}
static id C18DSUpdatedItems(id self,SEL cmd) {
    id items=gDSItemsOriginal?gDSItemsOriginal(self,cmd):nil;
    C18DSApplyAppearance(self); return items;
}
static void C18DSShellExpand(id self,SEL cmd,id moduleView) {
    id controller=self==C18DSShell() && [moduleView isKindOfClass:UIView.class]?C18DSControllerForView(moduleView):nil;
    if (controller && C18DSOpen(controller,moduleView)) return;
    if (gDSShellOriginal) gDSShellOriginal(self,cmd,moduleView);
}
static void C18DSNativeTry(UIView *view) {
    id shell=C18DSShell(); if (!shell || !view.window) return;
    C18DSWeakView *tried=objc_getAssociatedObject(view,&kDSNativeTried);
    if (tried.view==(id)shell) return;
    if (!C18DSControllerForView(view)) return;
    C18DSInstallOnView(view);
    if (!objc_getAssociatedObject(view,&kDSGestures)) return;
    tried=[C18DSWeakView new]; tried.view=(id)shell;
    objc_setAssociatedObject(view,&kDSNativeTried,tried,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void C18DSNativeMoved(id self,SEL cmd) {
    if (gDSMoveOriginal) gDSMoveOriginal(self,cmd);
    if ([self isKindOfClass:UIView.class]) C18DSNativeTry(self);
}
static void C18DSNativeLayout(id self,SEL cmd) {
    if (gDSLayoutOriginal) gDSLayoutOriginal(self,cmd);
    if ([self isKindOfClass:UIView.class]) C18DSNativeTry(self);
}
static void C18DSNativeLong(id self,SEL cmd) {
    if (C18DSOpen(C18DSControllerForView(self),self)) return;
    if (gDSLongOriginal) gDSLongOriginal(self,cmd);
}
static void C18DSNativeContext(id self,SEL cmd) {
    if (C18DSOpen(C18DSControllerForView(self),self)) return;
    if (gDSContextOriginal) gDSContextOriginal(self,cmd);
}
static id C18DSNativeConfiguration(id self,SEL cmd,id interaction,CGPoint point) {
    // The native context-menu interaction also initiates long-press on some grid layouts.
    if (C18DSOpen(C18DSControllerForView(self),self)) return nil;
    return gDSConfigurationOriginal?gDSConfigurationOriginal(self,cmd,interaction,point):nil;
}
static BOOL C18DSRequestLive(C18DSRequest *request) {
    id module=request.module, shell=request.shell;
    CFTimeInterval age=CACurrentMediaTime()-request.started;
    return request && !request.consumed && module && shell && shell==C18DSShell() &&
        request.token && request.sessionGeneration==C18FivePresentationGeneration() && objc_getAssociatedObject(module,&kDSRequestToken)==request.token && age>=0 && age<10;
}
static UIAlertController *C18DSAlertCreate(id self,SEL cmd,NSString *title,NSString *message,UIAlertControllerStyle style) {
    // Keep the original alert byte-for-byte when our native-state/card path is unavailable.
    UIAlertController *alert=gDSAlertOriginal(self,cmd,title,message,style);
    C18DSRequest *request=(__bridge C18DSRequest *)gDSScope;
    if (alert && C18DSRequestLive(request)) objc_setAssociatedObject(alert,&kDSRequest,request,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return alert;
}
static void C18DSPresent(C18DSPresenterHook *hook,id self,UIViewController *controller,BOOL animated,void (^completion)(void)) {
    C18DSRequest *request=objc_getAssociatedObject(controller,&kDSRequest);
    // Never synthesize a completion or change its queue/count: non-nil always goes to UIKit.
    if (!completion && self==request.presenter && [controller isKindOfClass:UIAlertController.class] &&
        C18DSRequestLive(request) && C18DSOpen(request.module,nil)) {
        request.consumed=YES; objc_setAssociatedObject(controller,&kDSRequest,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); return;
    }
    hook->original(self,@selector(presentViewController:animated:completion:),controller,animated,completion);
}
static BOOL C18DSInstallPresenter(UIViewController *presenter) {
    Class cls=object_getClass(presenter); SEL selector=@selector(presentViewController:animated:completion:);
    if (!NSThread.isMainThread || ![presenter isKindOfClass:UIViewController.class] || cls==UIViewController.class ||
        !C18HookCanInstall(cls,selector,"v",@[@"@",@"B",@"@?"])) return NO;
    for (C18DSPresenterHook *known in gDSPresenters) if (known.owner==cls) return known->original!=NULL;
    C18DSPresenterHook *hook=[C18DSPresenterHook new]; hook.owner=cls;
    IMP prior=class_getMethodImplementation(cls,selector);
    hook.replacement=imp_implementationWithBlock(^(id receiver,UIViewController *controller,BOOL animated,void(^completion)(void)) {
        C18DSPresent(hook,receiver,controller,animated,completion);
    });
    if (!prior || !hook.replacement) return NO;
    hook->original=(C18DSPresentIMP)prior;
    if (!gDSPresenters) gDSPresenters=[NSMutableArray array]; [gDSPresenters addObject:hook];
    MSHookMessageEx(cls,selector,hook.replacement,(IMP *)&hook->original);
    return hook->original!=NULL;
}
static BOOL C18DSPrepareCapture(C18DSRequest *request) {
    UIView *source=C18DSSource(request.module,nil); UIWindow *window=source.window;
    if (!window || !C18DSRequestLive(request)) return NO;
    // Use only the existing window and top controller. No singleton/overlay getter/view load.
    for (UIWindow *candidate in window.windowScene.windows) if (candidate.isKeyWindow) { window=candidate; break; }
    UIViewController *top=window.rootViewController;
    for (NSUInteger depth=0;top && top.presentedViewController && depth<32;depth++) top=top.presentedViewController;
    if (!top || top.presentedViewController || !C18DSInstallPresenter(top)) return NO;
    request.presenter=top;
    if (!gDSAlertDone) {
        SEL selector=@selector(alertControllerWithTitle:message:preferredStyle:); Class meta=object_getClass(UIAlertController.class);
        if (!C18HookCanInstall(meta,selector,"@",@[@"@",@"@",@(@encode(UIAlertControllerStyle))])) return NO;
        gDSAlertDone=YES;
        MSHookMessageEx(meta,selector,(IMP)C18DSAlertCreate,(IMP *)&gDSAlertOriginal);
    }
    return gDSAlertOriginal!=NULL;
}
void C18DataSwitchRegisterHost(id module,C18FiveModuleHost *host) {
    if (!C18DSShell() || !module || !host) return;
    id controller=C18DSControllerForView(host.nativeHost); if (!C18DSIsController(controller)) return;
    C18DSWeakView *reference=[C18DSWeakView new]; reference.view=host.nativeHost;
    objc_setAssociatedObject(controller,&kDSHost,reference,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    C18DSInstallHooks(); C18DSApplyAppearance(controller);
}
void C18DataSwitchOpenForHost(C18FiveModuleHost *host) {
    if (!host) return; C18DSInstallHooks();
    id controller=C18DSControllerForView(host); if (!controller || C18DSEditing()) return;
    if (C18DSOpen(controller,host.nativeHost)) return;
    SEL selector=NSSelectorFromString(@"buttonTapped:forEvent:");
    if (C18DSMatch(class_getInstanceMethod(object_getClass(controller),selector),"v",@[@"@",@"@"]))
        ((void(*)(id,SEL,id,id))objc_msgSend)(controller,selector,nil,nil);
}
void C18DataSwitchInstallGestures(C18FiveModuleHost *host) {
    if (!host || !C18DSControllerForView(host)) return; C18DSInstallHooks(); C18DSInstallOnView(host);
}

static void C18DSInstallHooks(void) {
    if (!NSThread.isMainThread || !C18FiveIsPresented() || !C18FiveLiveShell()) return;
    Class cls=objc_getClass("CCSwitchDataModuleViewController");
    SEL selector=NSSelectorFromString(@"buttonTapped:forEvent:");
    if (!gDSButtonDone && C18DSMatch(class_getInstanceMethod(cls,selector),"v",@[@"@",@"@"])) {
        gDSButtonDone=YES; MSHookMessageEx(cls,selector,(IMP)C18DSButtonTapped,(IMP *)&gDSButtonOriginal);
    }
    selector=NSSelectorFromString(@"updatedMenuItems");
    if (!gDSItemsDone && C18DSMatch(class_getInstanceMethod(cls,selector),"@",@[])) {
        gDSItemsDone=YES; MSHookMessageEx(cls,selector,(IMP)C18DSUpdatedItems,(IMP *)&gDSItemsOriginal);
    }
    cls=objc_getClass("C18Shell"); selector=NSSelectorFromString(@"expandModuleView:");
    if (!gDSShellDone && C18DSMatch(class_getInstanceMethod(cls,selector),"v",@[@"@"])) {
        gDSShellDone=YES; MSHookMessageEx(cls,selector,(IMP)C18DSShellExpand,(IMP *)&gDSShellOriginal);
    }
    cls=objc_getClass("C18ButtonModuleView"); selector=@selector(didMoveToWindow);
    if (!gDSMoveDone && C18DSMatch(class_getInstanceMethod(cls,selector),"v",@[])) {
        gDSMoveDone=YES; MSHookMessageEx(cls,selector,(IMP)C18DSNativeMoved,(IMP *)&gDSMoveOriginal);
    }
    selector=@selector(layoutSubviews);
    if (!gDSLayoutDone && C18DSMatch(class_getInstanceMethod(cls,selector),"v",@[])) {
        gDSLayoutDone=YES; MSHookMessageEx(cls,selector,(IMP)C18DSNativeLayout,(IMP *)&gDSLayoutOriginal);
    }
    selector=NSSelectorFromString(@"performTapFromLongPress");
    if (!gDSLongDone && C18DSMatch(class_getInstanceMethod(cls,selector),"v",@[])) {
        gDSLongDone=YES; MSHookMessageEx(cls,selector,(IMP)C18DSNativeLong,(IMP *)&gDSLongOriginal);
    }
    selector=NSSelectorFromString(@"presentContextMenu");
    if (!gDSContextDone && C18DSMatch(class_getInstanceMethod(cls,selector),"v",@[])) {
        gDSContextDone=YES; MSHookMessageEx(cls,selector,(IMP)C18DSNativeContext,(IMP *)&gDSContextOriginal);
    }
    selector=@selector(contextMenuInteraction:configurationForMenuAtLocation:);
    if (!gDSConfigurationDone && C18DSMatch(class_getInstanceMethod(cls,selector),"@",@[@"@",@"{CGPoint=dd}"])) {
        gDSConfigurationDone=YES;
        MSHookMessageEx(cls,selector,(IMP)C18DSNativeConfiguration,(IMP *)&gDSConfigurationOriginal);
    }
    // Factories and per-presenter capture are installed on an actual tap only.
}
void C18DataSwitchActivate(void) {
    if (!C18DSShell()) return;
    C18DSInstallHooks();
    // Existing native wrappers may already be on-screen before these hooks
    // attach. Discover only the current Shell's existing moduleViews graph.
    id views=C18DSObject(C18DSShell(),@"moduleViews");
    if ([views isKindOfClass:NSArray.class]) for (id wrapper in [(NSArray *)views copy]) {
        if (![wrapper isKindOfClass:UIView.class]) continue;
        id content=C18DSObject(wrapper,@"contentView");
        if ([content isKindOfClass:UIView.class]) C18DSNativeTry(content);
    }
    C18PowerMenuInstall();
}
