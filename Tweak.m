#import "C18Five.h"
#import "C18ConnectivityModel.h"
#import "C18PressDriver.h"
#import "C18Localization.h"
#import "C18HookRuntime.h"
#import <QuartzCore/QuartzCore.h>
#import <mach-o/dyld.h>
#import <string.h>

extern void MSHookMessageEx(Class,SEL,IMP,IMP *);
static char kC18State, kC18ButtonMirror;
static NSHashTable<UIView *> *gViews;
static NSInteger gMode;
static NSArray<NSString *> *gSlots;
static BOOL gConfigLoaded, gInstalled, gShellLayoutInstalled, gShellPresentInstalled, gShellDismissInstalled;
static int gInstallAttempts;
static BOOL gInstallRetryScheduled;
static char kC18Applying;
static __weak id gC18LiveShell;
static BOOL gC18Presenting, gC18Presented, gC18DidPresentInFlight;
static NSUInteger gC18PreparingDepth;
static BOOL gShellBatchInstalled, gShellReloadInstalled, gShellFactoryInstalled, gModuleContentInstalled;
static __thread NSUInteger gC18FactoryDepth;
static __thread BOOL gC18StandaloneBuildAllowed;
@class C18FiveStandaloneView;
static NSUInteger gC18PresentationGeneration;
BOOL C18FiveIsPresented(void) { return NSThread.isMainThread && (gC18Presenting || gC18Presented) && gC18LiveShell!=nil; }
BOOL C18FiveIsPreparing(void) { return C18FiveIsPresented() && gC18PreparingDepth>0; }
id C18FiveLiveShell(void) { return C18FiveIsPresented() ? gC18LiveShell : nil; }
NSUInteger C18FivePresentationGeneration(void) { return C18FiveIsPresented() ? gC18PresentationGeneration : 0; }
static NSUInteger gDepth;
static int gReloadToken;
static void C18ReloadConfig(void);
static void C18InstallButtonMirrors(void);
FOUNDATION_EXPORT void C18PowerMenuInstall(void);
FOUNDATION_EXPORT void C18CellularRateInstall(void);
FOUNDATION_EXPORT void C18UptimeFixInstall(void);
FOUNDATION_EXPORT void C18UptimePrepareModule(UIView *module);
FOUNDATION_EXPORT void C18UptimeSetPresented(BOOL presented);
static void C18InstallViewHooks(void);
static void C18DiscoverViews(void);
static void ApplyVisible(UIView *view);
static void Apply(UIView *view);
static void (*oLayout)(id,SEL), (*oRoles)(id,SEL), (*oAlphas)(id,SEL);
static void (*oGrid)(id,SEL,long long), (*oExpanded)(id,SEL,BOOL);
static void (*oWindow)(id,SEL);
static BOOL (*oCanExpand)(id,SEL), (*oShouldExpand)(id,SEL,CGPoint);
static void (*oShellLayout)(id,SEL), (*oShellPresent)(id,SEL), (*oShellDismiss)(id,SEL), (*oShellReload)(id,SEL);
static void (*oShellBatch)(id,SEL,id,id);
static void C18ApplyAll(void);
static void C18PrepareShell(id shell);
static BOOL C18ShellSessionMatches(id shell,NSUInteger generation);
static void C18InvalidateShell(id shell,NSUInteger generation);
static UIView *C18DisplayView(UIView *view);
static UIView *C18SyncStandaloneContent(UIView *module,UIView *content);
static id (*oShellFactory)(id,SEL,id,long long,id,BOOL);
static void (*oModuleContent)(id,SEL,id);
static void (*oConnectivityList)(id,SEL,long long,int);
static BOOL gConnectivityListInstalled;

