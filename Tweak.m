#import "C18Five.h"
#import "C18ConnectivityModel.h"
#import <QuartzCore/QuartzCore.h>
#import <mach-o/dyld.h>

extern void MSHookMessageEx(Class,SEL,IMP,IMP *);
static char kC18State;
static NSHashTable<UIView *> *gViews;
static NSInteger gMode;
static NSArray<NSString *> *gSlots;
static BOOL gConfigLoaded, gInstalled;
static NSUInteger gDepth;
static int gReloadToken;
static void C18ReloadConfig(void);
static void (*oLayout)(id,SEL), (*oRoles)(id,SEL), (*oAlphas)(id,SEL);
static void (*oGrid)(id,SEL,long long), (*oExpanded)(id,SEL,BOOL);
static void (*oRefresh)(id,SEL,BOOL), (*oWindow)(id,SEL);
static BOOL (*oCanExpand)(id,SEL), (*oShouldExpand)(id,SEL,CGPoint);
static void (*oDidPresent)(id,SEL), (*oDidDismiss)(id,SEL);

@interface C18FiveState : NSObject
@property(nonatomic,strong) NSMutableDictionary<NSString *,C18FiveModuleHost *> *hosts;
@property(nonatomic,strong) NSArray<NSDictionary *> *saved;
@property(nonatomic) BOOL applied;
@end
@implementation C18FiveState
- (instancetype)init { if ((self=[super init])) _hosts=[NSMutableDictionary dictionary]; return self; }
@end
static C18FiveState *State(UIView *view, BOOL create) {
    C18FiveState *state=objc_getAssociatedObject(view,&kC18State);
    if (!state && create) { state=[C18FiveState new]; objc_setAssociatedObject(view,&kC18State,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    return state;
}
static BOOL Parts(id view, NSArray **buttons, NSArray **tiles, UIView **cluster) {
    id b=C18FiveGet(view,@"_buttons"), t=C18FiveGet(view,@"_tiles"), c=C18FiveGet(view,@"_cluster");
    if (![b isKindOfClass:NSArray.class] || [b count]!=7 || ![t isKindOfClass:NSArray.class] || [t count]!=7 || ![c isKindOfClass:UIView.class]) return NO;
    for (NSInteger i=0;i<7;i++) {
        if (![b[i] isKindOfClass:UIControl.class] || [b[i] tag]!=i || ![t[i] isKindOfClass:UIView.class]) return NO;
    }
    if (buttons) *buttons=b; if (tiles) *tiles=t; if (cluster) *cluster=c; return YES;
}
static BOOL Eligible(UIView *view) {
    C18Position p[7];
    id shell=C18FiveObject(objc_getClass("C18Shell"),NSSelectorFromString(@"shared"));
    NSArray *live=C18FiveObject(shell,NSSelectorFromString(@"moduleViews"));
    UIView *parent=view.superview; Class moduleClass=objc_getClass("C18ModuleView");
    while (parent && (!moduleClass || ![parent isKindOfClass:moduleClass])) parent=parent.superview;
    if (!parent || ![live isKindOfClass:NSArray.class] || ![live containsObject:parent]) return NO;
    return gMode && !C18FiveBool(view,NSSelectorFromString(@"isExpanded")) &&
        !C18FiveBool(view,NSSelectorFromString(@"isImplicitlyExpanded")) &&
        C18CalculatePositions((int)gMode,view.bounds.size.width,view.bounds.size.height,p)>0 && Parts(view,NULL,NULL,NULL);
}
static void Restore(UIView *view, BOOL removeHosts) {
    C18FiveState *state=State(view,NO); if (!state) return;
    if (state.applied) {
        state.applied=NO;
        for (NSDictionary *d in state.saved) {
            UIView *v=d[@"view"]; v.hidden=[d[@"hidden"] boolValue]; v.alpha=[d[@"alpha"] doubleValue];
            v.userInteractionEnabled=[d[@"interaction"] boolValue]; v.frame=[d[@"frame"] CGRectValue];
            if (d[@"glyph"]) ((void(*)(id,SEL,double))objc_msgSend)(v,NSSelectorFromString(@"setGlyphScale:"),[d[@"glyph"] doubleValue]);
        }
        state.saved=nil;
    }
    for (C18FiveModuleHost *host in state.hosts.allValues) host.hidden=YES;
    if (removeHosts) { for (C18FiveModuleHost *host in state.hosts.allValues) [host close]; [state.hosts removeAllObjects]; }
}
static void C18ReloadConfig(void) {
    NSArray *slots=nil; NSInteger mode=0;
    C18FiveRead(&mode,&slots); gMode=mode; gSlots=[slots copy] ?: C18FiveDefaultSlots();
    gConfigLoaded=YES;
}
static void LoadConfig(void) { C18ReloadConfig(); }
static void Apply(UIView *view) {
    if (!gConfigLoaded) LoadConfig();
    if (!Eligible(view)) { Restore(view,gMode==0); return; }
    NSArray *buttons,*tiles; UIView *cluster;
    if (!Parts(view,&buttons,&tiles,&cluster)) return;
    C18FiveState *state=State(view,YES);
    if (state.applied) return;
    NSMutableArray *objects=[NSMutableArray arrayWithArray:buttons]; [objects addObjectsFromArray:tiles]; [objects addObject:cluster];
    UIView *material=C18FiveGet(view,@"_backgroundMaterial"); if ([material isKindOfClass:UIView.class]) [objects addObject:material];
    NSMutableArray *saved=[NSMutableArray array];
    for (UIView *v in objects) {
        NSMutableDictionary *d=[@{@"view":v,@"hidden":@(v.hidden),@"alpha":@(v.alpha),@"interaction":@(v.userInteractionEnabled),@"frame":[NSValue valueWithCGRect:v.frame]} mutableCopy];
        if ([v respondsToSelector:NSSelectorFromString(@"glyphScale")]) d[@"glyph"]=C18FiveGet(v,@"glyphScale")?:@1;
        [saved addObject:d];
    }
    state.saved=saved; state.applied=YES;
    cluster.frame=view.bounds; cluster.hidden=NO; cluster.alpha=1; cluster.userInteractionEnabled=YES;
    material.alpha=1;
    for (UIView *v in tiles) { v.hidden=YES; v.userInteractionEnabled=NO; }
    for (UIControl *v in buttons) { v.hidden=YES; v.userInteractionEnabled=NO; }
    C18Position p[7]; int count=C18CalculatePositions((int)gMode,view.bounds.size.width,view.bounds.size.height,p);
    NSMutableArray<NSString *> *items=[[gSlots subarrayWithRange:NSMakeRange(0,gMode)] mutableCopy];
    if (gMode==4) {
        // Keep the right-hand auxiliary region, populated with remaining connection controls.
        for (NSInteger i=0;i<7 && items.count<7;i++) { NSString *s=C18FiveBuiltinID(i); if (![items containsObject:s]) [items addObject:s]; }
    }
    NSSet *wanted=[NSSet setWithArray:[items filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *s, NSDictionary *b){return C18FiveModuleID(s)!=nil;}]]];
    for (NSString *key in state.hosts.allKeys) if (![wanted containsObject:key]) { [state.hosts[key] close]; [state.hosts removeObjectForKey:key]; }
    for (int i=0;i<count;i++) {
        NSString *slot=items[i]; NSInteger item=C18FiveBuiltinIndex(slot);
        UIView *v;
        if (item!=NSNotFound) {
            v=buttons[item];
            double scale=item==3 ? 1.25 : 1.0;
            if (!p[i].primary) scale*=0.45;
            if ([v respondsToSelector:NSSelectorFromString(@"setGlyphScale:")]) ((void(*)(id,SEL,double))objc_msgSend)(v,NSSelectorFromString(@"setGlyphScale:"),scale);
        } else {
            C18FiveModuleHost *host=state.hosts[slot];
            if (!host) { host=[[C18FiveModuleHost alloc] initWithSlotID:slot owner:view]; state.hosts[slot]=host; [cluster addSubview:host]; }
            v=host;
        }
        v.frame=CGRectMake(p[i].x,p[i].y,p[i].side,p[i].side); v.hidden=NO; v.alpha=1; v.userInteractionEnabled=YES;
        [v setNeedsLayout];
    }
}
static void C18ApplyAll(void) {
    for (UIView *v in gViews.allObjects) { [v setNeedsLayout]; [v layoutIfNeeded]; }
}
static void C18BeforeNative(id self) {
    if (gDepth==0) Restore(self,gMode==0);
    gDepth++;
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
    // beta4 creates ConnectivityView before it receives its final compact frame.
    // Reapply on the next main-loop passes so first presentation is already five-key.
    dispatch_async(dispatch_get_main_queue(),^{ Apply(self); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,120*NSEC_PER_MSEC),dispatch_get_main_queue(),^{ Apply(self); });
}
static BOOL C18CanExpandHook(id self, SEL cmd) { if (gMode==5 && Eligible(self)) return NO; return oCanExpand ? oCanExpand(self,cmd) : NO; }
static BOOL C18ShouldExpandHook(id self, SEL cmd, CGPoint point) { if (gMode==5 && Eligible(self)) return NO; return oShouldExpand ? oShouldExpand(self,cmd,point) : NO; }
static void C18ReloadNotify(int token) { C18ReloadConfig(); C18ApplyAll(); }
static void C18InstallViewHooks(void) {
    if (gInstalled) return;
    Class cls=objc_getClass("C18ConnectivityView"); if (!cls) return;
    gInstalled=YES; gViews=[NSHashTable weakObjectsHashTable]; C18ReloadConfig();
    MSHookMessageEx(cls,@selector(layoutSubviews),(IMP)C18LayoutHook,(IMP*)&oLayout);
    MSHookMessageEx(cls,@selector(_applyButtonRoles),(IMP)C18RolesHook,(IMP*)&oRoles);
    MSHookMessageEx(cls,@selector(_applyLayoutAlphas),(IMP)C18AlphasHook,(IMP*)&oAlphas);
    MSHookMessageEx(cls,@selector(setGridSize:),(IMP)C18GridHook,(IMP*)&oGrid);
    MSHookMessageEx(cls,@selector(setExpanded:),(IMP)C18ExpandedHook,(IMP*)&oExpanded);
    MSHookMessageEx(cls,@selector(didMoveToWindow),(IMP)C18WindowHook,(IMP*)&oWindow);
    MSHookMessageEx(cls,@selector(canExpand),(IMP)C18CanExpandHook,(IMP*)&oCanExpand);
    MSHookMessageEx(cls,@selector(shouldExpandOnTouchAtPoint:),(IMP)C18ShouldExpandHook,(IMP*)&oShouldExpand);
    notify_register_dispatch(C18FiveReload,&gReloadToken,dispatch_get_main_queue(),^(int t){C18ReloadConfig();C18ApplyAll();});
    C18FiveInstallModuleHooks();
    C18FiveInstallEditor();
}
__attribute__((constructor)) static void C18FiveInit(void) {
    dispatch_async(dispatch_get_main_queue(),^{ C18InstallViewHooks(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1*NSEC_PER_SEC),dispatch_get_main_queue(),^{ C18InstallViewHooks(); });
}
