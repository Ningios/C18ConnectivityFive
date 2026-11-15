#import "C18Five.h"
#import "C18HookRuntime.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>
#import <dlfcn.h>

static NSString *C18ChoiceString(id value) { return [value isKindOfClass:NSString.class] ? value : @""; }
static UIImage *C18ChoiceNativeSymbol(NSString *name) {
    if (!name.length) return nil;
    UIImageSymbolConfiguration *configuration=[UIImageSymbolConfiguration configurationWithPointSize:25 weight:UIImageSymbolWeightSemibold scale:UIImageSymbolScaleSmall];
    // Original C18Symbol(NSString *, UIImageSymbolConfiguration *) also resolves
    // private glyphs (Bluetooth/AirDrop) and the original Symbols resource pack.
    typedef UIImage *(*SymbolFunction)(NSString *,UIImageSymbolConfiguration *);
    SymbolFunction native=(SymbolFunction)dlsym(RTLD_DEFAULT,"C18Symbol");
    UIImage *image=native ? native(name,configuration) : nil;
    if (!image) image=[UIImage systemImageNamed:name withConfiguration:configuration];
    SEL privateSymbol=NSSelectorFromString(@"_systemImageNamed:withConfiguration:");
    if (!image && [UIImage respondsToSelector:privateSymbol]) {
        NSMethodSignature *signature=[UIImage methodSignatureForSelector:privateSymbol];
        if (signature.numberOfArguments==4 && signature.methodReturnType[0]=='@' &&
            [signature getArgumentTypeAtIndex:2][0]=='@' && [signature getArgumentTypeAtIndex:3][0]=='@')
            image=((UIImage *(*)(id,SEL,NSString *,UIImageSymbolConfiguration *))objc_msgSend)(UIImage.class,privateSymbol,name,configuration);
    }
    return [image isKindOfClass:UIImage.class] ? [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] : nil;
}
static UIImage *C18ChoiceImage(NSDictionary *entry) {
    static NSCache<NSString *,UIImage *> *images;
    static NSDictionary<NSString *,NSString *> *symbols;
    static dispatch_once_t once;
    dispatch_once(&once,^{
        images=[NSCache new]; images.countLimit=256;
        symbols=@{@"builtin:0":@"airplane",@"builtin:1":@"airdrop",@"builtin:2":@"wifi",@"builtin:3":@"cellularbars",@"builtin:4":@"bluetooth",@"builtin:5":@"personalhotspot",@"builtin:6":@"network.connected.to.line.below.fill",
            @"0":@"square.grid.2x2",@"4":@"square.grid.2x2.fill",@"5":@"circle.grid.cross.fill",
            @"com.apple.control-center.AirDropModule":@"airdrop",@"com.apple.control-center.BluetoothModule":@"bluetooth",
            @"com.apple.control-center.WiFiModule":@"wifi",@"com.apple.control-center.VPNModule":@"network.connected.to.line.below.fill",
            @"com.apple.WiFiKit.PersonalHotspotControl":@"personalhotspot",@"com.apple.coretelephony.ToggleAirplaneMode":@"airplane",
            @"com.apple.coretelephony.ToggleCellularData":@"antenna.radiowaves.left.and.right",@"com.apple.shortcuts.ShortcutsControl":@"square.stack.3d.up",
            @"com.apple.shortcuts.OpenAppControl":@"app",@"com.apple.Translate.TranslationLiveActivityControl":@"character.bubble",
            @"com.apple.control-center.FlashlightModule":@"flashlight.on.fill",
            @"com.apple.control-center.CameraModule":@"camera.fill",@"com.apple.control-center.CalculatorModule":@"calculator",
            @"com.apple.control-center.AlarmModule":@"alarm.fill",@"com.apple.control-center.TimerModule":@"timer",
            @"com.apple.control-center.AppearanceModule":@"circle.lefthalf.filled",
            @"com.apple.control-center.LowPowerModule":@"battery.100",@"com.apple.control-center.MagnifierModule":@"plus.magnifyingglass",
            @"com.apple.accessibility.controlcenter.text.size":@"textformat.size",
            @"com.apple.mediaremote.controlcenter.airplaymirroring":@"rectangle.on.rectangle",
            @"com.apple.sharing.AskToAirDropControlCenterModule":@"airplayaudio",
            @"com.apple.replaykit.AudioConferenceControlCenterModule":@"mic.fill"};
    });
    NSString *identifier=C18ChoiceString(entry[@"identifier"]); if (!identifier.length) identifier=C18ChoiceString(entry[@"id"]);
    NSString *path=C18ChoiceString(entry[@"path"]);
    NSString *key=[NSString stringWithFormat:@"%@|%@",path,identifier];
    UIImage *image=[images objectForKey:key]; if (image) return image;
    if (path.length) {
        // Use the bundle's declared/original resources before any SF Symbol.
        NSMutableOrderedSet<NSString *> *names=[NSMutableOrderedSet orderedSet];
        if ([entry[@"iconNames"] isKindOfClass:NSArray.class]) for (id name in entry[@"iconNames"])
            if (C18ChoiceString(name).length) [names addObject:name];
        if (identifier.length) [names addObject:identifier];
        [names addObject:path.lastPathComponent.stringByDeletingPathExtension];
        [names addObjectsFromArray:@[@"SettingsIcon",@"ModuleIcon",@"Icon",@"icon",@"Glyph",@"glyph"]];
        NSBundle *bundle=[NSBundle bundleWithPath:path];
        for (NSString *name in names) {
            if (bundle) image=[UIImage imageNamed:name inBundle:bundle compatibleWithTraitCollection:nil];
            if (!image) for (NSString *scale in @[@"@3x",@"@2x",@""]) {
                NSString *file=[[name stringByDeletingPathExtension] stringByAppendingFormat:@"%@.png",scale];
                image=[UIImage imageWithContentsOfFile:[path stringByAppendingPathComponent:file]]; if (image) break;
            }
            if (image) break;
        }
        // A single shallow lookup on a cache miss, never a recursive scan per cell.
        if (!image) {
            NSArray *files=[[NSFileManager.defaultManager contentsOfDirectoryAtPath:path error:NULL] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
            for (NSString *file in files) {
                NSString *lower=file.lowercaseString;
                if (![lower.pathExtension isEqualToString:@"png"] || !([lower containsString:@"icon"] || [lower containsString:@"glyph"])) continue;
                image=[UIImage imageWithContentsOfFile:[path stringByAppendingPathComponent:file]]; if (image) break;
            }
        }
    }
    NSString *symbol=C18ChoiceString(entry[@"nativeSymbol"]);
    if (!image && symbol.length) image=C18ChoiceNativeSymbol(symbol);
    symbol=symbols[identifier];
    if (!image && symbol.length) image=C18ChoiceNativeSymbol(symbol);
    if (!image) image=[UIImage systemImageNamed:@"square.grid.2x2"];
    if (image) [images setObject:image forKey:key];
    return image;
}

@interface C18ChoiceCell : UICollectionViewCell
@property(nonatomic,strong) UIView *iconBackground;
@property(nonatomic,strong) UIImageView *iconView;
@property(nonatomic,strong) UILabel *titleLabel;
@property(nonatomic,strong) UIView *checkView;
- (void)setEntry:(NSDictionary *)entry selected:(BOOL)selected;
@end
@implementation C18ChoiceCell
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self=[super initWithFrame:frame])) return nil;
    self.contentView.backgroundColor=UIColor.clearColor;
    _iconBackground=[UIView new]; _iconBackground.backgroundColor=[UIColor colorWithWhite:1 alpha:.10];
    _iconBackground.layer.cornerCurve=kCACornerCurveContinuous; _iconBackground.layer.masksToBounds=YES; [self.contentView addSubview:_iconBackground];
    _iconView=[UIImageView new]; _iconView.tintColor=UIColor.whiteColor; _iconView.contentMode=UIViewContentModeScaleAspectFit;
    _iconView.clipsToBounds=YES; [_iconBackground addSubview:_iconView];
    self.isAccessibilityElement=YES;
    _titleLabel=[UILabel new]; _titleLabel.textColor=UIColor.whiteColor; _titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    _titleLabel.textAlignment=NSTextAlignmentCenter; _titleLabel.numberOfLines=2; _titleLabel.adjustsFontSizeToFitWidth=YES; _titleLabel.minimumScaleFactor=.72; [self.contentView addSubview:_titleLabel];
    _checkView=[[UIView alloc] initWithFrame:CGRectZero]; _checkView.backgroundColor=[UIColor colorWithRed:.16 green:.76 blue:.42 alpha:1]; _checkView.layer.cornerRadius=9; _checkView.hidden=YES;
    UILabel *check=[[UILabel alloc] initWithFrame:CGRectZero]; check.text=@"✓"; check.textColor=UIColor.whiteColor; check.font=[UIFont boldSystemFontOfSize:12]; check.textAlignment=NSTextAlignmentCenter; check.tag=1801; [_checkView addSubview:check]; [self.contentView addSubview:_checkView];
    return self;
}
- (void)setEntry:(NSDictionary *)entry selected:(BOOL)selected {
    _titleLabel.text=C18ChoiceString(entry[@"title"]); _iconView.image=C18ChoiceImage(entry);
    _checkView.hidden=!selected; _iconBackground.backgroundColor=[UIColor colorWithWhite:1 alpha:selected?.22:.10];
    _iconBackground.layer.borderWidth=selected?1.5:0; _iconBackground.layer.borderColor=[UIColor colorWithWhite:1 alpha:.70].CGColor;
    self.accessibilityLabel=_titleLabel.text; self.accessibilityTraits=UIAccessibilityTraitButton|(selected?UIAccessibilityTraitSelected:0);
}
- (void)layoutSubviews {
    [super layoutSubviews]; CGFloat w=self.contentView.bounds.size.width, side=MIN(56.0,MAX(32.0,w-8));
    _iconBackground.frame=CGRectMake((w-side)/2,6,side,side); _iconBackground.layer.cornerRadius=side/2;
    _iconView.frame=CGRectInset(_iconBackground.bounds,12,12); _iconView.layer.cornerRadius=4;
    _titleLabel.frame=CGRectMake(0,CGRectGetMaxY(_iconBackground.frame)+7,w,34);
    _checkView.frame=CGRectMake(CGRectGetMaxX(_iconBackground.frame)-14,4,18,18); ((UILabel *)[_checkView viewWithTag:1801]).frame=_checkView.bounds;
}
@end

