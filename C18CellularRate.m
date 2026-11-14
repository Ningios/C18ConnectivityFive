#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <stdlib.h>
#import <string.h>
#import "C18Five.h"
#import "C18HookRuntime.h"

extern void MSHookMessageEx(Class, SEL, IMP, IMP *);
void C18CellularRateInstall(void);

// Original fat module: arm64 buttonTapped v32@0:8@16@24 (0xe540),
// updatedMenuItems @16@0:8 (0x106a0), transition v20@0:8B16 (0xdb54).
// Its enumeration block decodes CCUIMenuModuleItem and the 4G/5G identifiers,
// then calls initWithTitle:identifier:handler: and setSelected:.
// A dedicated card reads native items and invokes performAction; the original
// CoreTelephony backend, identifiers and selected bits are never rewritten.
static char kCRItemTitle, kCROpening;
static BOOL gCRTapDone, gCRItemsDone, gCRTransitionDone, gCRTitleDone, gCRItemTitleDone, gCRShellDone;
static dispatch_source_t gCRTimer;
static NSUInteger gCRPasses;
static void (*gCRTitleOriginal)(id, SEL, id);
static void (*gCRTransitionOriginal)(id, SEL, BOOL);
static void (*gCRShellOriginal)(id, SEL, id);
static id (*gCRItemsOriginal)(id, SEL);
static id (*gCRItemTitleOriginal)(id, SEL);
static BOOL C18CROpen(id, id);
static BOOL C18CRPresentCard(id, UIView *, id);
static void C18CRApplyTitle(id);
static void C18CRAttempt(void);

static BOOL C18CRType(const char *actual, const char *expected) {
    if (!actual || !expected) return NO;
    while (*actual && strchr("rnNoORV", *actual)) actual++;
    if (!strcmp(expected, "@")) return actual[0]=='@' && actual[1]!='?';
    if (!strcmp(expected, "B")) return actual[0]=='B' || actual[0]=='c';
    if (expected[0]=='@') return actual[0]=='@' && actual[1]!='?';
    if (expected[0]==':' || (expected[0] && !expected[1])) return actual[0]==expected[0];
    return !strcmp(actual, expected);
}
static BOOL C18CRMatch(Method method, const char *result, NSArray<NSString *> *arguments) {
    if (!method || method_getNumberOfArguments(method)!=arguments.count+2) return NO;
    char *type=method_copyReturnType(method);
    BOOL valid=C18CRType(type, result); free(type);
    for (NSUInteger i=0; valid && i<arguments.count+2; i++) {
        const char *expected=i==0?"@":i==1?":":arguments[i-2].UTF8String;
        type=method_copyArgumentType(method, (unsigned int)i);
        valid=C18CRType(type, expected); free(type);
    }
    return valid;
}
static Method C18CRMethod(id object, SEL selector) {
    return object?class_getInstanceMethod(object_getClass(object), selector):NULL;
}
static id C18CRObject(id object, NSString *name) {
    SEL selector=NSSelectorFromString(name);
    if (!C18CRMatch(C18CRMethod(object, selector), "@", @[])) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(object, selector); }
    @catch (__unused NSException *exception) { return nil; }
}
static BOOL C18CRBool(id object, NSString *name, BOOL fallback) {
    SEL selector=NSSelectorFromString(name);
    if (C18CRMatch(C18CRMethod(object, selector), "@", @[])) {
        id value=C18CRObject(object,name); return [value isKindOfClass:NSNumber.class]?[value boolValue]:fallback;
    }
    if (!C18CRMatch(C18CRMethod(object, selector), "B", @[])) return fallback;
    @try { return ((BOOL (*)(id, SEL))objc_msgSend)(object, selector); }
    @catch (__unused NSException *exception) { return fallback; }
}
static id C18CRIvar(id object, const char *name) {
    if (!object) return nil;
    Ivar ivar=class_getInstanceVariable(object_getClass(object), name);
    return ivar && C18CRType(ivar_getTypeEncoding(ivar), "@")?object_getIvar(object, ivar):nil;
}
static BOOL C18CRController(id object) {
    Class cls=objc_getClass("CCCellularRateModuleViewController");
    return cls && [object isKindOfClass:cls];
}
static void C18CRApplyTitle(id controller) {
    SEL selector=@selector(setTitle:);
    if (!C18CRController(controller) || !C18CRMatch(C18CRMethod(controller, selector), "v", @[@"@"])) return;
    ((void (*)(id, SEL, id))objc_msgSend)(controller, selector, @"蜂窝4/5G切换");
}
static BOOL C18CRWrapperMatches(id wrapper, id controller) {
    Class cls=objc_getClass("C18ModuleView");
    if (!cls || ![wrapper isKindOfClass:cls] || ![wrapper isKindOfClass:UIView.class]) return NO;
    // Validate the actual content controller, never a module title/index/tag.
    id content=C18CRObject(wrapper, @"contentView");
    return C18CRIvar(content, "_vc")==controller;
}
static UIView *C18CRAncestor(UIView *view, id controller) {
    for (NSUInteger depth=0; view && depth<32; depth++, view=view.superview)
        if (C18CRWrapperMatches(view, controller)) return view;
    return nil;
}
static UIView *C18CRFindInTree(UIView *view, id controller, NSUInteger depth, NSUInteger *remaining) {
    if (!view || !*remaining || depth>16) return nil;
    (*remaining)--;
    if (C18CRWrapperMatches(view, controller)) return view;
    for (UIView *child in view.subviews) {
        UIView *match=C18CRFindInTree(child, controller, depth+1, remaining);
        if (match) return match;
    }
    return nil;
}
static UIView *C18CRWrapper(id controller, id sender, id shell) {
    UIView *view=[controller isKindOfClass:UIViewController.class]?[(UIViewController *)controller viewIfLoaded]:nil;
    UIView *wrapper=C18CRAncestor(view, controller);
    if (!wrapper && [sender isKindOfClass:UIView.class]) wrapper=C18CRAncestor(sender, controller);
    if (wrapper) return wrapper;
    // Covers both Shell's main grid and nested four/five-slot wrappers. Hidden
    // compact wrappers remain eligible; only the native expanded content moves.
    id modules=C18CRObject(shell, @"moduleViews");
    NSUInteger remaining=1024;
    if ([modules isKindOfClass:NSArray.class]) for (id candidate in modules) {
        if (![candidate isKindOfClass:UIView.class]) continue;
        wrapper=C18CRFindInTree(candidate, controller, 0, &remaining);
        if (wrapper) return wrapper;
        if (!remaining) break;
    }
    return nil;
}

