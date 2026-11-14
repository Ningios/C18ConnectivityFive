#import "C18SIMController.h"
#import "C18SIMRuntime.h"
#import "C18SIMSession.h"
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import <objc/runtime.h>

static UIView *C18SIMMaterial(void) {
    typedef UIView *(*Factory)(NSString *,CGFloat);
    Factory factory=(Factory)dlsym(RTLD_DEFAULT,"C18Material");
    if (!factory) {
        Class cls=objc_getClass("C18Shell"); const char *path=cls?class_getImageName(cls):NULL;
        void *image=path?dlopen(path,RTLD_LAZY|RTLD_NOLOAD):NULL;
        if (image) { factory=(Factory)dlsym(image,"C18Material"); dlclose(image); }
    }
    UIView *view=factory?factory(@"modulesSheer",1.0):nil;
    if (![view isKindOfClass:UIView.class]) view=[UIView new];
    view.userInteractionEnabled=NO; return view;
}

static UIImage *C18SIMGlyph(void) {
    UIImage *glyph=[UIImage imageNamed:@"CCSIM" inBundle:[NSBundle bundleForClass:C18SIMController.class] compatibleWithTraitCollection:nil];
    if (!glyph) glyph=[UIImage systemImageNamed:@"simcard.2" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:27 weight:UIImageSymbolWeightRegular]];
    return [glyph imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

@class C18SIMPanelController;
static __weak C18SIMPanelController *gC18SIMActivePanel;
@interface C18SIMController ()
@property(nonatomic,strong) UIButton *compactButton;
@property(nonatomic,strong) C18SIMPanelController *activePanel;
@end

@interface C18SIMPanelController : UIViewController {
    C18SIMSession _session;
}
@property(nonatomic,weak) C18SIMController *owner;
@property(nonatomic,strong) C18SIMService *service;
@property(nonatomic) BOOL requestedRead;
@property(nonatomic) BOOL wasAttached;
@property(nonatomic,strong) UIView *material;
@property(nonatomic,strong) UIImageView *headerIcon;
@property(nonatomic,strong) UILabel *heading;
@property(nonatomic,strong) UILabel *message;
@property(nonatomic,strong) UIView *headerLine;
@property(nonatomic,strong) UIScrollView *list;
@property(nonatomic,strong) NSArray<C18SIMRow *> *rows;
@property(nonatomic,strong) NSArray<C18SIMLine *> *items;
- (void)updateRows;
- (void)reload;
- (void)chooseRow:(C18SIMRow *)row;
- (void)requestClose;
- (void)endSession;
- (void)finishDetached;
- (void)presentationRejected;
@end

static BOOL C18SIMPresentPanel(id shell,UIViewController *panel,UIView *source) {
    SEL present=NSSelectorFromString(@"presentMenuViewController:fromModuleView:");
    NSMethodSignature *signature=[shell methodSignatureForSelector:present];
    if (!source || signature.numberOfArguments!=4 || strcmp(signature.methodReturnType,"v") ||
        [signature getArgumentTypeAtIndex:2][0]!='@' || [signature getArgumentTypeAtIndex:3][0]!='@') return NO;
    [panel loadViewIfNeeded];
    ((void(*)(id,SEL,id,id))objc_msgSend)(shell,present,panel,source);
    return SIMValue(shell,@"_menuController")==panel;
}

@implementation C18SIMPanelController
- (instancetype)init {
    if ((self=[super init])) { _session=C18SIMSessionNew(); _items=@[]; }
    return self;
}
- (void)loadView {
    self.title=@"蜂窝管理";
    self.preferredContentSize=CGSizeMake(336,[self preferredExpandedContentHeight]);
    UIView *view=[[UIView alloc] initWithFrame:(CGRect){CGPointZero,self.preferredContentSize}]; self.view=view;
    view.backgroundColor=UIColor.clearColor; view.layer.cornerRadius=44;
    view.layer.cornerCurve=kCACornerCurveContinuous; view.clipsToBounds=YES;
    self.material=C18SIMMaterial(); [view addSubview:self.material];
    UIImage *glyph=C18SIMGlyph();
    self.headerIcon=[[UIImageView alloc] initWithImage:glyph];
    self.headerIcon.tintColor=UIColor.whiteColor;
    self.headerIcon.contentMode=UIViewContentModeScaleAspectFit;
    [view addSubview:self.headerIcon];
    self.heading=[UILabel new]; self.heading.text=@"蜂窝管理"; self.heading.textColor=UIColor.whiteColor;
    self.heading.textAlignment=NSTextAlignmentCenter; self.heading.font=[UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    [view addSubview:self.heading];
    self.headerLine=[UIView new]; self.headerLine.backgroundColor=[UIColor colorWithWhite:1 alpha:.25]; [view addSubview:self.headerLine];
    self.list=[UIScrollView new]; self.list.alwaysBounceVertical=NO; [view addSubview:self.list];
    NSMutableArray *rows=[NSMutableArray array];
    for (NSInteger slot=1;slot<=2;slot++) {
        C18SIMRow *row=[[C18SIMRow alloc] initWithFrame:CGRectZero]; row.tag=slot;
        [row addTarget:self action:@selector(chooseRow:) forControlEvents:UIControlEventTouchUpInside];
        [self.list addSubview:row]; [rows addObject:row];
    }
    self.rows=rows;
    self.message=[UILabel new]; self.message.font=[UIFont systemFontOfSize:14];
    self.message.textAlignment=NSTextAlignmentCenter; self.message.textColor=UIColor.whiteColor; self.message.numberOfLines=3;
    self.message.text=@"正在读取 SIM 信息…"; [self.list addSubview:self.message];
    [self updateRows];
}
// Exactly the same dual-line height and initial width as C18DSController.
- (CGFloat)preferredExpandedContentHeight { return 104+62*2; }
- (bool)canDismissPresentedContent { return false; }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews]; CGFloat w=self.view.bounds.size.width,h=self.view.bounds.size.height;
    CGFloat scale=self.view.window.screen.scale ?: UIScreen.mainScreen.scale;
    self.material.frame=self.view.bounds; self.headerIcon.frame=CGRectMake((w-32)*.5,20,32,32);
    self.heading.frame=CGRectMake(16,62,w-32,27); self.headerLine.frame=CGRectMake(0,102,w,1/MAX(1,scale));
    self.list.frame=CGRectMake(0,104,w,MAX(0,h-104));
    CGFloat rowHeight=MAX(56,MIN(66,MAX(0,h-104)/MAX((NSUInteger)1,self.rows.count)));
    self.list.contentSize=CGSizeMake(w,rowHeight*self.rows.count);
    for (NSUInteger i=0;i<self.rows.count;i++) self.rows[i].frame=CGRectMake(0,i*rowHeight,w,rowHeight);
    self.message.frame=CGRectMake(16,0,MAX(0,w-32),MAX(0,h-104));
}
- (void)updateRows {
    BOOL hasItems=self.items.count>0;
    self.message.hidden=hasItems;
    for (C18SIMRow *row in self.rows) {
        C18SIMLine *line=nil;
        for (C18SIMLine *item in self.items) if (item.slot==row.tag) { line=item; break; }
        row.hidden=!line;
        if (line) [row updateWithItem:line busy:(!_session.active || _session.reading || _session.busy)];
    }
    [self.view setNeedsLayout];
}
- (void)reload {
    uint64_t token=C18SIMSessionRead(&_session); if (!token) return;
    self.requestedRead=YES; self.items=@[];
    self.message.text=@"正在读取 SIM 信息…"; [self updateRows];
    __weak C18SIMPanelController *weakSelf=self;
    [self.service readItems:^(NSArray<C18SIMLine *> *items,NSString *error) {
        C18SIMPanelController *panel=weakSelf;
        if (!panel || !C18SIMSessionAcceptRead(&panel->_session,token)) return;
        NSMutableArray *valid=[NSMutableArray array]; NSMutableSet *slots=[NSMutableSet set];
        for (C18SIMLine *line in items) {
            if (![line isKindOfClass:C18SIMLine.class] || line.slot<1 || line.slot>2 || [slots containsObject:@(line.slot)]) continue;
            [slots addObject:@(line.slot)]; [valid addObject:line];
        }
        panel.items=[valid copy]; panel.message.text=error ?: @"无法读取 SIM 信息，请关闭后重试";
        [panel updateRows];
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        C18SIMPanelController *panel=weakSelf;
        if (!panel || !C18SIMSessionAcceptRead(&panel->_session,token)) return;
        panel.items=@[]; panel.message.text=@"读取超时，请关闭后重试"; [panel updateRows];
    });
}
- (void)willTransitionToExpandedContentMode:(bool)expanded {
    if (expanded) { if (!self.requestedRead) [self reload]; }
    else [self endSession];
}
- (void)didTransitionToExpandedContentMode:(bool)expanded {
    if (!expanded) [self finishDetached];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated]; if (!self.requestedRead) [self reload];
}
- (void)willMoveToParentViewController:(UIViewController *)parent {
    if (!parent && self.wasAttached) [self endSession];
    [super willMoveToParentViewController:parent];
}
- (void)didMoveToParentViewController:(UIViewController *)parent {
    [super didMoveToParentViewController:parent];
    if (parent) self.wasAttached=YES;
    else if (self.wasAttached) [self finishDetached];
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated]; [self endSession];
}
- (void)endSession { C18SIMSessionEnd(&_session); }
- (void)finishDetached {
    if (self.parentViewController || self.viewIfLoaded.superview) return;
    [self endSession];
    if (gC18SIMActivePanel==self) gC18SIMActivePanel=nil;
    C18SIMController *owner=self.owner;
    if (owner.activePanel==self) owner.activePanel=nil;
}
- (void)presentationRejected { [self finishDetached]; }
- (void)requestClose {
    id shell=SIMObject(objc_getClass("C18Shell"),NSSelectorFromString(@"shared"));
    // The native menu's background already targets dismissMenu directly. This
    // path is for successful actions/CC dismissal; busy never blocks closing.
    if (SIMValue(shell,@"_menuController")==self) {
        [self endSession]; SIMNoArgVoid(shell,NSSelectorFromString(@"dismissMenu"));
    }
}
- (void)chooseRow:(C18SIMRow *)row {
    C18SIMLine *selected=nil;
    for (C18SIMLine *item in self.items) if (item.slot==row.tag) { selected=item; break; }
    if (!selected.available) return;
    uint64_t token=C18SIMSessionAction(&_session); if (!token) return;
    [self updateRows];
    __weak C18SIMPanelController *weakSelf=self;
    [self.service setItem:selected enabled:!selected.enabled completion:^(BOOL accepted,NSString *error) {
        C18SIMPanelController *panel=weakSelf;
        if (!panel || !C18SIMSessionAcceptAction(&panel->_session,token)) return;
        if (accepted) [panel requestClose];
        else {
            panel.items=@[]; panel.message.text=error ?: @"SIM 启停请求失败";
            [panel updateRows];
        }
    }];
}
@end