@interface C18ChoiceHeader : UICollectionReusableView
@property(nonatomic,strong) UILabel *label;
@end
@implementation C18ChoiceHeader
- (instancetype)initWithFrame:(CGRect)frame { if (!(self=[super initWithFrame:frame])) return nil; _label=[UILabel new]; _label.textColor=[UIColor colorWithWhite:1 alpha:.68]; _label.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]; [self addSubview:_label]; return self; }
- (void)layoutSubviews { [super layoutSubviews]; _label.frame=CGRectInset(self.bounds,12,0); }
@end

@interface C18FiveChoiceController : UIViewController <UICollectionViewDataSource,UICollectionViewDelegateFlowLayout,UISearchBarDelegate>
@property(nonatomic,strong) NSArray<NSDictionary *> *groups;
@property(nonatomic,strong) NSArray<NSDictionary *> *visibleGroups;
@property(nonatomic,copy) NSString *selected;
@property(nonatomic,copy) BOOL (^choose)(NSString *identifier);
@property(nonatomic,strong) UISearchBar *searchBar;
@property(nonatomic,strong) UICollectionView *collectionView;
@property(nonatomic,strong) UILabel *emptyLabel;
- (void)filter:(NSString *)text;
@end
@implementation C18FiveChoiceController
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor=UIColor.clearColor;
    self.searchBar=[[UISearchBar alloc] initWithFrame:CGRectZero]; self.searchBar.placeholder=@"搜索模块"; self.searchBar.delegate=self; self.searchBar.searchBarStyle=UISearchBarStyleMinimal; self.searchBar.tintColor=UIColor.whiteColor;
    self.searchBar.searchTextField.textColor=UIColor.whiteColor; self.searchBar.searchTextField.returnKeyType=UIReturnKeySearch; [self.view addSubview:self.searchBar];
    UICollectionViewFlowLayout *layout=[UICollectionViewFlowLayout new]; layout.minimumInteritemSpacing=8; layout.minimumLineSpacing=10; layout.sectionInset=UIEdgeInsetsMake(4,12,20,12); layout.headerReferenceSize=CGSizeMake(0,36);
    self.collectionView=[[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout]; self.collectionView.backgroundColor=UIColor.clearColor; self.collectionView.dataSource=self; self.collectionView.delegate=self;
    self.collectionView.alwaysBounceVertical=YES; self.collectionView.keyboardDismissMode=UIScrollViewKeyboardDismissModeOnDrag; self.collectionView.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;
    self.emptyLabel=[UILabel new]; self.emptyLabel.text=@"没有匹配的模块"; self.emptyLabel.textColor=[UIColor colorWithWhite:1 alpha:.65]; self.emptyLabel.font=[UIFont systemFontOfSize:15]; self.emptyLabel.textAlignment=NSTextAlignmentCenter; self.collectionView.backgroundView=self.emptyLabel;
    [self.collectionView registerClass:C18ChoiceCell.class forCellWithReuseIdentifier:@"C18ChoiceCell"]; [self.collectionView registerClass:C18ChoiceHeader.class forSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:@"C18ChoiceHeader"]; [self.view addSubview:self.collectionView];
    [self filter:@""];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews]; UIEdgeInsets safe=self.view.safeAreaInsets; CGFloat width=self.view.bounds.size.width;
    self.searchBar.frame=CGRectMake(safe.left+10,safe.top+2,MAX(0,width-safe.left-safe.right-20),44);
    CGRect frame=CGRectMake(safe.left,CGRectGetMaxY(self.searchBar.frame),MAX(0,width-safe.left-safe.right),MAX(0,self.view.bounds.size.height-CGRectGetMaxY(self.searchBar.frame)));
    BOOL widthChanged=fabs(self.collectionView.bounds.size.width-frame.size.width)>.5; self.collectionView.frame=frame;
    self.collectionView.contentInset=UIEdgeInsetsMake(0,0,safe.bottom+12,0); self.collectionView.scrollIndicatorInsets=self.collectionView.contentInset;
    if (widthChanged) [self.collectionView.collectionViewLayout invalidateLayout];
}
- (void)filter:(NSString *)text {
    NSMutableArray *groups=[NSMutableArray array]; NSString *query=[C18ChoiceString(text) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    for (NSDictionary *group in self.groups) {
        NSMutableArray *entries=[NSMutableArray array];
        for (NSDictionary *entry in group[@"entries"]) {
            BOOL matches=!query.length;
            for (NSString *key in @[@"title",@"displayName",@"identifier",@"id"]) {
                NSString *field=C18ChoiceString(entry[key]);
                if (field.length && [field rangeOfString:query options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch].location!=NSNotFound) { matches=YES; break; }
            }
            if (matches) [entries addObject:entry];
        }
        if (entries.count) [groups addObject:@{@"title":C18ChoiceString(group[@"title"]),@"entries":entries}];
    }
    self.visibleGroups=groups; self.emptyLabel.hidden=groups.count>0; [self.collectionView reloadData];
}
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText { [self filter:searchText]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }
- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView { return self.visibleGroups.count; }
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section { return [self.visibleGroups[section][@"entries"] count]; }
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)ip { C18ChoiceCell *cell=[collectionView dequeueReusableCellWithReuseIdentifier:@"C18ChoiceCell" forIndexPath:ip]; NSDictionary *entry=self.visibleGroups[ip.section][@"entries"][ip.item]; [cell setEntry:entry selected:[entry[@"id"] isEqualToString:self.selected]]; return cell; }
- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)ip { C18ChoiceHeader *header=[collectionView dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:@"C18ChoiceHeader" forIndexPath:ip]; header.label.text=self.visibleGroups[ip.section][@"title"]; return header; }
- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)ip {
    UICollectionViewFlowLayout *flow=(UICollectionViewFlowLayout *)layout;
    CGFloat available=collectionView.bounds.size.width-flow.sectionInset.left-flow.sectionInset.right-flow.minimumInteritemSpacing*3;
    return CGSizeMake(MAX(1,floor(available/4.0)),108);
}
- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)ip {
    NSDictionary *entry=self.visibleGroups[ip.section][@"entries"][ip.item]; NSString *identifier=entry[@"id"];
    if (self.choose && self.choose(identifier)) { self.selected=identifier; [collectionView reloadData]; [self.navigationController popViewControllerAnimated:YES]; }
    else { UIAlertController *a=[UIAlertController alertControllerWithTitle:@"保存失败" message:@"原配置未更改，请重试。" preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }
}
@end

@interface C18FivePageTransition : NSObject <UIViewControllerAnimatedTransitioning>
@property(nonatomic) UINavigationControllerOperation operation;
@end
@implementation C18FivePageTransition
- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)context { return .22; }
- (void)animateTransition:(id<UIViewControllerContextTransitioning>)context {
    UIViewController *from=[context viewControllerForKey:UITransitionContextFromViewControllerKey];
    UIViewController *to=[context viewControllerForKey:UITransitionContextToViewControllerKey];
    UIView *outgoing=[context viewForKey:UITransitionContextFromViewKey] ?: from.view;
    UIView *incoming=[context viewForKey:UITransitionContextToViewKey] ?: to.view;
    if (!incoming || !outgoing || incoming==outgoing) { [context completeTransition:![context transitionWasCancelled]]; return; }
    CGAffineTransform originalTransform=incoming.transform;
    outgoing.hidden=YES; incoming.hidden=NO;
    incoming.frame=[context finalFrameForViewController:to];
    [context.containerView addSubview:incoming];
    // Animate only the new page. Transparent pages must not reveal another page's controls.
    CGFloat direction=self.operation==UINavigationControllerOperationPop ? -1 : 1;
    incoming.alpha=0;
    incoming.transform=CGAffineTransformTranslate(originalTransform,direction*16,0);
    [UIView animateWithDuration:[self transitionDuration:context] delay:0
        options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionCurveEaseOut
        animations:^{ incoming.alpha=1; incoming.transform=originalTransform; }
        completion:^(BOOL finished) {
            BOOL completed=![context transitionWasCancelled];
            incoming.alpha=1; incoming.transform=originalTransform;
            incoming.hidden=!completed; outgoing.hidden=completed;
            if (completed) [outgoing removeFromSuperview];
            else [incoming removeFromSuperview];
            [context completeTransition:completed];
        }];
}
@end