extern UIView *C18FiveNativeMaterial(NSString *recipe);

@interface C18CRChoice : NSObject
@property(nonatomic) NSInteger generation;
@property(nonatomic,strong) id nativeItem;
@property(nonatomic) BOOL selected;
@end
@implementation C18CRChoice @end

static NSInteger C18CRGeneration(id item) {
    id value=C18CRObject(item,@"identifier");
    if (![value isKindOfClass:NSString.class]) return 0;
    NSString *key=[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].uppercaseString;
    if ([key isEqualToString:@"5G"]) return 5;
    if ([key isEqualToString:@"4G"]) return 4;
    return 0;
}
static BOOL C18CRCanInvoke(id item) {
    // CCUIMenuModuleItem returns _Bool, not void (iOS 16/17).
    return C18CRMatch(C18CRMethod(item,NSSelectorFromString(@"performAction")),"B",@[]);
}
static BOOL C18CRInvokeAction(id item) {
    SEL selector=NSSelectorFromString(@"performAction");
    Method method=C18CRMethod(item,selector);
    if (!C18CRMatch(method,"B",@[])) return NO;
    char *type=method_copyReturnType(method);
    if (!type) return NO;
    const char *actual=type;
    while (*actual && strchr("rnNoORV",*actual)) actual++;
    BOOL nativeBool=actual[0]=='B';
    free(type);
    // Preserve both BOOL encodings without invoking through a void IMP.
    if (nativeBool) return ((_Bool (*)(id,SEL))objc_msgSend)(item,selector);
    return ((signed char (*)(id,SEL))objc_msgSend)(item,selector)!=0;
}
static BOOL C18CRReadSelected(id item, BOOL *value) {
    SEL selector=NSSelectorFromString(@"isSelected");
    Method method=C18CRMethod(item,selector);
    @try {
        if (C18CRMatch(method,"@",@[])) {
            id selected=((id (*)(id,SEL))objc_msgSend)(item,selector);
            if (![selected isKindOfClass:NSNumber.class]) return NO;
            *value=[selected boolValue]; return YES;
        }
        if (!C18CRMatch(method,"B",@[])) return NO;
        *value=((BOOL (*)(id,SEL))objc_msgSend)(item,selector); return YES;
    } @catch (__unused NSException *exception) { return NO; }
}
static NSArray<C18CRChoice *> *C18CRReadChoices(id controller) {
    SEL selector=NSSelectorFromString(@"updatedMenuItems");
    // An empty/invalid refresh is unknown, NOT permission to confirm a cached
    // _menuItems snapshot. Keep the ivar fallback only for older native APIs.
    id raw=C18CRMatch(C18CRMethod(controller,selector),"@",@[])?
        C18CRObject(controller,@"updatedMenuItems"):C18CRIvar(controller,"_menuItems");
    if (![raw isKindOfClass:NSArray.class]) return @[];
    NSMutableDictionary<NSNumber *,C18CRChoice *> *found=[NSMutableDictionary dictionary];
    for (id item in raw) {
        NSInteger generation=C18CRGeneration(item); BOOL selected=NO;
        if (!generation) continue;
        // Duplicates or unreadable flags make the entire snapshot ambiguous.
        if (found[@(generation)] || !C18CRCanInvoke(item) || !C18CRReadSelected(item,&selected)) return @[];
        C18CRChoice *choice=[C18CRChoice new];choice.generation=generation;choice.nativeItem=item;
        choice.selected=selected;found[@(generation)]=choice;
    }
    if (found.count!=2) return @[];
    return @[found[@5],found[@4]];
}