@implementation C18SIMController
- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:CGRectMake(0,0,64,64)];
    self.view.backgroundColor=UIColor.clearColor;
    self.compactButton=[UIButton buttonWithType:UIButtonTypeCustom];
    [self.compactButton setImage:C18SIMGlyph() forState:UIControlStateNormal];
    self.compactButton.tintColor=UIColor.whiteColor;
    self.compactButton.accessibilityLabel=@"蜂窝管理";
    [self.compactButton addTarget:self action:@selector(openPanel) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.compactButton];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews]; self.compactButton.frame=self.view.bounds;
}
// The compact controller is NEVER presented/reparented as expanded content.
// C18ButtonModuleView uses these exact selectors to route long press as a tap.
- (double)preferredExpandedContentHeight { return 0.0; }
- (bool)providesOwnPlatter { return false; }
- (bool)shouldBeginTransitionToExpandedContentModule { return false; }
- (bool)shouldExpandModuleOnTouch:(__unused id)touch { return false; }
- (bool)canDismissPresentedContent { return false; }
- (BOOL)c18PerformLongPress { [self openPanel]; return YES; }
- (void)openPanel {
    if (!NSThread.isMainThread || !self.viewIfLoaded.window) return;
    id shell=SIMObject(objc_getClass("C18Shell"),NSSelectorFromString(@"shared"));
    if (!shell || [SIMValue(shell,@"_editing") boolValue]) return;
    // Native dismissMenu clears _menuController before its removal animation.
    // Keep this gate until the old panel really detaches, across ALL SIM hosts.
    if (gC18SIMActivePanel || self.activePanel || SIMValue(shell,@"_menuController") ||
        SIMValue(shell,@"_expandedModule") || [SIMValue(shell,@"_collapsing") boolValue]) return;
    Class wrapper=objc_getClass("C18ModuleView"); UIView *source=self.viewIfLoaded;
    while (source && (!wrapper || ![source isKindOfClass:wrapper])) source=source.superview;
    if (!source) return;
    C18SIMPanelController *panel=[C18SIMPanelController new];
    panel.service=self.service; panel.owner=self;
    self.activePanel=panel; gC18SIMActivePanel=panel;
    if (!C18SIMPresentPanel(shell,panel,source)) [panel presentationRejected];
}
- (void)controlCenterDidDismiss { [self.activePanel requestClose]; }
@end
