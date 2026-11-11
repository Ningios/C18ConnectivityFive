#import "C18Five.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>

@interface C18FiveChoiceController : UITableViewController
@property(nonatomic,strong) NSArray<NSDictionary *> *groups;
@property(nonatomic,copy) NSString *selected;
@property(nonatomic,copy) BOOL (^choose)(NSString *identifier);
@end
@implementation C18FiveChoiceController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return self.groups.count; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return [self.groups[section][@"entries"] count]; }
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section { return self.groups[section][@"title"]; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:@"choice"];
    if (!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"choice"];
    NSDictionary *entry=self.groups[ip.section][@"entries"][ip.row];
    cell.textLabel.text=entry[@"title"]; cell.textLabel.numberOfLines=2;
    cell.accessoryType=[entry[@"id"] isEqualToString:self.selected]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [table deselectRowAtIndexPath:ip animated:YES];
    NSString *identifier=self.groups[ip.section][@"entries"][ip.row][@"id"];
    if (self.choose && self.choose(identifier)) [self.navigationController popViewControllerAnimated:YES];
    else {
        UIAlertController *a=[UIAlertController alertControllerWithTitle:@"保存失败" message:@"原配置未更改，请重试。" preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
    }
}
@end

extern void MSHookMessageEx(Class, SEL, IMP, IMP *);
static char kC18EditorInstalled;
static BOOL gC18EditorHooked;
static int gC18EditorTries;
static void (*gOriginalDragPress)(id,SEL,id);

@interface C18FiveEditorController : UITableViewController <UIAdaptivePresentationControllerDelegate>
@property(nonatomic,strong) NSArray<NSDictionary *> *catalog;
@property(nonatomic) NSInteger mode;
@property(nonatomic,strong) NSArray<NSString *> *slots;
@property(nonatomic,weak) id shell;
@property(nonatomic) BOOL sessionEnded;
- (void)endConfiguration;
@end

@implementation C18FiveEditorController
- (instancetype)init {
    if ((self=[super initWithStyle:UITableViewStyleInsetGrouped])) {
        self.title=@"自定义五键";
        NSArray *saved=nil; NSInteger mode=0; C18FiveRead(&mode,&saved); _mode=mode; _slots=saved; _catalog=C18FiveCatalog();
        self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)];
        self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    }
    return self;
}
- (void)endConfiguration {
    if (_sessionEnded) return; _sessionEnded=YES;
    C18FiveVoid(_shell,NSSelectorFromString(@"controlConfigurationDidEnd"));
}
- (void)close { [self dismissViewControllerAnimated:YES completion:^{ [self endConfiguration]; }]; }
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.isBeingDismissed || self.navigationController.isBeingDismissed || !self.navigationController.presentingViewController) [self endConfiguration];
}
- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController { [self endConfiguration]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section==0 ? 1 : 5; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return section==0 ? @"布局模式" : @"五个槽位"; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"c18five"];
    if (!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"c18five"];
    cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    if (indexPath.section==0) {
        cell.textLabel.text=@"布局模式";
        cell.detailTextLabel.text=_mode==5?@"自定义五键":(_mode==4?@"自定义四键":@"原版布局");
    } else {
        cell.textLabel.text=[NSString stringWithFormat:@"槽位%ld",(long)indexPath.row+1];
        NSString *slot=_slots[indexPath.row]; NSString *title=slot;
        for (NSDictionary *entry in _catalog) if ([entry[@"id"] isEqual:slot]) { title=entry[@"title"]; break; }
        cell.detailTextLabel.text=title;
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tableView deselectRowAtIndexPath:ip animated:YES];
    C18FiveChoiceController *choice=[C18FiveChoiceController new];
    __weak C18FiveEditorController *weakSelf=self;
    if (ip.section==0) {
        choice.title=@"布局模式"; choice.selected=[@(_mode) stringValue];
        choice.groups=@[@{@"title":@"布局模式",@"entries":@[
            @{@"id":@"0",@"title":@"原版布局"},@{@"id":@"4",@"title":@"自定义四键"},@{@"id":@"5",@"title":@"自定义五键"}]}];
        choice.choose=^BOOL(NSString *value) {
            C18FiveEditorController *editor=weakSelf; if (!editor) return NO;
            NSInteger mode=[value integerValue];
            if (!C18FiveWrite(mode,editor.slots)) return NO;
            editor.mode=mode; [editor.tableView reloadData]; return YES;
        };
    } else {
        NSInteger slot=ip.row; choice.title=[NSString stringWithFormat:@"选择槽位%ld",(long)slot+1]; choice.selected=_slots[slot];
        NSMutableArray *groups=[NSMutableArray array];
        for (NSString *name in @[@"连接功能",@"CC+",@"自带功能",@"系统功能"]) {
            NSMutableArray *entries=[NSMutableArray array];
            for (NSDictionary *entry in _catalog) if ([entry[@"group"] isEqual:name]) [entries addObject:entry];
            if (entries.count) [groups addObject:@{@"title":name,@"entries":entries}];
        }
        choice.groups=groups;
        choice.choose=^BOOL(NSString *sid) {
            C18FiveEditorController *editor=weakSelf; if (!editor) return NO;
            NSMutableArray *next=[editor.slots mutableCopy]; NSString *old=next[slot]; NSUInteger existing=[next indexOfObject:sid];
            if (existing!=NSNotFound && existing!=(NSUInteger)slot) next[existing]=old;
            next[slot]=sid;
            if (!C18FiveWrite(editor.mode,next)) return NO;
            editor.slots=next; [editor.tableView reloadData]; return YES;
        };
    }
    [self.navigationController pushViewController:choice animated:YES];
}
@end

