#import "C18Five.h"
#import "C18RemovedModules.h"
#import "C18ConnectivityShape.h"
#import <string.h>

extern void MSHookMessageEx(Class,SEL,IMP,IMP *);
static void (*gNativeLoad)(id,SEL,id);
static BOOL gNativeRestoreHooked,gNativeRestoreRetry;
static NSUInteger gNativeRestoreAttempts;

static NSSet<NSString *> *C18NativeIdentifiers(NSDictionary *state) {
    if (![state isKindOfClass:NSDictionary.class] || ![state[@"iconLists"] isKindOfClass:NSArray.class] ||
        ![state[@"fixedLocations"] isKindOfClass:NSArray.class]) return nil;
    NSMutableSet *seen=[NSMutableSet set];
    for (id page in state[@"iconLists"]) {
        if (![page isKindOfClass:NSArray.class]) return nil;
        for (id entry in page) {
            if (![entry isKindOfClass:NSDictionary.class]) return nil;
            id identifier=entry[@"id"],size=entry[@"gridSize"];
            if (![identifier isKindOfClass:NSString.class] || ![identifier length] || !size || [seen containsObject:identifier]) return nil;
            [seen addObject:identifier];
        }
    }
    return seen;
}
static BOOL C18NativeFixedLocationsValid(NSDictionary *state) {
    NSArray *pages=state[@"iconLists"],*fixed=state[@"fixedLocations"];
    if (![fixed isKindOfClass:NSArray.class] || fixed.count>pages.count) return NO;
    for (NSUInteger p=0;p<fixed.count;p++) {
        if (![fixed[p] isKindOfClass:NSDictionary.class]) return NO;
        NSMutableSet *identifiers=[NSMutableSet set];
        for (NSDictionary *entry in pages[p]) [identifiers addObject:entry[@"id"]];
        for (id key in fixed[p]) {
            id value=fixed[p][key];
            if (![identifiers containsObject:key] || ![value isKindOfClass:NSNumber.class] ||
                [value integerValue]<0 || [value unsignedIntegerValue]>=32) return NO;
        }
    }
    return YES;
}
static NSDictionary *C18NativeRestoreState(NSDictionary *input,NSDictionary *backup) {
    NSSet *current=C18NativeIdentifiers(input);
    if (!current || ![input[@"C18FiveColumnGridVersion"] respondsToSelector:@selector(unsignedIntegerValue)] ||
        [input[@"C18FiveColumnGridVersion"] unsignedIntegerValue]==0) return input;
    NSSet *original=C18NativeIdentifiers(backup);
    // Restore exact positions only if neither module membership nor sizes changed.
    NSMutableDictionary *sizes=[NSMutableDictionary dictionary],*oldSizes=[NSMutableDictionary dictionary];
    for (NSArray *page in input[@"iconLists"]) for (NSDictionary *entry in page) sizes[entry[@"id"]]=entry[@"gridSize"];
    if (original) for (NSArray *page in backup[@"iconLists"]) for (NSDictionary *entry in page) oldSizes[entry[@"id"]]=entry[@"gridSize"];
    if (original && !backup[@"C18FiveColumnGridVersion"] && C18NativeFixedLocationsValid(backup) && [current isEqualToSet:original] && [sizes isEqual:oldSizes]) return backup;
    // Keep all CURRENT modules and sizes if the backup is absent, marked v1/v2,
    // or the user added/removed a module since it was taken. Native 4x8 placement
    // rebuilds positions from the lists; no custom frames, spans or grid model.
    NSMutableDictionary *native=[input mutableCopy];
    [native removeObjectForKey:@"C18FiveColumnGridVersion"];
    NSMutableArray *fixed=[NSMutableArray array];
    for (__unused id page in input[@"iconLists"]) [fixed addObject:@{}];
    native[@"fixedLocations"]=fixed;
    return [native copy];
}

static id C18NativeWithoutPromos(id input) {
    if (![input isKindOfClass:NSDictionary.class]) return input;
    id pages=input[@"iconLists"],fixed=input[@"fixedLocations"];
    if (![pages isKindOfClass:NSArray.class]) return input;
    BOOL changed=NO; NSMutableArray *keptPages=[NSMutableArray array];
    for (id page in pages) {
        if (![page isKindOfClass:NSArray.class]) return input;
        NSMutableArray *kept=[NSMutableArray array];
        for (id entry in page) {
            if (![entry isKindOfClass:NSDictionary.class]) return input;
            if (C18RemovedModuleID(entry[@"id"])) changed=YES;
            else [kept addObject:entry];
        }
        [keptPages addObject:[kept copy]];
    }
    NSMutableArray *keptFixed=[NSMutableArray array];
    if ([fixed isKindOfClass:NSArray.class]) for (id page in fixed) {
        if (![page isKindOfClass:NSDictionary.class]) return input;
        NSMutableDictionary *kept=[page mutableCopy];
        for (id key in page) if (C18RemovedModuleID(key)) { [kept removeObjectForKey:key];changed=YES; }
        [keptFixed addObject:[kept copy]];
    }
    if (!changed) return input;
    NSMutableDictionary *result=[input mutableCopy];result[@"iconLists"]=[keptPages copy];
    if ([fixed isKindOfClass:NSArray.class]) result[@"fixedLocations"]=[keptFixed copy];
    return [result copy];
}