@interface C18FiveNavigationController : UINavigationController <UINavigationControllerDelegate>
@property(nonatomic,strong) UIVisualEffectView *glass;
@property(nonatomic,weak) UIViewController *displayedPage;
@property(nonatomic,weak) UIViewController *transitionPage;
- (void)showOnlyPage:(UIViewController *)page;
@end
@implementation C18FiveNavigationController
- (void)showOnlyPage:(UIViewController *)page {
    if (!page) return;
    UIViewController *previous=self.displayedPage;
    if (previous!=page) previous.viewIfLoaded.hidden=YES;
    for (UIViewController *candidate in self.viewControllers)
        if (candidate.isViewLoaded) candidate.view.hidden=(candidate!=page);
    page.view.hidden=NO;
    self.displayedPage=page;
}
- (id<UIViewControllerAnimatedTransitioning>)navigationController:(UINavigationController *)navigationController
        animationControllerForOperation:(UINavigationControllerOperation)operation
        fromViewController:(UIViewController *)fromViewController toViewController:(UIViewController *)toViewController {
    C18FivePageTransition *transition=[C18FivePageTransition new]; transition.operation=operation;
    return transition;
}
- (void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated {
    self.transitionPage=viewController;
    [self showOnlyPage:viewController];
}
- (void)navigationController:(UINavigationController *)navigationController didShowViewController:(UIViewController *)viewController animated:(BOOL)animated {
    self.transitionPage=nil;
    [self showOnlyPage:viewController];
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.delegate=self;
    self.view.backgroundColor=UIColor.clearColor;
    // The glass belongs to the entire sheet, so pushed pages share the backdrop.
    self.glass=[[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark]];
    self.glass.backgroundColor=[UIColor colorWithWhite:.38 alpha:.22]; self.glass.userInteractionEnabled=NO;
    self.glass.frame=self.view.bounds; self.glass.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.view insertSubview:self.glass atIndex:0];
    self.view.layer.cornerRadius=32; self.view.layer.cornerCurve=kCACornerCurveContinuous;
    self.view.layer.maskedCorners=kCALayerMinXMinYCorner|kCALayerMaxXMinYCorner; self.view.clipsToBounds=YES;
    UINavigationBarAppearance *appearance=[UINavigationBarAppearance new]; [appearance configureWithTransparentBackground];
    appearance.titleTextAttributes=@{NSForegroundColorAttributeName:UIColor.whiteColor};
    appearance.largeTitleTextAttributes=appearance.titleTextAttributes; appearance.shadowColor=UIColor.clearColor;
    self.navigationBar.standardAppearance=appearance; self.navigationBar.scrollEdgeAppearance=appearance; self.navigationBar.compactAppearance=appearance;
    self.navigationBar.translucent=YES; self.navigationBar.tintColor=UIColor.whiteColor;
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews]; self.glass.frame=self.view.bounds;
    if (self.glass.superview==self.view) [self.view sendSubviewToBack:self.glass];
    if (!self.transitionCoordinator && !self.transitionPage) [self showOnlyPage:self.topViewController];
}
@end

