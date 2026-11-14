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
static BOOL gC18Presenting, gC18Presented;
static NSUInteger gC18PresentationGeneration;
BOOL C18FiveIsPresented(void) { return NSThread.isMainThread && (gC18Presenting || gC18Presented) && gC18LiveShell!=nil; }
id C18FiveLiveShell(void) { return C18FiveIsPresented() ? gC18LiveShell : nil; }
NSUInteger C18FivePresentationGeneration(void) { return C18FiveIsPresented() ? gC18PresentationGeneration : 0; }
static NSUInteger gDepth;
static int gReloadToken;
static void C18ReloadConfig(void);
static void C18InstallButtonMirrors(void);
FOUNDATION_EXPORT void C18PowerMenuInstall(void);
FOUNDATION_EXPORT void C18CellularRateInstall(void);
static void C18InstallViewHooks(void);
static void C18DiscoverViews(void);
static void ApplyVisible(UIView *view);
static void Apply(UIView *view);
static void (*oLayout)(id,SEL), (*oRoles)(id,SEL), (*oAlphas)(id,SEL);
static void (*oGrid)(id,SEL,long long), (*oExpanded)(id,SEL,BOOL);
static void (*oWindow)(id,SEL);
static BOOL (*oCanExpand)(id,SEL), (*oShouldExpand)(id,SEL,CGPoint);
static void (*oShellLayout)(id,SEL), (*oShellPresent)(id,SEL), (*oShellDismiss)(id,SEL);