// Passive serialized-state normalization: no singleton reload or startup scan.
static id C18NativeConnectivityShapes(id input) {
    if (![input isKindOfClass:NSDictionary.class] || ![input[@"iconLists"] isKindOfClass:NSArray.class]) return input;
    NSInteger mode=0; C18FiveRead(&mode,NULL); if (mode!=5) return input;
    BOOL changed=NO; NSMutableArray *pages=[NSMutableArray array];
    for (id page in input[@"iconLists"]) {
        if (![page isKindOfClass:NSArray.class]) return input;
        NSMutableArray *entries=[NSMutableArray array];
        for (id entry in page) {
            if (![entry isKindOfClass:NSDictionary.class]) return input;
            if (C18ShapeIdentifier(entry[@"id"])) {
                id old=entry[@"gridSize"], normalized=C18ShapeGridClass(old);
                if (![normalized isEqual:old]) {
                    NSMutableDictionary *copy=[entry mutableCopy];copy[@"gridSize"]=normalized;
                    [entries addObject:[copy copy]];changed=YES;continue;
                }
            }
            [entries addObject:entry];
        }
        [pages addObject:[entries copy]];
    }
    if (!changed) return input;
    NSMutableDictionary *result=[input mutableCopy];result[@"iconLists"]=[pages copy];return [result copy];
}

static void C18NativeLoad(id state,SEL cmd,id input) {
    input=C18NativeConnectivityShapes(C18NativeWithoutPromos(input));
    if (![input isKindOfClass:NSDictionary.class] || !input[@"C18FiveColumnGridVersion"]) {
        gNativeLoad(state,cmd,input); return;
    }
    NSUserDefaults *journal=[[NSUserDefaults alloc] initWithSuiteName:@"com.cc18.fivecolumn.migration"];
    NSDictionary *backup=C18NativeConnectivityShapes(C18NativeWithoutPromos([journal dictionaryForKey:@"OriginalStateBeforeV2"]));
    NSDictionary *native=C18NativeRestoreState(input,backup);
    if (native==input) { gNativeLoad(state,cmd,input); return; }
    // Preserve the replaced representation. Never clear global CC18 preferences
    // or the independent top-row com.ning.c18connectivity slot configuration.
    if (![journal objectForKey:@"StateBeforeNativeRestoreBeta7"]) {
        [journal setObject:input forKey:@"StateBeforeNativeRestoreBeta7"];
        if (![journal synchronize]) { gNativeLoad(state,cmd,input); return; }
    }
    gNativeLoad(state,cmd,native);
    // _loadState: is a void native load and may run from loadIfNeeded. Save only
    // after it returns and verify the serialized module identities are intact.
    dispatch_async(dispatch_get_main_queue(),^{
        id serialized=C18FiveObject(state,NSSelectorFromString(@"_serialize"));
        if (![C18NativeIdentifiers(serialized) isEqualToSet:C18NativeIdentifiers(native)]) return;
        C18FiveVoid(state,NSSelectorFromString(@"_save"));
        [journal setObject:@"native-four-column-restored-beta7" forKey:@"Status"];
        [journal synchronize];
    });
}
static BOOL C18NativeRegisterLoad(void) {
    if (gNativeRestoreHooked) return YES;
    Class cls=objc_getClass("C18IconState");SEL load=sel_registerName("_loadState:");
    Method method=class_getInstanceMethod(cls,load);
    if (!method || strcmp(method_getTypeEncoding(method),"v24@0:8@16")) return NO;
    gNativeRestoreHooked=YES;
    MSHookMessageEx(cls,load,(IMP)C18NativeLoad,(IMP *)&gNativeLoad);
    return YES;
}
void C18NativeLayoutRestoreInstall(void) {
    if (!NSThread.isMainThread || gNativeRestoreHooked || C18NativeRegisterLoad()) return;
    // If the image is late, retry metadata lookup only. No singleton is sent a message.
    if (!gNativeRestoreRetry && gNativeRestoreAttempts++<120) {
        gNativeRestoreRetry=YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
            gNativeRestoreRetry=NO; C18NativeLayoutRestoreInstall();
        });
    }
}
__attribute__((constructor)) static void C18NativeLoadRegistration(void) {
    // ObjC class metadata is registered before Mach-O C initializers. Install
    // before the owner's ordinary loadIfNeeded without messaging any ObjC class.
    // Missing classes are handled later by the normal metadata-only registrar.
    C18NativeRegisterLoad();
}
