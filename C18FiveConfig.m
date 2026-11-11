#import "C18Five.h"
#import <CoreFoundation/CoreFoundation.h>
#import <mach-o/dyld.h>

NSString * const C18FiveDomain = @"com.ning.c18connectivity";
const char * const C18FiveReload = "com.ning.c18connectivity.reload";
static NSString * const kNames[7] = {@"飞行模式",@"隔空投送",@"Wi-Fi",@"蜂窝数据",@"蓝牙",@"个人热点",@"VPN"};
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
    if (!object || ![object respondsToSelector:sel]) return nil;
    NSMethodSignature *sig=[object methodSignatureForSelector:sel];
    const char *t=sig.methodReturnType;
    if (!t || (*t!='@' && *t!='#')) return nil;
    return ((id(*)(id,SEL))objc_msgSend)(object,sel);
}
BOOL C18FiveBool(id object, SEL sel) {
    if (!object || ![object respondsToSelector:sel]) return NO;
    const char *t=[object methodSignatureForSelector:sel].methodReturnType;
    if (!t || (*t!='B' && *t!='c')) return NO;
    return ((BOOL(*)(id,SEL))objc_msgSend)(object,sel);
}
void C18FiveVoid(id object, SEL sel) {
    if (!object || ![object respondsToSelector:sel]) return;
    const char *t=[object methodSignatureForSelector:sel].methodReturnType;
    if (t && *t=='v') ((void(*)(id,SEL))objc_msgSend)(object,sel);
}
void C18FiveSetInteger(id object, SEL sel, NSInteger v) {
    if (!object || ![object respondsToSelector:sel]) return;
    NSMethodSignature *sig=[object methodSignatureForSelector:sel];
    if (sig.numberOfArguments!=3) return;
    const char *t=[sig getArgumentTypeAtIndex:2];
    if (*t=='q') ((void(*)(id,SEL,NSInteger))objc_msgSend)(object,sel,v);
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
    // No slider, player, live statistics, grouped panel, or configurable custom card.
    NSArray *blocked=@[@"displaymodule",@"tinydisplay",@"tinymediaaudio",@"controlcenter.audio",@"nowplaying",@"mediacontrol",@"volumemodule",@"brightnessmodule",@"uptime",@"cpumagic",@"caperfhud",@"connectivity",@"focusuimodule",@"home.compact",@"homecontrol",@"text-size",@"hearing"];
    for (NSString *part in blocked) if ([s containsString:part]) return YES;
    return NO;
}
static NSSet *C18FiveLoadableIdentifiers(void) {
    Class shellClass=objc_getClass("C18Shell"); SEL shared=NSSelectorFromString(@"shared");
    if (!shellClass || ![shellClass respondsToSelector:shared]) return nil;
    id shell=((id(*)(id,SEL))objc_msgSend)(shellClass,shared);
    id ids=C18FiveObject(shell,NSSelectorFromString(@"galleryLoadableModuleIdentifiers"));
    if (![ids isKindOfClass:NSArray.class] && ![ids isKindOfClass:NSSet.class]) return nil;
    return [NSSet setWithArray:[ids allObjects]];
}
static NSDictionary *C18FiveBundleEntry(NSString *path, NSString *group, NSSet *loadable) {
    NSDictionary *info=[NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@"Info.plist"]];
    NSString *bid=info[@"CFBundleIdentifier"], *principal=info[@"NSPrincipalClass"];
    if (![bid isKindOfClass:NSString.class] || !bid.length || C18FiveExcluded(bid,principal)) return nil;
    if ([info[@"UIDeviceFamily"] isKindOfClass:NSArray.class] && ![info[@"UIDeviceFamily"] containsObject:@1]) return nil;
    NSBundle *bundle=[NSBundle bundleWithPath:path];
    NSString *title=bundle.localizedInfoDictionary[@"CFBundleDisplayName"] ?: bundle.localizedInfoDictionary[@"CFBundleName"];
    if (!title.length) title=info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: bid;
    return @{@"id":[@"module:" stringByAppendingString:bid],@"identifier":bid,@"title":title,@"group":group,@"path":path,@"principal":principal?:@""};
}
static NSArray<NSDictionary *> *gC18FiveCatalog;
NSArray<NSDictionary *> *C18FiveCatalog(void) {
    if (gC18FiveCatalog) return gC18FiveCatalog;
    NSMutableArray *result=[NSMutableArray array]; NSMutableSet *seen=[NSMutableSet set];
    for (NSInteger i=0;i<7;i++) {
        NSDictionary *e=@{@"id":C18FiveBuiltinID(i),@"title":kNames[i],@"group":@"连接功能"};
        [result addObject:e]; [seen addObject:e[@"id"]];
    }
    NSMutableArray *roots=[NSMutableArray arrayWithObjects:@[@"/Library/ControlCenter/Bundles",@"CC+"],@[@"/Library/ControlCenter18/Bundles",@"自带功能"],@[@"/var/jb/Library/ControlCenter/Bundles",@"CC+"],@[@"/var/jb/Library/ControlCenter18/Bundles",@"自带功能"],@[@"/System/Library/ControlCenter/Bundles",@"系统功能"],nil];
    for (uint32_t j=0;j<_dyld_image_count();j++) {
        const char *n=_dyld_get_image_name(j); if (!n) continue;
        NSString *imagePath=@(n); NSRange rr=[imagePath rangeOfString:@"/Library/MobileSubstrate/"];
        if (rr.location!=NSNotFound) {
            NSString *prefix=[imagePath substringToIndex:rr.location];
            [roots addObject:@[[prefix stringByAppendingString:@"/Library/ControlCenter/Bundles"],@"CC+"]];
            [roots addObject:@[[prefix stringByAppendingString:@"/Library/ControlCenter18/Bundles"],@"自带功能"]];
        }
    }
    // Derive RootHide's real prefix from the already-loaded shipping dylib/bundle.
    NSMutableArray *loaded=[NSMutableArray arrayWithArray:NSBundle.allBundles]; [loaded addObjectsFromArray:NSBundle.allFrameworks];
    for (NSBundle *bundle in loaded) {
        NSString *path=bundle.bundlePath; NSRange r=[path rangeOfString:@"/Library/PreferenceBundles/ControlCenter18Prefs.bundle"];
        if (r.location!=NSNotFound) {
            NSString *prefix=[path substringToIndex:r.location];
            [roots addObject:@[[prefix stringByAppendingString:@"/Library/ControlCenter/Bundles"],@"CC+"]];
            [roots addObject:@[[prefix stringByAppendingString:@"/Library/ControlCenter18/Bundles"],@"自带功能"]];
        }
    }
    Class c=objc_getClass("C18ConnectivityView"); const char *image=c ? class_getImageName(c) : NULL;
    if (image) {
        NSString *path=@(image); NSRange r=[path rangeOfString:@"/Library/MobileSubstrate/"];
        if (r.location!=NSNotFound) {
            NSString *prefix=[path substringToIndex:r.location];
            [roots addObject:@[[prefix stringByAppendingString:@"/Library/ControlCenter/Bundles"],@"CC+"]];
            [roots addObject:@[[prefix stringByAppendingString:@"/Library/ControlCenter18/Bundles"],@"自带功能"]];
        }
    }
    for (NSArray *root in roots) {
        NSArray *names=[[NSFileManager.defaultManager contentsOfDirectoryAtPath:root[0] error:NULL] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
        for (NSString *name in names) {
            if (![name.pathExtension isEqualToString:@"bundle"]) continue;
            NSDictionary *e=C18FiveBundleEntry([root[0] stringByAppendingPathComponent:name],root[1],nil);
            if (e && ![seen containsObject:e[@"id"]]) { [seen addObject:e[@"id"]]; [result addObject:e]; }
        }
    }
    gC18FiveCatalog=[result copy];
    return gC18FiveCatalog;
}
NSDictionary *C18FiveEntry(NSString *slotID) {
    for (NSDictionary *entry in C18FiveCatalog()) if ([entry[@"id"] isEqual:slotID]) return entry;
    return nil;
}