// C18CR_READBACK_POLICY_BEGIN -- extracted verbatim by tests/rate_regression.py.
// Pure state policy; the panel below uses this exact implementation. Immediate
// performAction's BOOL is intentionally not an input to the confirmation policy.
typedef struct {
    uint64_t generation;
    int active, busy, target;
    double deadline;
} C18CRReadbackState;
typedef enum {
    C18CRReadbackStale, C18CRReadbackWaiting,
    C18CRReadbackConfirmed, C18CRReadbackUnconfirmed
} C18CRReadbackResult;
static const double C18CRReadbackInterval=.20, C18CRReadbackTimeout=8.0;
static void C18CRReadbackInvalidate(C18CRReadbackState *state) {
    state->generation++; state->active=0; state->busy=0; state->target=0; state->deadline=0;
}
static void C18CRReadbackActivate(C18CRReadbackState *state) {
    C18CRReadbackInvalidate(state); state->active=1;
}
static uint64_t C18CRReadbackBegin(C18CRReadbackState *state, int target, double now) {
    if (!state->active || state->busy || (target!=0 && target!=4 && target!=5)) return 0;
    state->generation++; state->busy=1; state->target=target;
    state->deadline=now+C18CRReadbackTimeout; return state->generation;
}
static int C18CRReadbackAccepts(const C18CRReadbackState *state, uint64_t token) {
    return token && state->active && state->busy && state->generation==token;
}
static int C18CRExclusiveGeneration(unsigned count, long first, int firstSelected, long second, int secondSelected) {
    if (count!=2 || !((first==5 && second==4) || (first==4 && second==5)) ||
        !!firstSelected==!!secondSelected) return 0;
    return (int)(firstSelected?first:second);
}
static C18CRReadbackResult C18CRReadbackObserve(C18CRReadbackState *state, uint64_t token,
                                               int selectedGeneration, double now) {
    if (!C18CRReadbackAccepts(state,token)) return C18CRReadbackStale;
    if (selectedGeneration && (!state->target || selectedGeneration==state->target) && now<=state->deadline) {
        state->busy=0; return C18CRReadbackConfirmed;
    }
    if (now>=state->deadline) { state->busy=0; return C18CRReadbackUnconfirmed; }
    return C18CRReadbackWaiting;
}
// C18CR_READBACK_POLICY_END
static NSInteger C18CRSelectedGeneration(NSArray<C18CRChoice *> *choices) {
    if (choices.count!=2) return 0;
    return C18CRExclusiveGeneration((unsigned)choices.count,choices[0].generation,choices[0].selected,
                                   choices[1].generation,choices[1].selected);
}

@interface C18CRChoiceRow : UIControl
@property(nonatomic,strong) UILabel *capsule;
@property(nonatomic,strong) UILabel *label;
- (void)updateWithChoice:(C18CRChoice *)choice;
@end
@implementation C18CRChoiceRow
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self=[super initWithFrame:frame])) return nil;
    self.backgroundColor=UIColor.clearColor;self.isAccessibilityElement=YES;
    _capsule=[UILabel new];_capsule.textAlignment=NSTextAlignmentCenter;
    _capsule.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _capsule.textColor=UIColor.whiteColor;_capsule.layer.cornerRadius=11.5;
    _capsule.layer.cornerCurve=kCACornerCurveContinuous;_capsule.clipsToBounds=YES;
    _capsule.userInteractionEnabled=NO;[self addSubview:_capsule];
    _label=[UILabel new];_label.font=[UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    _label.textColor=UIColor.whiteColor;_label.userInteractionEnabled=NO;
    _label.adjustsFontSizeToFitWidth=YES;_label.minimumScaleFactor=.75;[self addSubview:_label];
    return self;
}
- (void)updateWithChoice:(C18CRChoice *)choice {
    self.tag=choice.generation;self.label.text=choice.generation==5?@"切换5G":@"切换4G";
    self.capsule.text=choice.selected?@"✓":@"";
    self.capsule.backgroundColor=choice.selected?[UIColor colorWithRed:.20 green:.78 blue:.35 alpha:1]:[UIColor colorWithWhite:1 alpha:.16];
    self.accessibilityLabel=self.label.text;self.accessibilityValue=choice.selected?@"已选中":@"未选中";
    self.accessibilityTraits=UIAccessibilityTraitButton|(choice.selected?UIAccessibilityTraitSelected:0);
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];CGFloat w=self.bounds.size.width,h=self.bounds.size.height;
    CGFloat bw=36,gap=12,cw=MIN(ceil([self.label sizeThatFits:CGSizeMake(CGFLOAT_MAX,h)].width),MAX(0,w-32-bw-gap));
    CGFloat x=(w-bw-gap-cw)*.5;
    self.capsule.frame=CGRectMake(x,(h-23)*.5,bw,23);self.label.frame=CGRectMake(x+bw+gap,0,cw,h);
}
- (void)setHighlighted:(BOOL)value {
    [super setHighlighted:value];self.backgroundColor=value?[UIColor colorWithWhite:1 alpha:.08]:UIColor.clearColor;
}
@end

// C18CR_REOPEN_POLICY_BEGIN -- compiled verbatim by local regression tests.
// One logical open request per old panel; repeated taps coalesce. A request can
// run only after this exact old view detaches, and only in its original session.
typedef struct {
    uint64_t serial, session;
    int pending;
} C18CRReopenState;
static void C18CRReopenCancel(C18CRReopenState *state) {
    state->serial++;state->session=0;state->pending=0;
}
static uint64_t C18CRReopenQueue(C18CRReopenState *state,uint64_t session,int sameOwner,int attached) {
    if (!session || !sameOwner || !attached) {C18CRReopenCancel(state);return 0;}
    state->serial++;state->session=session;state->pending=1;return state->serial;
}
static int C18CRReopenTake(C18CRReopenState *state,uint64_t token,uint64_t session,
                           int detached,int validContext,int blocked) {
    if (!token || token!=state->serial || !state->pending) return 0;
    int accepted=state->session==session && session && detached && validContext && !blocked;
    // Completion consumes even an invalid request: never resurrect it later.
    C18CRReopenCancel(state);return accepted;
}
// C18CR_REOPEN_POLICY_END