@interface C18FiveState : NSObject <UIGestureRecognizerDelegate,UIContextMenuInteractionDelegate>
@property(nonatomic,strong) NSMutableDictionary<NSString *,C18FiveModuleHost *> *hosts;
@property(nonatomic,strong) NSMutableDictionary<NSNumber *,UIControl *> *buttons;
@property(nonatomic,strong) UIView *compactBar;
@property(nonatomic,weak) C18FiveStandaloneView *standaloneSurface;
@property(nonatomic,strong) UIControl *auxiliary;
@property(nonatomic,weak) UIView *owner;
@property(nonatomic,weak) UIView *registeredModule;
@property(nonatomic) BOOL applied;
@property(nonatomic) NSUInteger listRequestToken;
- (void)tap:(UIControl *)sender;
- (BOOL)canHold:(UIView *)button;
- (void)openForButton:(UIView *)button;
- (void)expand:(id)sender;
@end
static BOOL C18Signature(id object,SEL sel,const char *ret,NSUInteger arguments) {
    NSMethodSignature *sig=[object methodSignatureForSelector:sel];
    return sig && sig.numberOfArguments==arguments && !strcmp(sig.methodReturnType,ret);
}
static id C18Shell(void) { return C18FiveLiveShell(); }
static BOOL C18Editing(void) { return C18FiveBool(C18Shell(),NSSelectorFromString(@"isEditing")); }
static UIView *C18OuterModule(UIView *view) {
    Class cls=objc_getClass("C18ModuleView");
    for (UIView *p=view.superview;p;p=p.superview) if (cls && [p isKindOfClass:cls]) return p;
    C18FiveState *state=objc_getAssociatedObject(view,&kC18State);
    return state.registeredModule;
}
@implementation C18FiveState
- (instancetype)init { if ((self=[super init])) { _hosts=[NSMutableDictionary dictionary]; _buttons=[NSMutableDictionary dictionary]; } return self; }
- (BOOL)canHold:(UIView *)button {
    if (!gC18Presented || !C18FiveIsPresented() || C18Editing() || !button.window || !button.userInteractionEnabled || !self.applied || C18FiveBool(self.owner,NSSelectorFromString(@"isExpanded"))) return NO;
    NSArray *tiles=C18FiveGet(self.owner,@"_tiles");NSInteger item=button.tag;
    if (![tiles isKindOfClass:NSArray.class] || item<0 || item>=(NSInteger)tiles.count) return NO;
    return C18FiveGet(tiles[item],@"listHandler") || C18FiveGet(tiles[item],@"menuProvider") || item==2 || item==4;
}
- (void)tap:(UIControl *)sender {
    if (!gC18Presented || !C18FiveIsPresented() || C18Editing()) return;
    NSArray *native=C18FiveGet(self.owner,@"_buttons");
    if ([native isKindOfClass:NSArray.class] && sender.tag>=0 && sender.tag<(NSInteger)native.count) {
        SEL action=NSSelectorFromString(@"_itemTapped:");
        if (C18Signature(self.owner,action,"v",3)) ((void(*)(id,SEL,id))objc_msgSend)(self.owner,action,native[sender.tag]);
    }
}
- (void)openForButton:(UIView *)button {
    if (![self canHold:button]) return;
    NSInteger item=button.tag;NSArray *tiles=C18FiveGet(self.owner,@"_tiles");id tile=tiles[item];
    id list=C18FiveGet(tile,@"listHandler");if (list) { ((void(^)(void))list)();return; }
    if (item==2 || item==4) {
        SEL sel=NSSelectorFromString(@"_presentListForItem:");NSMethodSignature *sig=[self.owner methodSignatureForSelector:sel];
        if (sig.numberOfArguments==3 && sig.methodReturnType[0]=='v' && [sig getArgumentTypeAtIndex:2][0]=='q')
            ((void(*)(id,SEL,long long))objc_msgSend)(self.owner,sel,item);
        return;
    }
    id provider=C18FiveGet(tile,@"menuProvider");if (!provider) return;
    C18PressPresentMenu(button,^UIContextMenuConfiguration *(UIContextMenuInteraction *interaction,CGPoint point){
        (void)interaction;(void)point;
        return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested){
            (void)suggested;id menu=((id(^)(void))provider)();return [menu isKindOfClass:UIMenu.class]?menu:nil;
        }];
    });
}
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction configurationForMenuAtLocation:(CGPoint)location {
    (void)location; if (C18Editing() || !self.applied) return nil;
    NSInteger item=interaction.view.tag; NSArray *tiles=C18FiveGet(self.owner,@"_tiles");
    if (![tiles isKindOfClass:NSArray.class] || item<0 || item>=(NSInteger)tiles.count) return nil;
    id provider=C18FiveGet(tiles[item],@"menuProvider"); if (!provider) return nil;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested){
        (void)suggested; id menu=((id(^)(void))provider)(); return [menu isKindOfClass:UIMenu.class]?menu:nil;
    }];
}
- (void)expand:(id)sender {
    (void)sender; if (C18Editing()) return;
    UIView *module=C18OuterModule(self.owner); id shell=C18Shell(); SEL sel=NSSelectorFromString(@"expandModuleView:");
    if (module && C18Signature(shell,sel,"v",3)) ((void(*)(id,SEL,id))objc_msgSend)(shell,sel,module);
}
@end
static C18FiveState *State(UIView *view, BOOL create) {
    C18FiveState *state=objc_getAssociatedObject(view,&kC18State);
    if (!state && create) { state=[C18FiveState new]; state.owner=view; state.registeredModule=C18OuterModule(view); objc_setAssociatedObject(view,&kC18State,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    return state;
}
// The original connection view is retained only as a state/action backend.
// It is NOT a subview, contentView, snapshot source or animation participant
// when mode 5 is selected. The outer native module still owns drag/position.
@interface C18FiveStandaloneView : UIView
@property(nonatomic,strong) UIView *backend;
- (void)refresh;
- (void)ensureAppeared;
- (BOOL)canExpand;
- (BOOL)shouldExpandOnTouchAtPoint:(CGPoint)point;
@end
static UIView *C18DisplayView(UIView *view) {
    C18FiveState *state=State(view,NO);
    return state.standaloneSurface ?: view;
}
UIView *C18FiveDisplayView(UIView *view) { return C18DisplayView(view); }
static BOOL Parts(id view, NSArray **buttons, NSArray **tiles, UIView **cluster) {
    id b=C18FiveGet(view,@"_buttons"), t=C18FiveGet(view,@"_tiles"), c=C18FiveGet(view,@"_cluster");
    if (![b isKindOfClass:NSArray.class] || [b count]!=7 || ![t isKindOfClass:NSArray.class] || [t count]!=7 || ![c isKindOfClass:UIView.class]) return NO;
    for (NSInteger i=0;i<7;i++) if (![b[i] isKindOfClass:UIControl.class] || [b[i] tag]!=i || ![t[i] isKindOfClass:UIView.class]) return NO;
    if (buttons) *buttons=b; if (tiles) *tiles=t; if (cluster) *cluster=c; return YES;
}
static BOOL C18Managed(UIView *view) {
    id live=C18FiveObject(C18Shell(),NSSelectorFromString(@"moduleViews")); UIView *module=C18OuterModule(view);
    return module && [live isKindOfClass:NSArray.class] && [live containsObject:module] && Parts(view,NULL,NULL,NULL);
}
static CGSize C18CompactSize(UIView *view) {
    UIView *module=C18OuterModule(view); C18Position positions[7];
    C18FiveStandaloneView *surface=State(view,NO).standaloneSurface;
    if (surface) return surface.bounds.size;
    CGSize size=module.bounds.size;
    if (C18CalculatePositions((int)gMode,size.width,size.height,positions)>0) return size;
    return view.bounds.size;
}
static BOOL Eligible(UIView *view) {
    C18Position p[7]; CGSize size=C18CompactSize(view);
    return (gMode==5 || gC18Presented) && C18FiveIsPresented() && (C18DisplayView(view).window || (gMode==5 && C18FiveIsPreparing())) && gMode && C18Managed(view) && !C18FiveBool(view,NSSelectorFromString(@"isExpanded")) &&
        !C18FiveBool(view,NSSelectorFromString(@"isImplicitlyExpanded")) &&
        C18CalculatePositions((int)gMode,size.width,size.height,p)>0;
}
static void Restore(UIView *view, BOOL removeHosts) {
    UIView *cluster=C18FiveGet(view,@"_cluster"); if (!State(view,NO).standaloneSurface && [cluster isKindOfClass:UIView.class]) cluster.hidden=NO;
    C18FiveState *state=State(view,NO); if (!state) return;
    state.listRequestToken++;
    state.applied=NO; state.compactBar.hidden=YES;
    for (UIControl *button in state.buttons.allValues) C18PressUpdate(button,NO);
    for (C18FiveModuleHost *host in state.hosts.allValues) host.hidden=YES;
    if (removeHosts) { for (C18FiveModuleHost *host in state.hosts.allValues) [host close]; [state.hosts removeAllObjects]; }
}
static void C18ReloadConfig(void) {
    NSArray *slots=nil; NSInteger mode=0;
    C18FiveRead(&mode,&slots); gMode=mode; gSlots=[slots copy] ?: C18FiveDefaultSlots(); gConfigLoaded=YES;
}
static void LoadConfig(void) { C18ReloadConfig(); }
static void C18SetObject(id object,NSString *name,id value) {
    SEL sel=NSSelectorFromString(name); NSMethodSignature *sig=[object methodSignatureForSelector:sel];
    if (sig.numberOfArguments==3 && sig.methodReturnType[0]=='v' && [sig getArgumentTypeAtIndex:2][0]=='@')
        ((void(*)(id,SEL,id))objc_msgSend)(object,sel,value);
}
static void C18SyncButton(UIControl *button,UIControl *source,BOOL primary) {
    id image=C18FiveObject(source,NSSelectorFromString(@"glyphImage"));
    if ([image isKindOfClass:UIImage.class]) C18SetObject(button,@"setGlyphImage:",image);
    C18SetObject(button,@"setHighlightColor:",C18FiveObject(source,NSSelectorFromString(@"highlightColor")));
    button.selected=source.selected; button.enabled=source.enabled;
    button.accessibilityLabel=source.accessibilityLabel; button.accessibilityValue=source.accessibilityValue;
    double scale=(source.tag==3?1.25:1.0)*(primary?1.0:0.45);
    SEL sel=NSSelectorFromString(@"setGlyphScale:"); NSMethodSignature *sig=[button methodSignatureForSelector:sel];
    if (sig.numberOfArguments==3 && [sig getArgumentTypeAtIndex:2][0]=='d') ((void(*)(id,SEL,double))objc_msgSend)(button,sel,scale);
}
static void Apply(UIView *view) {
    if ((gMode!=5 && !gC18Presented) || !C18FiveIsPresented() || (!C18DisplayView(view).window && !(gMode==5 && C18FiveIsPreparing())) || [objc_getAssociatedObject(view,&kC18Applying) boolValue]) return;
    objc_setAssociatedObject(view,&kC18Applying,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try { ApplyVisible(view); } @finally { objc_setAssociatedObject(view,&kC18Applying,nil,OBJC_ASSOCIATION_ASSIGN); }
}
static void ApplyVisible(UIView *view) {
    if (!gConfigLoaded) LoadConfig();
    C18FiveState *existing=State(view,NO);
    BOOL managed=gMode && C18Managed(view);
    if (!managed) { Restore(view,gMode==0); return; }
    UIView *cluster=C18FiveGet(view,@"_cluster");
    BOOL standalone=existing.standaloneSurface!=nil;
    UIView *display=C18DisplayView(view);
    // Original compact buttons are never repositioned or restored into a live
    // animation. They continue to own the native expanded-card lifecycle.
    if (!Eligible(view)) {
        BOOL expanded=C18FiveBool(view,NSSelectorFromString(@"isExpanded")) || C18FiveBool(view,NSSelectorFromString(@"isImplicitlyExpanded"));
        if (!expanded) {
            if (gMode!=5) { Restore(view,NO);return; }
            // Zero/temporary native bounds may settle later in this same
            // transaction. Never expose the old compact cluster in between.
            if (!standalone) cluster.hidden=YES; existing.applied=NO; existing.compactBar.hidden=YES; return;
        }
        if (!standalone) cluster.hidden=existing.compactBar!=nil;
        existing.applied=NO;
        for (UIControl *button in existing.buttons.allValues) C18PressUpdate(button,NO);
        existing.compactBar.alpha=standalone?1:cluster.alpha; existing.compactBar.userInteractionEnabled=NO; return;
    }
    if (!standalone) cluster.hidden=YES;
    NSArray *buttons; if (!Parts(view,&buttons,NULL,NULL)) return;
    C18FiveState *state=State(view,YES);
    if (!state.compactBar) {
        state.compactBar=[[UIView alloc] initWithFrame:display.bounds]; state.compactBar.backgroundColor=UIColor.clearColor;
        state.compactBar.clipsToBounds=NO; [display addSubview:state.compactBar];
        state.auxiliary=[[UIControl alloc] initWithFrame:CGRectZero]; state.auxiliary.accessibilityLabel=@"展开连接面板";
        [state.auxiliary addTarget:state action:@selector(expand:) forControlEvents:UIControlEventTouchUpInside]; [state.compactBar addSubview:state.auxiliary];
    }
    if (state.compactBar.superview!=display) [display addSubview:state.compactBar];
    state.applied=YES; state.compactBar.hidden=NO; state.compactBar.alpha=standalone?1:cluster.alpha;
    state.compactBar.userInteractionEnabled=!C18Editing();
    // Bounds are computed once for the compact representation; native expanded
    // geometry cannot overwrite these button frames during collapse.
    CGSize compactSize=C18CompactSize(view);
    state.compactBar.frame=(CGRect){CGPointZero,compactSize};
    C18Position p[7]; int count=C18CalculatePositions((int)gMode,compactSize.width,compactSize.height,p);
    NSMutableArray<NSString *> *items=[[gSlots subarrayWithRange:NSMakeRange(0,gMode)] mutableCopy];
    if (gMode==4) for (NSInteger i=0;i<7 && items.count<7;i++) { NSString *s=C18FiveBuiltinID(i); if (![items containsObject:s]) [items addObject:s]; }
    NSSet *wanted=[NSSet setWithArray:items];
    for (NSString *key in state.hosts.allKeys) if (![wanted containsObject:key]) { [state.hosts[key] close]; [state.hosts removeObjectForKey:key]; }
    NSMutableSet *usedBuiltins=[NSMutableSet set];
    for (NSString *slot in items) { NSInteger index=C18FiveBuiltinIndex(slot);if (index!=NSNotFound) [usedBuiltins addObject:@(index)]; }
    for (NSNumber *index in state.buttons) if (![usedBuiltins containsObject:index]) {
        UIControl *unused=state.buttons[index];if (!unused.hidden) unused.hidden=YES;C18PressUpdate(unused,NO);
    }
    // Do not briefly hide/re-show controls that remain in the current layout:
    // changing hidden during a stationary touch cancels its gesture tracking.
    CGRect auxiliary=CGRectNull;
    for (int i=0;i<count;i++) {
        NSString *slot=items[i]; NSInteger item=C18FiveBuiltinIndex(slot); UIView *v=nil;
        if (item!=NSNotFound) {
            UIControl *button=state.buttons[@(item)];
            if (!button) {
                Class cls=objc_getClass("C18RoundButton"); if (!cls || ![cls isSubclassOfClass:UIControl.class]) continue;
                button=[(UIControl *)[cls alloc] initWithFrame:CGRectZero]; button.tag=item;
                [button addTarget:state action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];
                // Long-press is installed below only for a primary custom slot.
                // Auxiliary three-icon region retains its existing whole-area tap.
                state.buttons[@(item)]=button; [state.compactBar addSubview:button];
            }
            NSHashTable *mirror=objc_getAssociatedObject(buttons[item],&kC18ButtonMirror);
            if (!mirror) { mirror=[NSHashTable weakObjectsHashTable]; objc_setAssociatedObject(buttons[item],&kC18ButtonMirror,mirror,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
            [mirror addObject:button];
            C18SyncButton(button,buttons[item],p[i].primary); v=button;
        } else {
            C18FiveModuleHost *host=state.hosts[slot];
            if (!host) { host=[[C18FiveModuleHost alloc] initWithSlotID:slot owner:view]; state.hosts[slot]=host; [state.compactBar addSubview:host]; }
            v=host;
        }
        if (p[i].primary) {
            CGRect frame=CGRectMake(p[i].x,p[i].y,p[i].side,p[i].side);if (!CGRectEqualToRect(v.frame,frame)) v.frame=frame;
            if (v.hidden) v.hidden=NO;if (v.alpha!=1) v.alpha=1;
            BOOL interactive=!C18Editing();if (v.userInteractionEnabled!=interactive) v.userInteractionEnabled=interactive;
            if ([v isKindOfClass:UIControl.class]) {
                __weak C18FiveState *weakState=state;__weak UIView *weakButton=v;
                C18PressAttach(v,^BOOL{ return [weakState canHold:weakButton]; },^{ [weakState openForButton:weakButton]; });
                C18PressUpdate(v,interactive);
            }
        } else {
            // Keep the auxiliary icons' geometry, disabled individual touches
            // and their single whole-area expand control exactly as before.
            v.frame=CGRectMake(p[i].x,p[i].y,p[i].side,p[i].side);v.hidden=NO;v.alpha=1;v.userInteractionEnabled=NO;
            if ([v isKindOfClass:UIControl.class]) C18PressUpdate(v,NO);
        }
        [v setNeedsLayout];
        if (!p[i].primary) auxiliary=CGRectIsNull(auxiliary)?v.frame:CGRectUnion(auxiliary,v.frame);
        if ([v isKindOfClass:C18FiveModuleHost.class]) [(C18FiveModuleHost *)v refresh];
    }
    state.auxiliary.hidden=gMode!=4 || CGRectIsNull(auxiliary);
    if (!state.auxiliary.hidden) { state.auxiliary.frame=CGRectInset(auxiliary,-2,-2); [state.compactBar bringSubviewToFront:state.auxiliary]; }
}
@implementation C18FiveStandaloneView
- (void)layoutSubviews {
    [super layoutSubviews];
    // Only this independent surface supplies compact geometry.
    if (!gC18FactoryDepth) Apply(self.backend);
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window && !gC18FactoryDepth) Apply(self.backend);
}
- (void)refresh { C18FiveVoid(self.backend,NSSelectorFromString(@"refresh"));Apply(self.backend); }
- (void)ensureAppeared { C18FiveVoid(self.backend,NSSelectorFromString(@"ensureAppeared"));Apply(self.backend); }
- (void)controlCenterWillPresent { C18FiveVoid(self.backend,_cmd);Apply(self.backend); }
- (void)controlCenterDidPresent { C18FiveVoid(self.backend,_cmd);Apply(self.backend); }
- (void)controlCenterDidDismiss { C18FiveVoid(self.backend,_cmd); }
- (void)setGridSize:(long long)size {
    SEL sel=_cmd;
    if (C18HookCanInstall(object_getClass(self.backend),sel,"v",@[@"q"]))
        ((void(*)(id,SEL,long long))objc_msgSend)(self.backend,sel,size);
}
- (BOOL)canExpand { return NO; }
- (BOOL)isExpanded { return NO; }
- (BOOL)isImplicitlyExpanded { return NO; }
- (BOOL)shouldExpandOnTouchAtPoint:(CGPoint)point { (void)point;return NO; }
@end
static C18FiveStandaloneView *C18CreateStandalone(UIView *module,UIView *backend) {
    C18FiveState *state=State(backend,YES);
    C18FiveStandaloneView *surface=[[C18FiveStandaloneView alloc] initWithFrame:backend.frame];
    surface.backgroundColor=UIColor.clearColor;surface.clipsToBounds=NO;
    surface.backend=backend;state.registeredModule=module;state.standaloneSurface=surface;
    if (state.compactBar) {
        state.compactBar.hidden=YES;state.applied=NO;
        [surface addSubview:state.compactBar];
    }
    // The real setter has not attached backend yet on the factory path.
    // The backend is otherwise removed by the original setContentView setter.
    return surface;
}
static void C18ModuleContentHook(id self,SEL cmd,id content) {
    Class cls=objc_getClass("C18ConnectivityView");
    if (NSThread.isMainThread && gC18StandaloneBuildAllowed && gMode==5 && cls &&
        [content isKindOfClass:cls] && Parts(content,NULL,NULL,NULL)) {
        C18FiveStandaloneView *surface=C18CreateStandalone(self,content);
        if (oModuleContent) oModuleContent(self,cmd,surface);
        if (gViews) [gViews addObject:content];
        return;
    }
    if (oModuleContent) oModuleContent(self,cmd,content);
}
static id C18ShellFactoryHook(id self,SEL cmd,id identifier,long long size,id instance,BOOL gallery) {
    if (!NSThread.isMainThread) return oShellFactory?oShellFactory(self,cmd,identifier,size,instance,gallery):nil;
    if (!gConfigLoaded) C18ReloadConfig();
    BOOL previous=gC18StandaloneBuildAllowed;gC18StandaloneBuildAllowed=!gallery && gMode==5;
    gC18FactoryDepth++;
    id result=nil;
    @try {
        result=oShellFactory?oShellFactory(self,cmd,identifier,size,instance,gallery):nil;
        C18UptimeFixInstall();
        if ([result isKindOfClass:UIView.class]) C18UptimePrepareModule(result);
        return result;
    } @finally { gC18StandaloneBuildAllowed=previous;if (gC18FactoryDepth) gC18FactoryDepth--; }
}
static UIView *C18SyncStandaloneContent(UIView *module,UIView *content) {
    if (!oModuleContent) return content;
    SEL setter=NSSelectorFromString(@"setContentView:");
    if (gMode==5 && ![content isKindOfClass:C18FiveStandaloneView.class]) {
        Class native=objc_getClass("C18ConnectivityView");
        if (native && [content isKindOfClass:native] && Parts(content,NULL,NULL,NULL) &&
            !C18FiveBool(content,NSSelectorFromString(@"isExpanded")) &&
            !C18FiveBool(content,NSSelectorFromString(@"isImplicitlyExpanded"))) {
            C18FiveStandaloneView *surface=C18CreateStandalone(module,content);
            oModuleContent(module,setter,surface);
            // Read the container's actual geometry before the first frame.
            [module setNeedsLayout];[module layoutIfNeeded];return surface;
        }
    } else if (gMode!=5 && [content isKindOfClass:C18FiveStandaloneView.class]) {
        C18FiveStandaloneView *surface=(C18FiveStandaloneView *)content;UIView *backend=surface.backend;
        C18FiveState *state=State(backend,NO);state.standaloneSurface=nil;
        oModuleContent(module,setter,backend);
        if (state.compactBar) [backend addSubview:state.compactBar];
        Restore(backend,gMode==0);
        [module setNeedsLayout];[module layoutIfNeeded];return backend;
    }
    return content;
}
static void (*oButtonImage)(id,SEL,id), (*oButtonColor)(id,SEL,id);
static void (*oButtonSelected)(id,SEL,BOOL), (*oButtonEnabled)(id,SEL,BOOL);
static void C18ButtonImage(id self,SEL cmd,id value) {
    if (oButtonImage) oButtonImage(self,cmd,value);
    NSHashTable *refs=objc_getAssociatedObject(self,&kC18ButtonMirror);
    for (UIControl *target in refs.allObjects) C18SetObject(target,@"setGlyphImage:",value);
}
static void C18ButtonColor(id self,SEL cmd,id value) {
    if (oButtonColor) oButtonColor(self,cmd,value);
    NSHashTable *refs=objc_getAssociatedObject(self,&kC18ButtonMirror);
    for (UIControl *target in refs.allObjects) C18SetObject(target,@"setHighlightColor:",value);
}
static void C18ButtonSelected(id self,SEL cmd,BOOL value) {
    if (oButtonSelected) oButtonSelected(self,cmd,value);
    NSHashTable *refs=objc_getAssociatedObject(self,&kC18ButtonMirror);
    for (UIControl *target in refs.allObjects) target.selected=value;
}
static void C18ButtonEnabled(id self,SEL cmd,BOOL value) {
    if (oButtonEnabled) oButtonEnabled(self,cmd,value);
    NSHashTable *refs=objc_getAssociatedObject(self,&kC18ButtonMirror);
    for (UIControl *target in refs.allObjects) target.enabled=value;
}
static void C18InstallButtonMirrors(void) {
    Class cls=objc_getClass("C18RoundButton"); if (!cls) return;
    static BOOL done[4];
    SEL selectors[4]={NSSelectorFromString(@"setGlyphImage:"),NSSelectorFromString(@"setHighlightColor:"),@selector(setSelected:),@selector(setEnabled:)};
    IMP replacements[4]={(IMP)C18ButtonImage,(IMP)C18ButtonColor,(IMP)C18ButtonSelected,(IMP)C18ButtonEnabled};
    IMP *originals[4]={(IMP *)&oButtonImage,(IMP *)&oButtonColor,(IMP *)&oButtonSelected,(IMP *)&oButtonEnabled};
    for (NSUInteger i=0;i<4;i++) if (!done[i]) {
        Method m=class_getInstanceMethod(cls,selectors[i]); if (!m || method_getNumberOfArguments(m)!=3) continue;
        char *ret=method_copyReturnType(m), *arg=method_copyArgumentType(m,2);
        BOOL valid=ret && !strcmp(ret,"v") && arg && (i<2?arg[0]=='@':(!strcmp(arg,"B")||!strcmp(arg,"c")));
        free(ret); free(arg); if (!valid) continue;
        done[i]=YES; MSHookMessageEx(cls,selectors[i],replacements[i],originals[i]);
    }
}
static void C18DiscoverViews(void) {
    if (!C18FiveIsPresented() || !gInstalled || !gViews) return;
    id shell=C18FiveLiveShell();
    id live=C18FiveObject(shell,NSSelectorFromString(@"moduleViews"));
    Class cls=objc_getClass("C18ConnectivityView");
    if (![live isKindOfClass:NSArray.class] || !cls) return;
    C18UptimeFixInstall();
    for (id module in [(NSArray *)live copy]) {
        if ([module isKindOfClass:UIView.class]) C18UptimePrepareModule(module);
        id content=C18FiveObject(module,NSSelectorFromString(@"contentView"));
        if ([module isKindOfClass:UIView.class] && [content isKindOfClass:UIView.class])
            content=C18SyncStandaloneContent(module,content);
        if ([content isKindOfClass:C18FiveStandaloneView.class]) content=[(C18FiveStandaloneView *)content backend];
        if ([content isKindOfClass:cls]) [gViews addObject:content];
    }
}
static void C18ApplyAll(void) {
    static BOOL applying=NO;
    if (!C18FiveIsPresented() || !gInstalled || applying) return;
    applying=YES;
    @try {
        C18DiscoverViews();
        for (UIView *v in gViews.allObjects) {
            Apply(v);
        }
    } @finally { applying=NO; }
}
static void C18BeforeNative(id self) {
    gDepth++;
    if (!State(self,NO).standaloneSurface && (gMode==5 || gC18Presented) && C18FiveIsPresented() && ([(UIView *)self window] || (gMode==5 && C18FiveIsPreparing())) && gMode && C18Managed(self)) { UIView *cluster=C18FiveGet(self,@"_cluster"); cluster.hidden=YES; }
}
static void C18AfterNative(id self) {
    if (gDepth) gDepth--;
    if (gDepth==0) Apply(self);
}
static void C18LayoutHook(id self, SEL cmd) {
    C18BeforeNative(self);
    @try { if (oLayout) oLayout(self,cmd); }
    @finally { C18AfterNative(self); }
    if (gViews) [gViews addObject:self];
}
static void C18RolesHook(id self, SEL cmd) { C18BeforeNative(self); @try { if (oRoles) oRoles(self,cmd); } @finally { C18AfterNative(self); } }
static void C18AlphasHook(id self, SEL cmd) { C18BeforeNative(self); @try { if (oAlphas) oAlphas(self,cmd); } @finally { C18AfterNative(self); } }
static void C18GridHook(id self, SEL cmd, long long size) { C18BeforeNative(self); @try { if (oGrid) oGrid(self,cmd,size); } @finally { C18AfterNative(self); } }
static void C18ExpandedHook(id self, SEL cmd, BOOL value) { C18BeforeNative(self); @try { if (oExpanded) oExpanded(self,cmd,value); } @finally { C18AfterNative(self); } }
static void C18WindowHook(id self, SEL cmd) {
    C18BeforeNative(self); @try { if (oWindow) oWindow(self,cmd); } @finally { C18AfterNative(self); }
    if (gViews) [gViews addObject:self];
    // Native layout/window callbacks apply only inside a live presentation.
}
static BOOL C18CanExpandHook(id self, SEL cmd) { if (gMode==5 && Eligible(self)) return NO; return oCanExpand ? oCanExpand(self,cmd) : NO; }
static BOOL C18ShouldExpandHook(id self, SEL cmd, CGPoint point) {
    if (Eligible(self)) {
        if (C18Editing() || gMode==5) return NO;
        C18FiveState *state=State(self,NO);
        return state && !state.auxiliary.hidden && CGRectContainsPoint(state.auxiliary.frame,point);
    }
    return oShouldExpand ? oShouldExpand(self,cmd,point) : NO;
}
// The real native animation entry, not the post-animation didPresent
// notification, owns cold first-frame preparation. All work remains on the
// actual Shell supplied by a user-driven batch; no +shared/startup graph load.
static BOOL C18ShellSessionMatches(id shell,NSUInteger generation) {
    return shell==gC18LiveShell && generation==gC18PresentationGeneration;
}
static void C18InvalidateShell(id shell,NSUInteger generation) {
    if (!C18ShellSessionMatches(shell,generation)) return;
    gC18PresentationGeneration++;gC18Presenting=NO;gC18Presented=NO;
    gC18DidPresentInFlight=NO;gC18PreparingDepth=0;gC18LiveShell=nil;
    C18UptimeSetPresented(NO);
    C18FiveModulesSetPresented(NO);
}
static void C18PrepareShell(id shell) {
    if (gMode!=5 || shell!=gC18LiveShell || !C18FiveIsPreparing()) return;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    @try {
        [UIView performWithoutAnimation:^{
            C18ApplyAll();
            for (UIView *view in gViews.allObjects) {
                C18FiveState *state=State(view,NO);
                if (state.applied) [state.compactBar layoutIfNeeded];
            }
        }];
    } @finally {[CATransaction commit];}
}
static void C18ShellReloadHook(id self,SEL cmd) {
    if (oShellReload) oShellReload(self,cmd);
    // Only a natural native reload within the live animation batch. Never
    // initiate reloadModules ourselves (it builds the full native module graph).
    if (C18FiveIsPreparing() && self==gC18LiveShell) C18PrepareShell(self);
}
static BOOL C18PresentationBatch(id batch,id state) {
    if (!NSThread.isMainThread || !batch || !state) return NO;
    SEL selector=NSSelectorFromString(@"type");
    if (!C18HookCanInstall(object_getClass(state),selector,"q",@[]) &&
        !C18HookCanInstall(object_getClass(state),selector,"Q",@[])) return NO;
    // Native addAnimationsToBatch uses type==1 for ensureAppeared/presentation.
    return ((NSUInteger(*)(id,SEL))objc_msgSend)(state,selector)==1;
}
static void C18ShellBatchHook(id self,SEL cmd,id batch,id state) {
    if (!C18PresentationBatch(batch,state)) {if (oShellBatch) oShellBatch(self,cmd,batch,state);return;}
    if (!gConfigLoaded) C18ReloadConfig();
    if (gMode!=5) {if (oShellBatch) oShellBatch(self,cmd,batch,state);return;}
    if (gC18LiveShell!=self || (!gC18Presenting && !gC18Presented)) {
        gC18PresentationGeneration++;gC18PreparingDepth=0;gC18DidPresentInFlight=NO;
    }
    gC18LiveShell=self;gC18Presenting=YES;gC18PreparingDepth++;
    NSUInteger generation=gC18PresentationGeneration;BOOL completed=NO;
    @try {
        if (!gConfigLoaded) C18ReloadConfig();
        // Existing graph is prepared BEFORE native animations/snapshots. If
        // empty, native reloadModules naturally calls our reload/layout hooks.
        C18PrepareShell(self);
        if (oShellBatch) oShellBatch(self,cmd,batch,state);
        if (C18ShellSessionMatches(self,generation)) C18PrepareShell(self);
        completed=YES;
    } @finally {
        if (C18ShellSessionMatches(self,generation)) {
            if (gC18PreparingDepth) gC18PreparingDepth--;
            if (!completed) C18InvalidateShell(self,generation);
        }
    }
}
static void C18ShellLayoutHook(id self, SEL cmd) {
    if (oShellLayout) oShellLayout(self,cmd);
    if (C18FiveIsPresented()) C18ApplyAll();
}
static void C18ShellPresentHook(id self, SEL cmd) {
    // An existing Shell, not +shared, is the authority for this lifecycle.
    // Hook registration itself does not create a singleton or module graph.
    if (gC18DidPresentInFlight && gC18LiveShell==self) return;
    if (gC18LiveShell!=self || (!gC18Presenting && !gC18Presented)) {
        gC18PresentationGeneration++;gC18PreparingDepth=0;gC18DidPresentInFlight=NO;
    }
    gC18LiveShell=self;gC18Presenting=YES;gC18Presented=NO;gC18DidPresentInFlight=YES;gC18PreparingDepth++;
    NSUInteger generation=gC18PresentationGeneration;BOOL completed=NO;
    @try {
        C18InstallViewHooks();
        C18ReloadConfig();
        C18InstallButtonMirrors();
        C18FiveInstallModuleHooks();
        C18FiveInstallEditor();
        C18LocalizationInstall();
        [UIView performWithoutAnimation:^{C18PrepareShell(self);}];
        if (oShellPresent) oShellPresent(self,cmd);
        // An original callback can synchronously dismiss or replace this Shell.
        // Never reactivate its retired session after returning from native code.
        if (!C18ShellSessionMatches(self,generation)) return;
        [UIView performWithoutAnimation:^{C18PrepareShell(self);}];
        completed=YES;gC18Presented=YES;
        C18DataSwitchActivate();C18PowerMenuInstall();C18CellularRateInstall();
        C18ApplyAll();
        C18UptimeSetPresented(YES);
        C18FiveModulesSetPresented(YES);
    } @finally {
        if (C18ShellSessionMatches(self,generation)) {
            gC18Presenting=NO;gC18DidPresentInFlight=NO;
            if (gC18PreparingDepth) gC18PreparingDepth--;
            if (!completed) C18InvalidateShell(self,generation);
        }
    }
}
static void C18ShellDismissHook(id self, SEL cmd) {
    // Retire before calling native cleanup. A reentrant/new presentation, even
    // on the same Shell object, receives a different generation and survives.
    if (self==gC18LiveShell) C18InvalidateShell(self,gC18PresentationGeneration);
    if (oShellDismiss) oShellDismiss(self,cmd);
}
// Native evidence: _presentListForItem: starts at 30 attempts and retries
// every 50 ms; tries==0 makes one final provider read. Preserve those reads,
// but bind each delayed continuation to the originating presentation/request.
static void C18StandaloneListAttempt(UIView *view,long long item,int tries,
                                    C18FiveState *state,id shell,UIView *module,
                                    NSUInteger generation,NSUInteger token) {
    if (State(view,NO)!=state || state.listRequestToken!=token ||
        !C18ShellSessionMatches(shell,generation) || !gC18Presented || gMode!=5 ||
        !state.standaloneSurface.window || state.registeredModule!=module ||
        !state.applied || C18Editing() || !C18Managed(view)) return;
    id legacy=C18FiveGet(view,@"_legacy");
    if (![legacy isKindOfClass:NSDictionary.class]) return;
    id provider=legacy[@(item)];
    SEL selector=NSSelectorFromString(@"presentedViewControllerForContentModuleDetailClickPresentationInteractionController:");
    if (!C18HookCanInstall(object_getClass(provider),selector,"@",@[@"@"])) return;
    id controller=C18FiveBool(provider,NSSelectorFromString(@"isEnabled")) ?
        ((id(*)(id,SEL,id))objc_msgSend)(provider,selector,nil) : nil;
    // Provider reads can run arbitrary callbacks; recheck before scheduling or
    // submitting. No old callback may acquire the identity of a new request.
    if (state.listRequestToken!=token || !C18ShellSessionMatches(shell,generation)) return;
    if (![controller isKindOfClass:UIViewController.class] && tries>0) {
        __weak UIView *weakView=view,*weakModule=module;__weak id weakShell=shell;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,50*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
            UIView *liveView=weakView,*liveModule=weakModule;id liveShell=weakShell;
            if (liveView && liveModule && liveShell)
                C18StandaloneListAttempt(liveView,item,tries-1,state,liveShell,liveModule,generation,token);
        });
        return;
    }
    if (![controller isKindOfClass:UIViewController.class])
        controller=((id(*)(id,SEL,id))objc_msgSend)(provider,selector,nil);
    if (state.listRequestToken!=token || !C18ShellSessionMatches(shell,generation) ||
        gMode!=5 || !gC18Presented || !state.applied || !state.standaloneSurface.window ||
        state.registeredModule!=module || C18Editing()) return;
    SEL anchored=NSSelectorFromString(@"presentMenuViewController:fromModuleView:");
    if ([controller isKindOfClass:UIViewController.class] &&
        C18HookCanInstall(object_getClass(shell),anchored,"v",@[@"@",@"@"]))
        ((void(*)(id,SEL,id,id))objc_msgSend)(shell,anchored,controller,module);
}
static void C18ConnectivityListHook(id self,SEL cmd,long long item,int tries) {
    C18FiveState *state=State(self,NO);
    if (!state.standaloneSurface || gMode!=5) {
        if (oConnectivityList) oConnectivityList(self,cmd,item,tries);
        return;
    }
    id shell=C18FiveLiveShell();UIView *module=state.registeredModule;
    NSUInteger token=++state.listRequestToken;
    C18StandaloneListAttempt(self,item,tries,state,shell,module,gC18PresentationGeneration,token);
}
static void C18InstallViewHooks(void) {
    C18NativeLayoutRestoreInstall();
    C18InstallButtonMirrors();
    C18PowerMenuInstall();
    Class shellClass=objc_getClass("C18Shell");
    Class moduleClass=objc_getClass("C18ModuleView");SEL contentSelector=NSSelectorFromString(@"setContentView:");
    if (!gModuleContentInstalled && C18HookCanInstall(moduleClass,contentSelector,"v",@[@"@"])) {
        gModuleContentInstalled=YES;
        MSHookMessageEx(moduleClass,contentSelector,(IMP)C18ModuleContentHook,(IMP *)&oModuleContent);
    }
    SEL factory=NSSelectorFromString(@"_makeModuleViewForIdentifier:size:instance:gallery:");
    if (!gShellFactoryInstalled && gModuleContentInstalled && C18HookCanInstall(shellClass,factory,"@",@[@"@",@"q",@"@",@"B"])) {
        gShellFactoryInstalled=YES;
        MSHookMessageEx(shellClass,factory,(IMP)C18ShellFactoryHook,(IMP *)&oShellFactory);
    }
    if (!gShellBatchInstalled && C18HookCanInstall(shellClass,NSSelectorFromString(@"addAnimationsToBatch:forState:"),"v",@[@"@",@"@"])) {
        gShellBatchInstalled=YES;
        MSHookMessageEx(shellClass,NSSelectorFromString(@"addAnimationsToBatch:forState:"),(IMP)C18ShellBatchHook,(IMP *)&oShellBatch);
    }
    if (!gShellReloadInstalled && C18HookCanInstall(shellClass,NSSelectorFromString(@"reloadModules"),"v",@[])) {
        gShellReloadInstalled=YES;
        MSHookMessageEx(shellClass,NSSelectorFromString(@"reloadModules"),(IMP)C18ShellReloadHook,(IMP *)&oShellReload);
    }
    if (!gShellLayoutInstalled && C18HookCanInstall(shellClass,@selector(layout),"v",@[])) {
        gShellLayoutInstalled=YES;
        MSHookMessageEx(shellClass,@selector(layout),(IMP)C18ShellLayoutHook,(IMP*)&oShellLayout);
    }
    if (!gShellPresentInstalled && C18HookCanInstall(shellClass,@selector(overlayDidPresent),"v",@[])) {
        gShellPresentInstalled=YES;
        MSHookMessageEx(shellClass,@selector(overlayDidPresent),(IMP)C18ShellPresentHook,(IMP*)&oShellPresent);
    }
    if (!gShellDismissInstalled && C18HookCanInstall(shellClass,@selector(overlayDidDismiss),"v",@[])) {
        gShellDismissInstalled=YES;
        MSHookMessageEx(shellClass,@selector(overlayDidDismiss),(IMP)C18ShellDismissHook,(IMP*)&oShellDismiss);
    }
    Class cls=objc_getClass("C18ConnectivityView");
    SEL list=NSSelectorFromString(@"_presentListForItem:tries:");
    SEL anchored=NSSelectorFromString(@"presentMenuViewController:fromModuleView:");
    if (!gConnectivityListInstalled && C18HookCanInstall(shellClass,anchored,"v",@[@"@",@"@"]) && C18HookCanInstall(cls,list,"v",@[@"q",@"i"])) {
        gConnectivityListInstalled=YES;MSHookMessageEx(cls,list,(IMP)C18ConnectivityListHook,(IMP *)&oConnectivityList);
    }
    if (!cls || !gShellLayoutInstalled || !gShellPresentInstalled || !gShellDismissInstalled || !gShellBatchInstalled || !gShellReloadInstalled || !gShellFactoryInstalled || !gModuleContentInstalled) {
        if (!gInstallRetryScheduled && gInstallAttempts++<120) {
            gInstallRetryScheduled=YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
                gInstallRetryScheduled=NO;
                C18InstallViewHooks();
            });
        }
        if (!cls) return;
    }
    C18FiveInstallModuleHooks();
    C18FiveInstallEditor();
    if (gInstalled) return;
    SEL selectors[8]={@selector(layoutSubviews),@selector(_applyButtonRoles),@selector(_applyLayoutAlphas),@selector(setGridSize:),@selector(setExpanded:),@selector(didMoveToWindow),@selector(canExpand),@selector(shouldExpandOnTouchAtPoint:)};
    for (NSUInteger i=0;i<8;i++) {
        NSArray *args=i==3?@[@"q"]:i==4?@[@"B"]:i==7?@[@"{CGPoint=dd}"]:@[];
        if (!C18HookCanInstall(cls,selectors[i],i>=6?"B":"v",args)) return;
    }
    gInstalled=YES; gViews=[NSHashTable weakObjectsHashTable];
    MSHookMessageEx(cls,@selector(layoutSubviews),(IMP)C18LayoutHook,(IMP*)&oLayout);
    MSHookMessageEx(cls,@selector(_applyButtonRoles),(IMP)C18RolesHook,(IMP*)&oRoles);
    MSHookMessageEx(cls,@selector(_applyLayoutAlphas),(IMP)C18AlphasHook,(IMP*)&oAlphas);
    MSHookMessageEx(cls,@selector(setGridSize:),(IMP)C18GridHook,(IMP*)&oGrid);
    MSHookMessageEx(cls,@selector(setExpanded:),(IMP)C18ExpandedHook,(IMP*)&oExpanded);
    MSHookMessageEx(cls,@selector(didMoveToWindow),(IMP)C18WindowHook,(IMP*)&oWindow);
    MSHookMessageEx(cls,@selector(canExpand),(IMP)C18CanExpandHook,(IMP*)&oCanExpand);
    MSHookMessageEx(cls,@selector(shouldExpandOnTouchAtPoint:),(IMP)C18ShouldExpandHook,(IMP*)&oShouldExpand);
    notify_register_dispatch(C18FiveReload,&gReloadToken,dispatch_get_main_queue(),^(int t){ (void)t;gConfigLoaded=NO;if (C18FiveIsPresented()) {C18ReloadConfig();C18ApplyAll();} });
    // Deliberately no +shared, state reload, discovery or module construction here.
}
__attribute__((constructor)) static void C18FiveInit(void) {
    dispatch_async(dispatch_get_main_queue(),^{ C18InstallViewHooks(); });
}