@interface C18FiveState : NSObject <UIGestureRecognizerDelegate,UIContextMenuInteractionDelegate>
@property(nonatomic,strong) NSMutableDictionary<NSString *,C18FiveModuleHost *> *hosts;
@property(nonatomic,strong) NSMutableDictionary<NSNumber *,UIControl *> *buttons;
@property(nonatomic,strong) UIView *compactBar;
@property(nonatomic,strong) UIControl *auxiliary;
@property(nonatomic,weak) UIView *owner;
@property(nonatomic,weak) UIView *registeredModule;
@property(nonatomic) BOOL applied;
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
    CGSize size=module.bounds.size;
    if (C18CalculatePositions((int)gMode,size.width,size.height,positions)>0) return size;
    return view.bounds.size;
}
static BOOL Eligible(UIView *view) {
    C18Position p[7]; CGSize size=C18CompactSize(view);
    return gC18Presented && C18FiveIsPresented() && view.window && gMode && C18Managed(view) && !C18FiveBool(view,NSSelectorFromString(@"isExpanded")) &&
        !C18FiveBool(view,NSSelectorFromString(@"isImplicitlyExpanded")) &&
        C18CalculatePositions((int)gMode,size.width,size.height,p)>0;
}
static void Restore(UIView *view, BOOL removeHosts) {
    UIView *cluster=C18FiveGet(view,@"_cluster"); if ([cluster isKindOfClass:UIView.class]) cluster.hidden=NO;
    C18FiveState *state=State(view,NO); if (!state) return;
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
    if (!gC18Presented || !C18FiveIsPresented() || !view.window || [objc_getAssociatedObject(view,&kC18Applying) boolValue]) return;
    objc_setAssociatedObject(view,&kC18Applying,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try { ApplyVisible(view); } @finally { objc_setAssociatedObject(view,&kC18Applying,nil,OBJC_ASSOCIATION_ASSIGN); }
}
static void ApplyVisible(UIView *view) {
    if (!gConfigLoaded) LoadConfig();
    C18FiveState *existing=State(view,NO);
    BOOL managed=gMode && C18Managed(view);
    if (!managed) { Restore(view,gMode==0); return; }
    UIView *cluster=C18FiveGet(view,@"_cluster");
    // Original compact buttons are never repositioned or restored into a live
    // animation. They continue to own the native expanded-card lifecycle.
    if (!Eligible(view)) {
        BOOL expanded=C18FiveBool(view,NSSelectorFromString(@"isExpanded")) || C18FiveBool(view,NSSelectorFromString(@"isImplicitlyExpanded"));
        if (!expanded) { Restore(view,NO); return; }
        cluster.hidden=existing.compactBar!=nil;
        existing.applied=NO;
        for (UIControl *button in existing.buttons.allValues) C18PressUpdate(button,NO);
        existing.compactBar.alpha=cluster.alpha; existing.compactBar.userInteractionEnabled=NO; return;
    }
    cluster.hidden=YES;
    NSArray *buttons; if (!Parts(view,&buttons,NULL,NULL)) return;
    C18FiveState *state=State(view,YES);
    if (!state.compactBar) {
        state.compactBar=[[UIView alloc] initWithFrame:view.bounds]; state.compactBar.backgroundColor=UIColor.clearColor;
        state.compactBar.clipsToBounds=NO; [view addSubview:state.compactBar];
        state.auxiliary=[[UIControl alloc] initWithFrame:CGRectZero]; state.auxiliary.accessibilityLabel=@"展开连接面板";
        [state.auxiliary addTarget:state action:@selector(expand:) forControlEvents:UIControlEventTouchUpInside]; [state.compactBar addSubview:state.auxiliary];
    }
    state.applied=YES; state.compactBar.hidden=NO; state.compactBar.alpha=cluster.alpha;
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
    if (!gC18Presented || !C18FiveIsPresented() || !gInstalled || !gViews) return;
    id shell=C18FiveLiveShell();
    id live=C18FiveObject(shell,NSSelectorFromString(@"moduleViews"));
    Class cls=objc_getClass("C18ConnectivityView");
    if (![live isKindOfClass:NSArray.class] || !cls) return;
    for (id module in [(NSArray *)live copy]) {
        id content=C18FiveObject(module,NSSelectorFromString(@"contentView"));
        if ([content isKindOfClass:cls]) [gViews addObject:content];
    }
}
static void C18ApplyAll(void) {
    static BOOL applying=NO;
    if (!gC18Presented || !C18FiveIsPresented() || !gInstalled || applying) return;
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
    if (gC18Presented && C18FiveIsPresented() && [(UIView *)self window] && gMode && C18Managed(self)) { UIView *cluster=C18FiveGet(self,@"_cluster"); cluster.hidden=YES; }
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
static void C18ShellLayoutHook(id self, SEL cmd) {
    if (oShellLayout) oShellLayout(self,cmd);
    if (C18FiveIsPresented()) C18ApplyAll();
}
static void C18ShellPresentHook(id self, SEL cmd) {
    // An existing Shell, not +shared, is the authority for this lifecycle.
    // Hook registration itself does not create a singleton or module graph.
    if (gC18Presenting && gC18LiveShell==self) { if (oShellPresent) oShellPresent(self,cmd); return; }
    if (gC18LiveShell!=self || !gC18Presented) gC18PresentationGeneration++;
    gC18LiveShell=self;gC18Presenting=YES;gC18Presented=NO;
    BOOL completed=NO;
    @try {
        C18InstallViewHooks();
        C18ReloadConfig();
        C18InstallButtonMirrors();
        C18FiveInstallModuleHooks();
        C18FiveInstallEditor();
        C18LocalizationInstall();
        if (oShellPresent) oShellPresent(self,cmd);
        completed=YES;gC18Presented=YES;
        C18DataSwitchActivate();C18PowerMenuInstall();C18CellularRateInstall();
        C18ApplyAll();
        C18FiveModulesSetPresented(YES);
    } @finally {
        gC18Presenting=NO;
        if (!completed) {gC18Presented=NO;gC18LiveShell=nil;}
    }
}
static void C18ShellDismissHook(id self, SEL cmd) {
    gC18PresentationGeneration++;
    gC18Presenting=NO;gC18Presented=NO;
    @try {
        C18FiveModulesSetPresented(NO);
        if (oShellDismiss) oShellDismiss(self,cmd);
    } @finally { if (gC18LiveShell==self) gC18LiveShell=nil; }
}
static void C18InstallViewHooks(void) {
    C18NativeLayoutRestoreInstall();
    C18InstallButtonMirrors();
    Class shellClass=objc_getClass("C18Shell");
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
    if (!cls || !gShellLayoutInstalled || !gShellPresentInstalled || !gShellDismissInstalled) {
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
