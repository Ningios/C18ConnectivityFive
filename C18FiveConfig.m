#import "C18Five.h"
#import "C18Localization.h"
#import "C18HookRuntime.h"
#import "C18RemovedModules.h"
#import <CoreFoundation/CoreFoundation.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>

NSString * const C18FiveDomain = @"com.ning.c18connectivity";
const char * const C18FiveReload = "com.ning.c18connectivity.reload";
static NSString * const kNames[7] = {@"飞行模式",@"隔空投送",@"Wi-Fi",@"蜂窝数据",@"蓝牙",@"个人热点",@"VPN"};
static NSString *C18FiveChineseTitle(NSString *identifier, NSString *fallback, NSString *moduleName) {
    static NSDictionary<NSString *,NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once,^{ names=@{
        @"com.apple.control-center.AirDropModule":@"隔空投送",
        @"com.apple.control-center.BluetoothModule":@"蓝牙",
        @"com.evgeniy558.controlcenter18.connectivity2":@"连接中心",
        @"com.apple.shortcuts.OpenAppControl":@"打开 App",
        @"com.apple.WiFiKit.PersonalHotspotControl":@"个人热点",
        @"com.apple.shortcuts.ShortcutsControl":@"快捷指令",
        @"com.apple.coretelephony.ToggleAirplaneMode":@"飞行模式",
        @"com.apple.coretelephony.ToggleCellularData":@"蜂窝数据",
        @"com.apple.Translate.TranslationLiveActivityControl":@"翻译",
        @"com.apple.control-center.VPNModule":@"VPN",
        @"com.apple.control-center.WiFiModule":@"Wi-Fi",
        @"com.apple.control-center.FlashlightModule":@"手电筒",
        @"com.apple.control-center.CameraModule":@"相机",
        @"com.apple.control-center.CalculatorModule":@"计算器",
        @"com.apple.control-center.TimerModule":@"计时器",
        @"com.apple.control-center.AlarmModule":@"闹钟",
        @"com.apple.control-center.ScreenRecordingModule":@"屏幕录制",
        @"com.apple.control-center.LowPowerModule":@"低电量模式",
        @"com.apple.control-center.OrientationLockModule":@"竖排方向锁定",
        @"com.apple.control-center.SilentModeModule":@"静音模式",
        @"com.apple.control-center.AppearanceModule":@"深色模式",
        @"com.apple.control-center.MagnifierModule":@"放大器",
        @"com.apple.control-center.NotesModule":@"备忘录",
        @"com.apple.control-center.QRCodeModule":@"扫码器",
        @"com.apple.control-center.WalletModule":@"钱包",
        @"com.apple.control-center.AppleTVRemoteModule":@"Apple TV 遥控器",
        @"com.apple.control-center.AccessibilityShortcutsModule":@"辅助功能快捷键",
        @"com.apple.control-center.VoiceMemosModule":@"语音备忘录",
        @"com.apple.control-center.MusicRecognitionModule":@"音乐识别",
        @"netskao.alipayscan":@"支付宝扫码", @"com.kdt.caperfhudcc":@"实时帧率",
        @"com.skypain.ccautobrightness":@"自动亮度", @"netskao.ccbadgeclear":@"清理角标",
        @"netskao.cccellularratemodule":@"蜂窝4/5G切换", @"com.netskao.cclifttowake":@"抬起唤醒",
        @"com.skypain.cclocation":@"定位", @"com.skypain.cclockscreen":@"锁屏",
        @"com.skypain.ccrespring":@"注销", @"netskao.ccsim":@"蜂窝管理",
        @"com.skypain.ccscreenshot":@"截屏", @"com.skypain.ccsettrings":@"CC 设置",
        @"netskao.ccswitchdatamodule":@"数据切换", @"com.skypain.ccvpn":@"CC VPN",
        @"com.KingPuffaddi.control-center.CCVibration":@"振动", @"com.jailbreak365.control-center.MuteModuleCC":@"静音",
        @"netskao.quantumultxlauncher":@"Quantumult X", @"netskao.tinydisplaymodule":@"迷你亮度",
        @"netskao.tinymediaaudio":@"迷你音量", @"com.mtac.uptimemodule":@"开机计时",
        @"com.sop.cpumagicrootless":@"实时 CPU", @"com.zqbb.qswx":@"微信付款码", @"com.zqbb.qszfb":@"支付宝付款码",
        @"netskao.wechatscan":@"微信扫码", @"com.jailbreak365.control-center.FilzaModule":@"打开 Filza",
        @"com.jailbreak365.control-center.SafariModule":@"打开 Safari", @"com.jailbreak365.control-center.SileoModule":@"打开 Sileo",
        @"com.jailbreak365.control-center.TelegramModule":@"打开 Telegram", @"com.jailbreak365.control-center.TwitterModule":@"打开 Twitter",
        @"com.jailbreak365.control-center.YouTubeModule":@"打开 YouTube", @"netskao.tinymediaaudiomodule":@"迷你音量"
    }; });
    NSString *title=[identifier isKindOfClass:NSString.class] ? names[identifier] : nil;
    if (title.length) return title;
    // Bundle filenames are stable aliases for system modules with non-control-center IDs.
    static NSDictionary<NSString *,NSString *> *systemNames;
    static dispatch_once_t systemOnce;
    dispatch_once(&systemOnce,^{ systemNames=@{
        @"AccessibilityGuidedAccessControlCenterModule":@"引导式访问",
        @"AccessibilityShorcutsModule":@"辅助功能快捷键", @"AccessibilityShortcutsModule":@"辅助功能快捷键",
        @"AccessibilitySoundDetectionControlCenterModule":@"声音识别",
        @"AccessibilityTextSizeModule":@"文字大小", @"AirPlayMirroringModule":@"屏幕镜像",
        @"AskToAirDropControlCenterModule":@"隔空投送接收询问", @"AudioConferenceControlCenterModule":@"麦克风模式",
        @"VideoConferenceControlCenterModule":@"视频效果", @"ContinuousExposeModule":@"台前调度",
        @"FeedbackAssistantModule":@"反馈助理", @"HomeControlCenterModule":@"家庭",
        @"HomeControlCenterCompactModule":@"家庭", @"KeyboardBrightnessModule":@"键盘亮度",
        @"MuteModule":@"静音模式", @"NFCControlCenterModule":@"NFC 标签读取器",
        @"PerformanceTraceModule":@"性能记录", @"PingMyWatchControlCenterUI":@"呼叫 Apple Watch",
        @"QuickNoteModule":@"快速备忘录", @"SystemQuickNoteModule":@"快速备忘录",
        @"ReplayKitModule":@"屏幕录制", @"ShazamModule":@"音乐识别",
        @"SilenceCallsCCWidget":@"静音未知来电", @"SpokenNotificationsModule":@"播报通知",
        @"StopwatchModule":@"秒表", @"TVRemoteModule":@"Apple TV 遥控器"
    }; });
    BOOL apple=[identifier.lowercaseString hasPrefix:@"com.apple."];
    NSString *systemTitle=apple ? systemNames[moduleName?:@""] : nil;
    if (systemTitle.length) return systemTitle;
    // Unknown third-party modules, app brands and author labels retain their original display name.
    if ([fallback isKindOfClass:NSString.class] && fallback.length) return fallback;
    return [identifier isKindOfClass:NSString.class] && identifier.length ? identifier : @"未命名模块";
}
NSString *C18FiveDisplayTitle(NSString *identifier,NSString *fallback,NSString *moduleName) { return C18FiveChineseTitle(identifier,fallback,moduleName); }
NSString *C18FiveBuiltinID(NSInteger i) { return i>=0 && i<7 ? [NSString stringWithFormat:@"builtin:%ld",(long)i] : nil; }
NSInteger C18FiveBuiltinIndex(NSString *s) {
    if (![s isKindOfClass:NSString.class]) return NSNotFound;
    for (NSInteger i=0;i<7;i++) if ([s isEqualToString:C18FiveBuiltinID(i)]) return i;
    return NSNotFound;
}
NSString *C18FiveModuleID(NSString *s) {
    return [s hasPrefix:@"module:"] && s.length>7 ? [s substringFromIndex:7] : nil;
}
NSArray *C18FiveDefaultSlots(void) { return @[@"builtin:4",@"builtin:2",@"builtin:3",@"builtin:1",@"builtin:0"]; }
id C18FiveGet(id object, NSString *key) {
    @try { return object ? [object valueForKey:key] : nil; } @catch(NSException *e) { return nil; }
}
id C18FiveObject(id object, SEL sel) {
    if (!object) return nil;
    Method method=class_getInstanceMethod(object_getClass(object),sel);
    if (!C18HookSignatureMatches(method,"@",@[]) && !C18HookSignatureMatches(method,"#",@[])) return nil;
    return ((id(*)(id,SEL))objc_msgSend)(object,sel);
}
BOOL C18FiveBool(id object, SEL sel) {
    if (!object || !C18HookCanInstall(object_getClass(object),sel,"B",@[])) return NO;
    return ((BOOL(*)(id,SEL))objc_msgSend)(object,sel);
}
void C18FiveVoid(id object, SEL sel) {
    if (object && C18HookCanInstall(object_getClass(object),sel,"v",@[])) ((void(*)(id,SEL))objc_msgSend)(object,sel);
}
void C18FiveSetInteger(id object, SEL sel, NSInteger v) {
    if (object && C18HookCanInstall(object_getClass(object),sel,"v",@[@"q"])) ((void(*)(id,SEL,NSInteger))objc_msgSend)(object,sel,v);
}
static BOOL C18FiveValid(NSInteger mode, NSArray *slots) {
    if (mode!=0 && mode!=4 && mode!=5) return NO;
    if (![slots isKindOfClass:NSArray.class] || slots.count!=5) return NO;
    NSMutableSet *seen=[NSMutableSet set];
    for (id slot in slots) {
        if (![slot isKindOfClass:NSString.class] || [seen containsObject:slot]) return NO;
        if (C18FiveBuiltinIndex(slot)==NSNotFound && !C18FiveModuleID(slot)) return NO;
        [seen addObject:slot];
    }
    return YES;
}
BOOL C18FiveRead(NSInteger *mode, NSArray **slots) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)C18FiveDomain);
    id saved=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Configuration"),(__bridge CFStringRef)C18FiveDomain));
    NSInteger m=0; NSArray *s=C18FiveDefaultSlots();
    if ([saved isKindOfClass:NSDictionary.class]) {
        id value=saved[@"mode"]; id items=saved[@"slots"];
        if (![value respondsToSelector:@selector(integerValue)] || !C18FiveValid([value integerValue],items)) {
            if (mode) *mode=0; if (slots) *slots=s; return NO;
        }
        m=[value integerValue]; s=[items copy];
    } else if (!saved) {
        // Migrate the initial seven-item integer draft without rewriting its file.
        id old=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Mode"),(__bridge CFStringRef)C18FiveDomain));
        if ([old respondsToSelector:@selector(integerValue)]) {
            m=[old integerValue]; NSMutableArray *converted=[s mutableCopy];
            for (NSInteger i=0;i<5;i++) {
                NSString *key=[NSString stringWithFormat:@"Slot%ld",(long)(i+1)];
                id v=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,(__bridge CFStringRef)C18FiveDomain));
                if (v && [v respondsToSelector:@selector(integerValue)]) {
                    NSString *slot=C18FiveBuiltinID([v integerValue]);
                    if (!slot) { m=0; break; }
                    converted[i]=slot;
                }
            }
            if (C18FiveValid(m,converted)) s=[converted copy]; else m=0;
        }
    }
    // A deleted third-party module may have been assigned to a custom slot.
    // Replace only those slots, preserving every other configured item.
    NSMutableArray *clean=[s mutableCopy];BOOL pruned=NO;
    NSMutableSet *used=[NSMutableSet setWithArray:s];
    for (NSUInteger i=0;i<clean.count;i++) if (C18RemovedModuleID(C18FiveModuleID(clean[i]))) {
        for (NSInteger builtin=0;builtin<7;builtin++) {
            NSString *replacement=C18FiveBuiltinID(builtin);
            if (![used containsObject:replacement]) { clean[i]=replacement;[used addObject:replacement];pruned=YES;break; }
        }
    }
    if (pruned) { s=[clean copy]; C18FiveWrite(m,s); }
    if (mode) *mode=m; if (slots) *slots=s;
    return YES;
}
BOOL C18FiveWrite(NSInteger mode, NSArray *slots) {
    if (!C18FiveValid(mode,slots)) return NO;
    NSDictionary *value=@{@"mode":@(mode),@"slots":[slots copy],@"version":@2};
    CFPreferencesSetAppValue(CFSTR("Configuration"),(__bridge CFPropertyListRef)value,(__bridge CFStringRef)C18FiveDomain);
    BOOL ok=CFPreferencesAppSynchronize((__bridge CFStringRef)C18FiveDomain);
    if (ok) notify_post(C18FiveReload);
    return ok;
}
BOOL C18FiveExcluded(NSString *identifier, NSString *principal) {
    NSString *s=[[NSString stringWithFormat:@"%@ %@",identifier?:@"",principal?:@""] lowercaseString];
    if (C18RemovedModuleID(identifier)) return YES;
    // No slider, player, live statistics, grouped panel, or configurable custom card.
    NSArray *blocked=@[@"displaymodule",@"tinydisplay",@"tinymediaaudio",@"controlcenter.audio",@"nowplaying",@"mediacontrol",@"volumemodule",@"brightnessmodule",@"uptime",@"cpumagic",@"caperfhud",@"connectivity",@"focusuimodule",@"home.compact",@"homecontrol",@"text-size",@"hearing"];
    for (NSString *part in blocked) if ([s containsString:part]) return YES;
    return NO;
}
static void C18FiveAddRoot(NSMutableArray *roots, NSString *prefix) {
    if (![prefix isKindOfClass:NSString.class]) return;
    for (NSArray *item in @[@[@"/Library/ControlCenter/Bundles",@"CC+"],@[@"/Library/ControlCenter18/Bundles",@"系统模块"]]) {
        NSArray *root=@[[prefix stringByAppendingString:item[0]],item[1]];
        if (![roots containsObject:root]) [roots addObject:root];
    }
}
static void C18FiveAddImageRoots(NSMutableArray *roots, NSString *imagePath) {
    if (![imagePath isKindOfClass:NSString.class]) return;
    // RootHide relocates MobileSubstrate libraries into usr/lib/TweakInject.
    for (NSString *marker in @[@"/usr/lib/TweakInject/",@"/Library/MobileSubstrate/",@"/Library/PreferenceBundles/"]) {
        NSRange r=[imagePath rangeOfString:marker];
        if (r.location!=NSNotFound) {
            C18FiveAddRoot(roots,[imagePath substringToIndex:r.location]);
            return;
        }
    }
}
static NSString *C18FiveBundleGroup(NSString *identifier, NSString *path) {
    // RootHide aliases and relocated bundles must not change a module's origin.
    if ([identifier.lowercaseString hasPrefix:@"com.apple."]) return @"系统模块";
    NSString *resolved=path.stringByResolvingSymlinksInPath.stringByStandardizingPath;
    if ([resolved hasPrefix:@"/System/Library/ControlCenter/Bundles/"]) return @"系统模块";
    return @"CC+";
}
static NSInteger C18FiveEntryPriority(NSDictionary *entry) {
    NSString *path=entry[@"path"];
    // Prefer CC18's compatible implementation over the same stock system ID.
    NSInteger score=[path containsString:@"/Library/ControlCenter18/Bundles/"] ? 300 :
        ([path hasPrefix:@"/System/Library/ControlCenter/Bundles/"] ? 200 : 100);
    if ([entry[@"principal"] length]) score+=10;
    return score;
}
static NSDictionary *C18FiveBundleEntry(NSString *path) {
    NSDictionary *info=[NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@"Info.plist"]];
    NSString *bid=info[@"CFBundleIdentifier"], *principal=info[@"NSPrincipalClass"];
    if (![principal isKindOfClass:NSString.class]) principal=nil;
    if (![bid isKindOfClass:NSString.class] || !bid.length || C18FiveExcluded(bid,principal)) return nil;
    if ([info[@"UIDeviceFamily"] isKindOfClass:NSArray.class] && ![info[@"UIDeviceFamily"] containsObject:@1]) return nil;
    // Read localization data as files. NSBundle localization may dlopen/dlclose
    // frameworks and initialize NSLocale while another dylib is initializing.
    NSDictionary *localized=nil;
    for (NSString *language in @[@"zh-Hans",@"zh_CN",@"zh",@"Base",@"en"]) {
        NSString *file=[path stringByAppendingPathComponent:[language stringByAppendingString:@".lproj/InfoPlist.strings"]];
        NSDictionary *strings=[NSDictionary dictionaryWithContentsOfFile:file];
        if (strings.count) { localized=strings; break; }
    }
    NSString *displayName=nil;
    for (id value in @[localized[@"CFBundleDisplayName"]?:@"",localized[@"CFBundleName"]?:@"",info[@"CFBundleDisplayName"]?:@"",info[@"CFBundleName"]?:@"",bid]) {
        if ([value isKindOfClass:NSString.class] && [value length]) { displayName=value; break; }
    }
    NSMutableOrderedSet<NSString *> *iconNames=[NSMutableOrderedSet orderedSet];
    for (NSString *key in @[@"CCSModuleIconName",@"CCSModuleGlyphName",@"CFBundleIconFile"]) {
        id name=info[key]; if ([name isKindOfClass:NSString.class] && [name length]) [iconNames addObject:name];
    }
    id files=info[@"CFBundleIconFiles"];
    for (NSString *key in @[@"CFBundleIcons",@"CFBundleIcons~iphone"]) {
        id icons=info[key]; id primary=[icons isKindOfClass:NSDictionary.class] ? icons[@"CFBundlePrimaryIcon"] : nil;
        id declared=[primary isKindOfClass:NSDictionary.class] ? primary[@"CFBundleIconFiles"] : nil;
        if ([declared isKindOfClass:NSArray.class]) for (id name in declared)
            if ([name isKindOfClass:NSString.class] && [name length]) [iconNames addObject:name];
    }
    if ([files isKindOfClass:NSArray.class]) for (id name in files)
        if ([name isKindOfClass:NSString.class] && [name length]) [iconNames addObject:name];
    NSString *moduleName=path.lastPathComponent.stringByDeletingPathExtension;
    NSDictionary *descriptor=[info[@"CCUISettingsIconDescriptor"] isKindOfClass:NSDictionary.class] ? info[@"CCUISettingsIconDescriptor"] : nil;
    NSDictionary *moduleImage=[descriptor[@"ModuleImage"] isKindOfClass:NSDictionary.class] ? descriptor[@"ModuleImage"] : nil;
    NSString *nativeSymbol=moduleImage[@"InternalSymbolName"] ?: moduleImage[@"SymbolName"];
    if (![nativeSymbol isKindOfClass:NSString.class]) nativeSymbol=@"";
    for (NSString *key in @[@"ImageName",@"AssetName"]) {
        id name=moduleImage[key]; if ([name isKindOfClass:NSString.class] && [name length]) [iconNames addObject:name];
    }
    return @{@"id":[@"module:" stringByAppendingString:bid],@"identifier":bid,@"title":C18FiveChineseTitle(bid,displayName,moduleName),@"displayName":displayName?:bid,@"group":C18FiveBundleGroup(bid,path),@"path":path,@"principal":principal?:@"",@"iconNames":iconNames.array,@"moduleName":moduleName,@"nativeSymbol":nativeSymbol};
}
// Only immutable snapshot references cross the cache lock. All loader, bundle,
// localization, sorting and filesystem calls run AFTER the lock is released.
static NSDictionary *gC18FiveCatalogSnapshot;
static CFAbsoluteTime gC18FiveCatalogPublishedAt;
static NSObject *C18FiveCatalogLock(void) {
    static NSObject *lock; static dispatch_once_t once;
    dispatch_once(&once,^{ lock=[NSObject new]; });
    return lock;
}
static NSDictionary *C18FiveReadCatalogSnapshot(void) {
    NSDictionary *snapshot;
    @synchronized(C18FiveCatalogLock()) { snapshot=gC18FiveCatalogSnapshot; }
    return snapshot;
}
static NSDictionary *C18FivePublishCatalogSnapshot(NSDictionary *candidate) {
    CFAbsoluteTime checked=[candidate[@"checked"] doubleValue];
    __attribute__((objc_precise_lifetime)) NSDictionary *previous;
    NSDictionary *selected;
    @synchronized(C18FiveCatalogLock()) {
        previous=gC18FiveCatalogSnapshot;
        // Scans can overlap. Compare primitives only, then swap immutable refs.
        if (gC18FiveCatalogPublishedAt>checked) selected=previous;
        else {
            gC18FiveCatalogSnapshot=candidate;
            gC18FiveCatalogPublishedAt=checked; selected=candidate;
        }
    }
    // Old graph destruction also runs outside the synchronization scope.
    (void)previous;
    return selected;
}
static NSDictionary *C18FiveCatalogSnapshot(void) {
    CFAbsoluteTime now=CFAbsoluteTimeGetCurrent();
    NSDictionary *cached=C18FiveReadCatalogSnapshot();
    if (cached && now-[cached[@"checked"] doubleValue]<5.0) return cached;
    NSMutableArray *roots=[NSMutableArray array];
    Dl_info ownImage={0};
    if (dladdr((const void *)&C18FiveCatalog,&ownImage) && ownImage.dli_fname)
        C18FiveAddImageRoots(roots,@(ownImage.dli_fname));
    Class cls=objc_getClass("C18ConnectivityView"); const char *image=cls?class_getImageName(cls):NULL;
    if (image) C18FiveAddImageRoots(roots,@(image));
    // Both known loaded images already identify the current RootHide prefix.
    // Do not enumerate every dyld image while initializing the module catalog.
    C18FiveAddRoot(roots,@""); C18FiveAddRoot(roots,@"/var/jb");
    [roots addObject:@[@"/System/Library/ControlCenter/Bundles",@"系统模块"]];
    NSMutableArray *signature=[NSMutableArray array];
    for (NSArray *root in roots) {
        NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:root[0] error:NULL];
        [signature addObject:@[root[0],attrs[NSFileModificationDate]?:NSNull.null]];
    }
    NSArray *entries; NSDictionary *byID;
    if (cached && [signature isEqual:cached[@"roots"]]) {
        entries=cached[@"entries"]; byID=cached[@"byID"];
    } else {
        NSMutableArray *result=[NSMutableArray array];
        NSMutableDictionary<NSString *,NSDictionary *> *modules=[NSMutableDictionary dictionary];
        for (NSInteger i=0;i<7;i++) [result addObject:@{@"id":C18FiveBuiltinID(i),@"title":kNames[i],@"group":@"连接功能"}];
        for (NSArray *root in roots) {
            NSArray *names=[[NSFileManager.defaultManager contentsOfDirectoryAtPath:root[0] error:NULL]
                sortedArrayUsingComparator:^NSComparisonResult(NSString *a,NSString *b) {
                    return [a compare:b options:NSLiteralSearch];
                }];
            for (NSString *name in names) {
                if (![name.pathExtension isEqualToString:@"bundle"]) continue;
                NSDictionary *entry=C18FiveBundleEntry([root[0] stringByAppendingPathComponent:name]);
                if (!entry) continue;
                NSDictionary *previous=modules[entry[@"id"]];
                if (!previous || C18FiveEntryPriority(entry)>C18FiveEntryPriority(previous)) modules[entry[@"id"]]=entry;
            }
        }
        NSArray *ordered=[modules.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) {
            NSComparisonResult order=[a[@"title"] compare:b[@"title"] options:NSLiteralSearch];
            return order==NSOrderedSame?[a[@"id"] compare:b[@"id"] options:NSLiteralSearch]:order;
        }];
        [result addObjectsFromArray:ordered];
        NSMutableDictionary *index=[NSMutableDictionary dictionaryWithCapacity:result.count];
        for (NSDictionary *entry in result) index[entry[@"id"]]=entry;
        entries=[result copy]; byID=[index copy];
    }
    NSDictionary *snapshot=@{@"entries":entries,@"byID":byID,@"roots":[signature copy],@"checked":@(now)};
    return C18FivePublishCatalogSnapshot(snapshot);
}
NSArray<NSDictionary *> *C18FiveCatalog(void) { return C18FiveCatalogSnapshot()[@"entries"]; }
NSDictionary *C18FiveEntry(NSString *slotID) {
    if (![slotID isKindOfClass:NSString.class] || !slotID.length) return nil;
    return C18FiveCatalogSnapshot()[@"byID"][slotID];
}