static UIViewController *C18FiveTopController(UIView *view) {
    UIResponder *r=view;
    while (r) { if ([r isKindOfClass:UIViewController.class]) return (UIViewController *)r; r=r.nextResponder; }
    UIWindow *w=view.window; UIViewController *vc=w.rootViewController;
    while (vc.presentedViewController) vc=vc.presentedViewController;
    return vc;
}
static void C18FivePresentEditor(id shell,UIView *view) {
    if (!view.window || !C18FiveBool(shell,NSSelectorFromString(@"isEditing"))) return;
    if (C18FiveGet(shell,@"_dragView") || C18FiveGet(shell,@"_resizeView")) return;
    UIViewController *top=C18FiveObject(shell,NSSelectorFromString(@"overlay"));
    if (![top isKindOfClass:UIViewController.class]) top=C18FiveTopController(view);
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) top=top.presentedViewController;
    if (!top.viewIfLoaded.window || top.isBeingDismissed || [top isKindOfClass:C18FiveEditorController.class] ||
        ([top isKindOfClass:UINavigationController.class] && [((UINavigationController *)top).topViewController isKindOfClass:C18FiveEditorController.class])) return;
    @try {
        C18FiveEditorController *editor=[C18FiveEditorController new]; editor.shell=shell;
        UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:editor];
        nav.modalPresentationStyle=UIModalPresentationPageSheet;
        nav.presentationController.delegate=editor;
        C18FiveVoid(shell,NSSelectorFromString(@"controlConfigurationWillBegin"));
        [top presentViewController:nav animated:YES completion:nil];
    } @catch(NSException *exception) { C18FiveVoid(shell,NSSelectorFromString(@"controlConfigurationDidEnd")); }
}
@interface C18FivePressState : NSObject
@property(nonatomic) CGPoint origin;
@property(nonatomic) BOOL moved;
@property(nonatomic,weak) UIView *module;
@end
@implementation C18FivePressState @end
static void C18FiveDragPressHook(id self,SEL cmd,id gesture) {
    if (![gesture isKindOfClass:UIGestureRecognizer.class]) {
        if (gOriginalDragPress) gOriginalDragPress(self,cmd,gesture);
        return;
    }
    UIGestureRecognizer *press=gesture;
    // self is C18Shell, not the module; the real module is gesture.view.
    UIView *module=press.view;
    UIView *content=C18FiveObject(module,NSSelectorFromString(@"contentView"));
    Class connectivity=objc_getClass("C18ConnectivityView");
    BOOL target=connectivity && [content isKindOfClass:connectivity] &&
        C18FiveBool(module,NSSelectorFromString(@"isEditing"));
    C18FivePressState *state=objc_getAssociatedObject(press,&kC18EditorInstalled);
    if (press.state==UIGestureRecognizerStateBegan && target) {
        state=[C18FivePressState new]; state.module=module;
        state.origin=[press locationInView:module.window];
        objc_setAssociatedObject(press,&kC18EditorInstalled,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (state && module.window) {
        CGPoint point=[press locationInView:module.window];
        if (hypot(point.x-state.origin.x,point.y-state.origin.y)>10.0) state.moved=YES;
    }
    BOOL open=state && !state.moved && press.state==UIGestureRecognizerStateEnded;
    // Always let beta4 finish lift/drag cleanup; a real drag remains unchanged.
    if (gOriginalDragPress) gOriginalDragPress(self,cmd,gesture);
    if (press.state==UIGestureRecognizerStateEnded || press.state==UIGestureRecognizerStateCancelled || press.state==UIGestureRecognizerStateFailed) {
        objc_setAssociatedObject(press,&kC18EditorInstalled,nil,OBJC_ASSOCIATION_ASSIGN);
        if (open && target) {
            __weak UIView *weakModule=state.module;
            __weak id weakShell=self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),dispatch_get_main_queue(),^{ if (weakModule.window) C18FivePresentEditor(weakShell,weakModule); });
        }
    }
}
void C18FiveInstallEditor(void) {
    if (gC18EditorHooked) return;
    Class cls=objc_getClass("C18Shell"); SEL sel=@selector(handleModuleDragPress:);
    if (!cls || !class_getInstanceMethod(cls,sel)) {
        if (gC18EditorTries++<20) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),dispatch_get_main_queue(),^{ C18FiveInstallEditor(); });
        return;
    }
    gC18EditorHooked=YES;
    MSHookMessageEx(cls,sel,(IMP)C18FiveDragPressHook,(IMP *)&gOriginalDragPress);
}
__attribute__((constructor)) static void C18FiveEditorInit(void) {
    dispatch_async(dispatch_get_main_queue(),^{ C18FiveInstallEditor(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{ C18FiveInstallEditor(); });
}