@class C18CRPanel;
@interface C18CRPanelView : UIView
@property(nonatomic,weak) C18CRPanel *panelOwner;
@property(nonatomic) BOOL didAttach;
@end

@interface C18CRPanel : UIViewController {
    C18CRReadbackState _readback;
    C18CRReopenState _reopen;
}
@property(nonatomic,strong) id rateController;
@property(nonatomic,strong) NSArray<C18CRChoice *> *choices;
@property(nonatomic,strong) UIView *material;
@property(nonatomic,strong) UIImage *headerGlyph;
@property(nonatomic,strong) UIImageView *icon;
@property(nonatomic,strong) UILabel *heading;
@property(nonatomic,strong) UIView *divider;
@property(nonatomic,strong) UIView *list;
@property(nonatomic,strong) NSArray<C18CRChoiceRow *> *rows;
@property(nonatomic,strong) UILabel *message;
@property(nonatomic) BOOL wasAttached;
@property(nonatomic) BOOL closing;
@property(nonatomic,weak) id presentationShell;
@property(nonatomic) NSUInteger presentationGeneration;
@property(nonatomic,weak) UIView *pendingSource;
- (BOOL)enqueueOpenForController:(id)controller wrapper:(UIView *)wrapper shell:(id)shell;
- (void)rootViewDidDetach;
- (void)consumePendingOpen:(uint64_t)token;
- (void)cancelPendingOpen;
- (void)choose:(C18CRChoiceRow *)row;
- (BOOL)isCurrentPanel;
- (void)endReadback;
- (void)renderChoices:(NSArray<C18CRChoice *> *)choices;
- (void)startReadbackForGeneration:(NSInteger)generation item:(id)item;
- (void)pollReadback:(uint64_t)token;
- (void)scheduleReadback:(uint64_t)token;
- (void)refreshFromNative;
@end
static __weak C18CRPanel *gCRActivePanel;
@implementation C18CRPanelView
- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    if (self.superview) {self.didAttach=YES;return;}
    if (self.didAttach) {self.didAttach=NO;[self.panelOwner rootViewDidDetach];}
}
@end
@implementation C18CRPanel
- (BOOL)enqueueOpenForController:(id)controller wrapper:(UIView *)wrapper shell:(id)shell {
    if (!NSThread.isMainThread) return NO;
    NSUInteger generation=C18FivePresentationGeneration();
    BOOL sameOwner=controller==self.rateController && shell==self.presentationShell &&
        shell==C18FiveLiveShell() && generation==self.presentationGeneration &&
        wrapper.window && C18CRWrapperMatches(wrapper,controller);
    uint64_t token=C18CRReopenQueue(&_reopen,generation,sameOwner,self.viewIfLoaded.superview!=nil);
    self.pendingSource=token?wrapper:nil;return token!=0;
}
- (void)cancelPendingOpen {
    C18CRReopenCancel(&_reopen);self.pendingSource=nil;
}
- (void)rootViewDidDetach {
    if (!NSThread.isMainThread) return;
    self.closing=YES;self.wasAttached=NO;[self endReadback];
    if (gCRActivePanel==self) gCRActivePanel=nil;
    if (!_reopen.pending) return;
    uint64_t token=_reopen.serial;
    // Driven by the actual removeFromSuperview event, not a guessed duration.
    // One main-queue continuation lets the original Shell completion finish
    // removing its old container before a new menu is installed.
    dispatch_async(dispatch_get_main_queue(), ^{[self consumePendingOpen:token];});
}
- (void)consumePendingOpen:(uint64_t)token {
    if (!NSThread.isMainThread) return;
    id shell=self.presentationShell;UIView *wrapper=self.pendingSource;
    BOOL context=C18FiveIsPresented() && shell && shell==C18FiveLiveShell() &&
        wrapper.window && C18CRWrapperMatches(wrapper,self.rateController) &&
        !C18CRBool(shell,@"isEditing",YES);
    BOOL blocked=C18CRIvar(shell,"_menuController") || C18CRIvar(shell,"_expandedModule") ||
        C18CRBool(shell,@"isCollapsing",NO) || objc_getAssociatedObject(self.rateController,&kCROpening) ||
        gCRActivePanel.viewIfLoaded.superview;
    if (!_reopen.pending || token!=_reopen.serial) return;
    BOOL accepted=C18CRReopenTake(&_reopen,token,C18FivePresentationGeneration(),
        self.viewIfLoaded.superview==nil,context,blocked);
    self.pendingSource=nil;
    if (accepted) C18CRPresentCard(self.rateController,wrapper,shell);
}
- (CGFloat)preferredExpandedContentHeight { return 228; }
- (void)loadView {
    self.title=@"蜂窝4/5G切换";self.preferredContentSize=CGSizeMake(336,228);
    C18CRPanelView *root=[[C18CRPanelView alloc] initWithFrame:CGRectMake(0,0,336,228)];
    root.panelOwner=self;self.view=root;
    self.view.backgroundColor=UIColor.clearColor;self.view.layer.cornerRadius=44;
    self.view.layer.cornerCurve=kCACornerCurveContinuous;self.view.clipsToBounds=YES;
    self.material=C18FiveNativeMaterial(@"modulesSheer");[self.view addSubview:self.material];
    self.icon=[[UIImageView alloc] initWithImage:self.headerGlyph];self.icon.tintColor=UIColor.whiteColor;
    self.icon.contentMode=UIViewContentModeScaleAspectFit;[self.view addSubview:self.icon];
    self.heading=[UILabel new];self.heading.text=self.title;self.heading.textColor=UIColor.whiteColor;
    self.heading.font=[UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];self.heading.textAlignment=NSTextAlignmentCenter;
    [self.view addSubview:self.heading];self.divider=[UIView new];
    self.divider.backgroundColor=[UIColor colorWithWhite:1 alpha:.25];[self.view addSubview:self.divider];
    self.list=[UIView new];[self.view addSubview:self.list];
    NSMutableArray *rows=[NSMutableArray array];
    NSArray<C18CRChoice *> *initial=C18CRSelectedGeneration(self.choices)?self.choices:@[];
    for (C18CRChoice *choice in initial) {
        C18CRChoiceRow *row=[[C18CRChoiceRow alloc] initWithFrame:CGRectZero];[row updateWithChoice:choice];
        [row addTarget:self action:@selector(choose:) forControlEvents:UIControlEventTouchUpInside];
        [self.list addSubview:row];[rows addObject:row];
    }
    self.rows=rows;
    self.message=[UILabel new];self.message.font=[UIFont systemFontOfSize:14];self.message.numberOfLines=3;
    self.message.textColor=UIColor.whiteColor;self.message.textAlignment=NSTextAlignmentCenter;
    self.message.text=@"无法读取4G/5G选项，请关闭后重试";self.message.hidden=self.rows.count==2;
    [self.list addSubview:self.message];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];CGFloat w=self.view.bounds.size.width,h=self.view.bounds.size.height;
    CGFloat scale=self.view.window.screen.scale?:UIScreen.mainScreen.scale;
    self.material.frame=self.view.bounds;self.icon.frame=CGRectMake((w-32)*.5,20,32,32);
    self.heading.frame=CGRectMake(16,62,w-32,27);self.divider.frame=CGRectMake(0,102,w,1/MAX(1,scale));
    self.list.frame=CGRectMake(0,104,w,MAX(0,h-104));
    CGFloat rh=MAX(56,MIN(66,MAX(0,h-104)/MAX((NSUInteger)1,self.rows.count)));
    for (NSUInteger i=0;i<self.rows.count;i++) self.rows[i].frame=CGRectMake(0,i*rh,w,rh);
    self.message.frame=self.list.bounds;
    if (self.view.window && !self.wasAttached) {self.wasAttached=YES;[self refreshFromNative];}
}
- (BOOL)isCurrentPanel {
    if (!NSThread.isMainThread || self.closing || gCRActivePanel!=self || !self.viewIfLoaded.window ||
        self.presentationGeneration!=C18FivePresentationGeneration()) return NO;
    id shell=C18FiveLiveShell();
    return shell==self.presentationShell && C18CRIvar(shell,"_menuController")==self && !C18CRBool(shell,@"isEditing",YES) &&
        !C18CRBool(shell,@"isCollapsing",NO);
}
- (void)endReadback {
    if (!NSThread.isMainThread) return;
    C18CRReadbackInvalidate(&_readback);self.list.userInteractionEnabled=NO;
}
- (void)renderChoices:(NSArray<C18CRChoice *> *)choices {
    if (!NSThread.isMainThread || !C18CRSelectedGeneration(choices)) return;
    self.choices=choices;
    if (self.rows.count!=2) {
        for (C18CRChoiceRow *oldRow in self.rows) [oldRow removeFromSuperview];
        NSMutableArray *rows=[NSMutableArray array];
        for (C18CRChoice *choice in choices) {
            C18CRChoiceRow *row=[[C18CRChoiceRow alloc] initWithFrame:CGRectZero];
            [row addTarget:self action:@selector(choose:) forControlEvents:UIControlEventTouchUpInside];
            [self.list addSubview:row];[rows addObject:row];
        }
        self.rows=rows;
    }
    for (NSUInteger i=0;i<2;i++) [self.rows[i] updateWithChoice:choices[i]];
    self.message.hidden=YES;[self.view setNeedsLayout];
}
- (void)startReadbackForGeneration:(NSInteger)generation item:(id)item {
    if (!NSThread.isMainThread || _readback.busy || ![self isCurrentPanel]) return;
    if (!_readback.active) C18CRReadbackActivate(&_readback);
    uint64_t token=C18CRReadbackBegin(&_readback,(int)generation,CACurrentMediaTime());
    if (!token) return;
    self.list.userInteractionEnabled=NO;
    // Feedback stays in the existing header, never overlays the two rows.
    self.heading.text=generation==5?@"正在确认5G…":generation==4?@"正在确认4G…":@"正在读取4G/5G…";
    if (self.rows.count!=2) self.message.text=@"正在读取原生状态…";
    self.message.hidden=self.rows.count==2;
    if (item) {
        @try {
            // Execute the original item exactly once through its BOOL ABI.
            // Neither YES nor NO confirms (or denies) the native rate change.
            (void)C18CRInvokeAction(item);
        } @catch (__unused NSException *exception) {
            // A handler can throw after changing the backend: still read back.
        }
    }
    [self scheduleReadback:token];
}
- (void)scheduleReadback:(uint64_t)token {
    if (!NSThread.isMainThread || !C18CRReadbackAccepts(&_readback,token)) return;
    if (![self isCurrentPanel]) { [self endReadback]; return; }
    double delay=MIN(C18CRReadbackInterval,MAX(0,_readback.deadline-CACurrentMediaTime()));
    __weak C18CRPanel *weakSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        C18CRPanel *panel=weakSelf;
        if (!panel) return;
        [panel pollReadback:token];
    });
}
- (void)pollReadback:(uint64_t)token {
    if (!NSThread.isMainThread || !C18CRReadbackAccepts(&_readback,token)) return;
    if (![self isCurrentPanel]) { [self endReadback]; return; }
    NSArray<C18CRChoice *> *choices=C18CRReadChoices(self.rateController);
    // updatedMenuItems is native code and can reenter/close/replace the panel.
    if (!C18CRReadbackAccepts(&_readback,token)) return;
    if (![self isCurrentPanel]) { [self endReadback]; return; }
    NSInteger selected=C18CRSelectedGeneration(choices);
    C18CRReadbackResult result=C18CRReadbackObserve(&_readback,token,(int)selected,CACurrentMediaTime());
    if (result==C18CRReadbackStale) return;
    if (selected) [self renderChoices:choices];
    if (result==C18CRReadbackWaiting) { [self scheduleReadback:token]; return; }
    self.heading.text=result==C18CRReadbackConfirmed?self.title:
        (_readback.target?@"切换状态未确认，请稍后重试":@"暂未读到4G/5G状态");
    self.list.userInteractionEnabled=YES;
}
- (void)refreshFromNative {
    if (!NSThread.isMainThread || _readback.busy || ![self isCurrentPanel]) return;
    if (!_readback.active) C18CRReadbackActivate(&_readback);
    NSArray<C18CRChoice *> *choices=C18CRReadChoices(self.rateController);
    if (![self isCurrentPanel] || !_readback.active || _readback.busy) return;
    if (C18CRSelectedGeneration(choices)) {
        [self renderChoices:choices];self.heading.text=self.title;self.list.userInteractionEnabled=YES;
    } else [self startReadbackForGeneration:0 item:nil];
}
- (void)choose:(C18CRChoiceRow *)row {
    if (!NSThread.isMainThread || _readback.busy || ![self isCurrentPanel]) return;
    NSArray<C18CRChoice *> *fresh=C18CRReadChoices(self.rateController);
    if (![self isCurrentPanel] || _readback.busy) return;
    C18CRChoice *target=nil;
    for (C18CRChoice *choice in fresh) if (choice.generation==row.tag) { target=choice;break; }
    if (!target || !C18CRSelectedGeneration(fresh)) {
        [self startReadbackForGeneration:0 item:nil];return;
    }
    [self renderChoices:fresh];
    if (target.selected) { self.heading.text=self.title;return; }
    [self startReadbackForGeneration:target.generation item:target.nativeItem];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];self.wasAttached=YES;self.closing=NO;
    if (!_readback.active) C18CRReadbackActivate(&_readback);
    [self refreshFromNative];
}
- (void)viewWillDisappear:(BOOL)animated {
    self.closing=YES;self.wasAttached=NO;[self endReadback];[super viewWillDisappear:animated];
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];self.wasAttached=NO;[self endReadback];
    if (gCRActivePanel==self) gCRActivePanel=nil;
}
@end