extern void MSHookMessageEx(Class, SEL, IMP, IMP *);
static char kC18EditorInstalled;
static BOOL gC18EditorHooked;
static void (*gOriginalDragPress)(id,SEL,id);

@interface C18FiveEditorController : UITableViewController <UIAdaptivePresentationControllerDelegate>
@property(nonatomic,strong) NSArray<NSDictionary *> *catalog;
@property(nonatomic) NSInteger mode;
@property(nonatomic,strong) NSArray<NSString *> *slots;
@property(nonatomic,weak) id shell;
@property(nonatomic) BOOL sessionEnded;
@property(nonatomic) BOOL catalogLoaded;
- (void)endConfiguration;
@end

@implementation C18FiveEditorController
- (instancetype)init {
    if ((self=[super initWithStyle:UITableViewStyleInsetGrouped])) {
        self.title=@"自定义五键";
        NSArray *saved=nil; NSInteger mode=0; C18FiveRead(&mode,&saved); _mode=mode; _slots=saved;
        // Directory/Info.plist enumeration is performed once off the UI thread.
        __weak C18FiveEditorController *weakSelf=self;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
            NSArray<NSDictionary *> *catalog=C18FiveCatalog();
            dispatch_async(dispatch_get_main_queue(),^{
                C18FiveEditorController *editor=weakSelf; if (!editor || editor.sessionEnded) return;
                editor.catalog=catalog; editor.catalogLoaded=YES;
                if (editor.isViewLoaded) [editor.tableView reloadData];
            });
        });
        self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)];
        self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor=UIColor.clearColor;
    self.tableView.separatorColor=[UIColor colorWithWhite:1 alpha:.12];
    self.tableView.backgroundView=nil;
    self.tableView.rowHeight=56;
    self.tableView.sectionHeaderHeight=40;
    // UISheetPresentationController owns the fixed grabber above the navigation bar.
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
    cell.backgroundColor=[UIColor colorWithWhite:1 alpha:.055];
    cell.textLabel.textColor=UIColor.whiteColor; cell.detailTextLabel.textColor=[UIColor colorWithWhite:1 alpha:.68];
    BOOL ready=indexPath.section==0 || self.catalogLoaded;
    cell.accessoryType=ready?UITableViewCellAccessoryDisclosureIndicator:UITableViewCellAccessoryNone;
    cell.userInteractionEnabled=ready;
    if (indexPath.section==0) {
        cell.textLabel.text=@"布局模式";
        cell.detailTextLabel.text=_mode==5?@"自定义五键":(_mode==4?@"自定义四键":@"原版布局");
    } else {
        cell.textLabel.text=[NSString stringWithFormat:@"槽位%ld",(long)indexPath.row+1];
        NSString *slot=_slots[indexPath.row]; NSString *title=slot;
        for (NSDictionary *entry in _catalog) if ([entry[@"id"] isEqual:slot]) { title=entry[@"title"]; break; }
        cell.detailTextLabel.text=self.catalogLoaded?title:@"正在载入模块…";
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    if ([view isKindOfClass:UITableViewHeaderFooterView.class]) ((UITableViewHeaderFooterView *)view).textLabel.textColor=[UIColor colorWithWhite:1 alpha:.68];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tableView deselectRowAtIndexPath:ip animated:YES];
    if (ip.section!=0 && !self.catalogLoaded) return;
    C18FiveChoiceController *choice=[C18FiveChoiceController new];
    __weak C18FiveEditorController *weakSelf=self;
    if (ip.section==0) {
        choice.title=@"布局模式"; choice.selected=[@(_mode) stringValue];
        choice.groups=@[
            @{@"title":@"布局模式",@"entries":@[
                @{@"id":@"0",@"title":@"原版布局"},@{@"id":@"4",@"title":@"自定义四键"}]},
            @{@"title":@"自定义五键",@"entries":@[
                @{@"id":@"5",@"title":@"自定义五键"}]}];
        choice.choose=^BOOL(NSString *value) {
            C18FiveEditorController *editor=weakSelf; if (!editor) return NO;
            NSInteger mode=[value integerValue];
            if (!C18FiveWrite(mode,editor.slots)) return NO;
            editor.mode=mode; [editor.tableView reloadData]; return YES;
        };
    } else {
        NSInteger slot=ip.row; choice.title=[NSString stringWithFormat:@"选择槽位%ld",(long)slot+1]; choice.selected=_slots[slot];
        NSMutableArray *groups=[NSMutableArray array];
        for (NSString *name in @[@"连接功能",@"系统模块",@"CC+"]) {
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
        [top isKindOfClass:C18FiveNavigationController.class] || [top.navigationController isKindOfClass:C18FiveNavigationController.class] ||
        ([top isKindOfClass:UINavigationController.class] && [((UINavigationController *)top).topViewController isKindOfClass:C18FiveEditorController.class])) return;
    @try {
        C18FiveEditorController *editor=[C18FiveEditorController new]; editor.shell=shell;
        C18FiveNavigationController *nav=[[C18FiveNavigationController alloc] initWithRootViewController:editor];
        nav.modalPresentationStyle=UIModalPresentationPageSheet;
        nav.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
        UISheetPresentationController *sheet=nav.sheetPresentationController;
        sheet.detents=@[UISheetPresentationControllerDetent.mediumDetent,UISheetPresentationControllerDetent.largeDetent];
        sheet.selectedDetentIdentifier=UISheetPresentationControllerDetentIdentifierLarge;
        sheet.preferredCornerRadius=32; sheet.prefersGrabberVisible=YES;
        sheet.prefersScrollingExpandsWhenScrolledToEdge=YES; sheet.prefersEdgeAttachedInCompactHeight=YES;
        sheet.widthFollowsPreferredContentSizeWhenEdgeAttached=YES;
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
    Class standalone=objc_getClass("C18FiveStandaloneView");
    BOOL target=((connectivity && [content isKindOfClass:connectivity]) ||
        (standalone && [content isKindOfClass:standalone])) &&
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
    if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(),^{ C18FiveInstallEditor(); }); return; }
    if (gC18EditorHooked) return;
    Class cls=objc_getClass("C18Shell"); SEL sel=@selector(handleModuleDragPress:);
    if (!C18HookCanInstall(cls,sel,"v",@[@"@"])) return;
    // This once token belongs only to the drag-press hook, never to a retry block.
    static dispatch_once_t editorHookOnce;
    dispatch_once(&editorHookOnce,^{
        MSHookMessageEx(cls,sel,(IMP)C18FiveDragPressHook,(IMP *)&gOriginalDragPress);
        gC18EditorHooked=YES;
    });
}
// Installed by the metadata-only startup registrar and again when Shell presents.
// No separate constructor, bundle prewarm, or timer-driven startup work.