static BOOL C18CRPresentCard(id controller,UIView *wrapper,id shell) {
    if (!NSThread.isMainThread || !C18FiveIsPresented() || shell!=C18FiveLiveShell() ||
        !C18CRController(controller) || ![wrapper isKindOfClass:UIView.class] ||
        !wrapper.window || !C18CRWrapperMatches(wrapper,controller) || C18CRBool(shell,@"isEditing",YES)) return NO;
    NSUInteger generation=C18FivePresentationGeneration();
    C18CRPanel *active=gCRActivePanel;id existing=C18CRIvar(shell,"_menuController");
    if (C18CRIvar(shell,"_expandedModule") || C18CRBool(shell,@"isCollapsing",NO) ||
        objc_getAssociatedObject(controller,&kCROpening)) { [active cancelPendingOpen];return NO; }
    if (existing) {
        if (existing!=active || ![existing isKindOfClass:C18CRPanel.class] || active.rateController!=controller ||
            active.presentationShell!=shell || active.presentationGeneration!=generation) {
            [active cancelPendingOpen];return NO;
        }
        if (active.closing) return [active enqueueOpenForController:controller wrapper:wrapper shell:shell];
        // An ivar identity alone never proves that a card is actually attached.
        return active.viewIfLoaded.superview && active.viewIfLoaded.window;
    }
    if (active.viewIfLoaded.superview)
        return [active enqueueOpenForController:controller wrapper:wrapper shell:shell];
    SEL present=NSSelectorFromString(@"presentMenuViewController:fromModuleView:");
    if (!C18CRMatch(C18CRMethod(shell,present),"v",@[@"@",@"@"])) return NO;
    objc_setAssociatedObject(controller,&kCROpening,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BOOL shown=NO;
    @try {
        C18CRApplyTitle(controller);
        C18CRPanel *panel=[C18CRPanel new];panel.rateController=controller;
        panel.presentationShell=shell;panel.presentationGeneration=generation;
        panel.choices=C18CRReadChoices(controller);
        id image=C18CRObject(controller,@"glyphImage");
        if (![image isKindOfClass:UIImage.class]) image=C18CRObject(C18CRObject(controller,@"buttonView"),@"glyphImage");
        panel.headerGlyph=[image isKindOfClass:UIImage.class]?[image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]:
            [UIImage systemImageNamed:@"antenna.radiowaves.left.and.right"];
        // Native title/items/glyph getters may synchronously reenter Shell.
        // Never present into a dismissed session or over a newly opened menu.
        if (!C18FiveIsPresented() || shell!=C18FiveLiveShell() || generation!=C18FivePresentationGeneration() ||
            !wrapper.window || !C18CRWrapperMatches(wrapper,controller) || C18CRBool(shell,@"isEditing",YES) ||
            C18CRBool(shell,@"isCollapsing",NO) || C18CRIvar(shell,"_menuController") ||
            C18CRIvar(shell,"_expandedModule") || gCRActivePanel.viewIfLoaded.superview) return NO;
        gCRActivePanel=panel;
        ((void(*)(id,SEL,id,id))objc_msgSend)(shell,present,panel,wrapper);
        shown=C18CRIvar(shell,"_menuController")==panel && gCRActivePanel==panel &&
            !panel.closing && panel.viewIfLoaded.superview && panel.viewIfLoaded.window &&
            shell==C18FiveLiveShell() && generation==C18FivePresentationGeneration();
        // A native present can synchronously dismiss while the old root is
        // still attached. Keep its lifecycle guard until the actual detach.
        if (gCRActivePanel==panel && !panel.viewIfLoaded.superview) gCRActivePanel=nil;
    } @finally { objc_setAssociatedObject(controller,&kCROpening,nil,OBJC_ASSOCIATION_ASSIGN); }
    return shown;
}
BOOL C18CellularRateOpenForController(id controller,UIView *source) { return C18CROpen(controller,source); }

static BOOL C18CROpen(id controller, id sender) {
    if (!NSThread.isMainThread || !C18FiveIsPresented() || !C18CRController(controller)) return NO;
    id shell=C18FiveLiveShell();
    if (C18CRBool(shell,@"isEditing",YES)) return NO;
    UIView *wrapper=C18CRWrapper(controller,sender,shell);
    return C18CRPresentCard(controller,wrapper,shell);
}
static void C18CRShellExpand(id self,SEL command,id wrapper) {
    if (!C18FiveIsPresented() || self!=C18FiveLiveShell()) { if (gCRShellOriginal) gCRShellOriginal(self,command,wrapper);return; }
    id content=C18CRObject(wrapper,@"contentView");
    id controller=C18CRIvar(content,"_vc");
    if (C18CRController(controller)) {
        // Consume the rate module's native expansion. Both independent and
        // four/five-slot long presses therefore use the same custom card.
        C18CRPresentCard(controller,wrapper,self); return;
    }
    if (gCRShellOriginal) gCRShellOriginal(self,command,wrapper);
}
static void C18CRTapped(id self, SEL command, id sender, id event) {
    (void)command; (void)event;
    // Deliberately no original-tap fallback: that path may change the rate.
    // Missing/invalid Shell or wrapper leaves the tap inert, never switches it.
    C18CROpen(self, sender);
}
static void C18CRSetTitle(id self, SEL command, id title) {
    if (gCRTitleOriginal) gCRTitleOriginal(self, command, C18CRController(self)?@"蜂窝4/5G切换":title);
}
static void C18CRTransition(id self, SEL command, BOOL expanded) {
    if (gCRTransitionOriginal) gCRTransitionOriginal(self, command, expanded);
    C18CRApplyTitle(self);
}
static NSString *C18CRLocalized(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *key=[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].uppercaseString;
    if ([key isEqualToString:@"5G"]) return @"切换5G";
    if ([key isEqualToString:@"4G"]) return @"切换4G";
    return nil;
}
static id C18CRItemTitle(id self, SEL command) {
    id localized=objc_getAssociatedObject(self, &kCRItemTitle);
    return localized?:gCRItemTitleOriginal?gCRItemTitleOriginal(self, command):nil;
}
static id C18CRUpdatedItems(id self, SEL command) {
    // Keep the original array AND original items, including native handlers,
    // identifiers, isSelected/checked and original CoreTelephony refreshes.
    id items=gCRItemsOriginal?gCRItemsOriginal(self, command):nil;
    C18CRApplyTitle(self);
    Class itemClass=objc_getClass("CCUIMenuModuleItem");
    if (!gCRItemTitleDone || !itemClass || ![items isKindOfClass:NSArray.class]) return items;
    for (id item in items) {
        if (![item isKindOfClass:itemClass]) continue;
        NSString *localized=C18CRLocalized(C18CRObject(item, @"identifier"));
        if (!localized && gCRItemTitleOriginal) localized=C18CRLocalized(gCRItemTitleOriginal(item, @selector(title)));
        objc_setAssociatedObject(item, &kCRItemTitle, localized, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    return items;
}

static Method C18CROwnMethod(Class cls, SEL selector) {
    unsigned int count=0; Method found=NULL;
    Method *methods=cls?class_copyMethodList(cls, &count):NULL;
    for (unsigned int i=0; i<count; i++) if (sel_isEqual(method_getName(methods[i]), selector)) { found=methods[i]; break; }
    free(methods); return found;
}
static void C18CRHook(Class cls, NSString *name, const char *result, NSArray<NSString *> *arguments,
                      IMP replacement, IMP *original, BOOL allowInherited, BOOL *done) {
    if (*done || !cls) return;
    SEL selector=NSSelectorFromString(name);
    Method method=class_getInstanceMethod(cls, selector);
    if (!C18CRMatch(method, result, arguments)) return;
    Method own=C18CROwnMethod(cls, selector);
    if (!own) {
        if (!allowInherited) return;
        // Add an override to the concrete target class before hooking it.
        // Never method_setImplementation on an inherited Method (parent-wide).
        if (!class_addMethod(cls, selector, method_getImplementation(method), method_getTypeEncoding(method))) return;
        own=C18CROwnMethod(cls, selector);
    }
    if (!C18CRMatch(own, result, arguments)) return;
    *done=YES;
    MSHookMessageEx(cls, selector, replacement, original);
}
static void C18CRAttempt(void) {
    if (!NSThread.isMainThread || !C18FiveIsPresented()) return;
    static IMP originalTap;
    Class cls=objc_getClass("CCCellularRateModuleViewController");
    // Each hook has its own completed bit. A missing item class or method does
    // not cause already-installed controller hooks to be installed twice.
    C18CRHook(cls, @"setTitle:", "v", @[@"@"], (IMP)C18CRSetTitle,
              (IMP *)&gCRTitleOriginal, YES, &gCRTitleDone);
    C18CRHook(objc_getClass("CCUIMenuModuleItem"), @"title", "@", @[], (IMP)C18CRItemTitle,
              (IMP *)&gCRItemTitleOriginal, YES, &gCRItemTitleDone);
    C18CRHook(cls, @"updatedMenuItems", "@", @[], (IMP)C18CRUpdatedItems,
              (IMP *)&gCRItemsOriginal, NO, &gCRItemsDone);
    C18CRHook(cls, @"willTransitionToExpandedContentMode:", "v", @[@"B"], (IMP)C18CRTransition,
              (IMP *)&gCRTransitionOriginal, NO, &gCRTransitionDone);
    C18CRHook(objc_getClass("C18Shell"), @"expandModuleView:", "v", @[@"@"], (IMP)C18CRShellExpand,
              (IMP *)&gCRShellOriginal, NO, &gCRShellDone);
    C18CRHook(cls, @"buttonTapped:forEvent:", "v", @[@"@", @"@"], (IMP)C18CRTapped,
              &originalTap, NO, &gCRTapDone);
}
static BOOL C18CRComplete(void) {
    return gCRTapDone && gCRItemsDone && gCRTransitionDone && gCRTitleDone && gCRItemTitleDone && gCRShellDone;
}
static void C18CRWake(void) {
    if (!C18FiveIsPresented()) {if (gCRTimer) {dispatch_source_cancel(gCRTimer);gCRTimer=nil;}return;}
    C18CRAttempt();
    if (C18CRComplete()) {
        if (gCRTimer) { dispatch_source_cancel(gCRTimer); gCRTimer=nil; }
        return;
    }
    if (gCRTimer || gCRPasses>=120) return;
    // At most 120 timer ticks total (30 seconds); no install/retry recursion.
    // A later relevant dyld notification still gets an immediate attempt.
    gCRTimer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(gCRTimer, dispatch_time(DISPATCH_TIME_NOW, 250*NSEC_PER_MSEC),
                              250*NSEC_PER_MSEC, 25*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(gCRTimer, ^{
        gCRPasses++; C18CRAttempt();
        if (!C18FiveIsPresented() || C18CRComplete() || gCRPasses>=120) {
            dispatch_source_cancel(gCRTimer); gCRTimer=nil;
        }
    });
    dispatch_resume(gCRTimer);
}
static void C18CRImageAdded(const struct mach_header *header, intptr_t slide) {
    (void)slide;
    // Callback only enqueues work; Objective-C and hook installation run after
    // dyld's callback returns, on main. No loader-lock Objective-C calls.
    Dl_info info={0};
    if (!dladdr((const void *)header, &info) || !info.dli_fname) return;
    const char *path=info.dli_fname;
    if (strstr(path, "CCCellularRateModule") || strstr(path, "ControlCenterUI.framework") || strstr(path, "ControlCenterUIKit.framework") || strstr(path, "ControlCenter18"))
        dispatch_async(dispatch_get_main_queue(), ^{ C18CRWake(); });
}
void C18CellularRateInstall(void) {
    if (!NSThread.isMainThread || !C18FiveIsPresented()) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ _dyld_register_func_for_add_image(C18CRImageAdded); });
    C18CRWake();
}
