#import "C18Five.h"
#import "C18Localization.h"
#import <dlfcn.h>
#import <string.h>

extern void MSHookMessageEx(Class,SEL,IMP,IMP *);
static BOOL C18LChinese(void) {
    NSString *language=NSLocale.preferredLanguages.firstObject;
    return [language hasPrefix:@"zh"];
}
NSString *C18LocalizeDisplayString(NSString *value) {
    if (![value isKindOfClass:NSString.class] || !C18LChinese()) return value;
    static NSDictionary<NSString *,NSString *> *map;
    static dispatch_once_t once;
    dispatch_once(&once,^{
        Dl_info info={0};
        if (dladdr((const void *)&C18LocalizeDisplayString,&info) && info.dli_fname) {
            NSString *path=[[@(info.dli_fname) stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"C18ChineseDisplay.plist"];
            id loaded=[NSDictionary dictionaryWithContentsOfFile:path];
            if ([loaded isKindOfClass:NSDictionary.class]) map=loaded;
        }
        if (!map) map=@{@"On":@"打开",@"Off":@"关闭",@"Locked":@"已锁定",@"Unlocked":@"未锁定"};
    });
    NSString *translated=map[value];
    return [translated isKindOfClass:NSString.class] ? translated : value;
}
static NSString *C18LTitle(id object,NSString *original) {
    if (!C18LChinese()) return original;
    NSString *identifier=C18FiveObject(object,NSSelectorFromString(@"identifier"));
    if (![identifier isKindOfClass:NSString.class]) return C18LocalizeDisplayString(original);
    NSString *name=[[identifier componentsSeparatedByString:@"."] lastObject];
    return C18FiveDisplayTitle(identifier,C18LocalizeDisplayString(original),name);
}
static id (*oValueB)(id,SEL,BOOL);
static id (*oValueC)(id,SEL,signed char);
static id (*oTitle)(id,SEL);
static id (*oGalleryTitle)(id,SEL);
static id (*oContextMenu)(id,SEL);
static id (*oAirDropMenu)(id,SEL);
static __thread NSUInteger gMenuScope;
static id (*oActionFactory)(id,SEL,id,id,id,id);
static id (*oNativeItemTitle)(id,SEL);
static id C18LValueB(id self,SEL cmd,BOOL value) { return C18LocalizeDisplayString(oValueB(self,cmd,value)); }
static id C18LValueC(id self,SEL cmd,signed char value) { return C18LocalizeDisplayString(oValueC(self,cmd,value)); }
static id C18LTemplateTitle(id self,SEL cmd) { return C18LTitle(self,oTitle(self,cmd)); }
static id C18LGalleryTitle(id self,SEL cmd) { return C18LTitle(self,oGalleryTitle(self,cmd)); }
static UIMenuElement *C18LElement(UIMenuElement *element) {
    if ([element isKindOfClass:UIAction.class]) {
        UIAction *action=[(UIAction *)element copy];
        action.title=C18LocalizeDisplayString(action.title);
        action.subtitle=C18LocalizeDisplayString(action.subtitle);
        action.discoverabilityTitle=C18LocalizeDisplayString(action.discoverabilityTitle);
        return action;
    }
    if ([element isKindOfClass:UIMenu.class]) {
        UIMenu *menu=(UIMenu *)element;
        NSMutableArray *children=[NSMutableArray arrayWithCapacity:menu.children.count];
        for (UIMenuElement *child in menu.children) [children addObject:C18LElement(child)];
        UIMenu *copy=[UIMenu menuWithTitle:C18LocalizeDisplayString(menu.title) image:menu.image identifier:menu.identifier options:menu.options children:children];
        copy.subtitle=C18LocalizeDisplayString(menu.subtitle);
        if (@available(iOS 16.0,*)) copy.preferredElementSize=menu.preferredElementSize;
        return copy;
    }
    return element;
}
static id C18LContext(id self,SEL cmd) {
    gMenuScope++;id menu=nil;
    @try {menu=oContextMenu(self,cmd);} @finally {gMenuScope--;}
    return C18LChinese() && [menu isKindOfClass:UIMenu.class] ? C18LElement(menu) : menu;
}
static id C18LAirDrop(id self,SEL cmd) {
    gMenuScope++;id menu=nil;
    @try {menu=oAirDropMenu(self,cmd);} @finally {gMenuScope--;}
    return C18LChinese() && [menu isKindOfClass:UIMenu.class] ? C18LElement(menu) : menu;
}
static BOOL C18LCaller(const void *address) {
    Dl_info info={0};if (!address || !dladdr(address,&info) || !info.dli_fname) return NO;
    const char *p=info.dli_fname;
    return strstr(p,"/ControlCenter/") || strstr(p,"/ControlCenter18/") || strstr(p,"/ControlCenter18.dylib") || strstr(p,"/C18ConnectivityFive.dylib");
}
static id C18LActionFactory(id cls,SEL cmd,id title,id image,id identifier,id handler) {
    if (gMenuScope || C18LCaller(__builtin_return_address(0))) title=C18LocalizeDisplayString(title);
    return oActionFactory(cls,cmd,title,image,identifier,handler);
}
static id C18LNativeItemTitle(id self,SEL cmd) {
    id title=oNativeItemTitle(self,cmd);
    return C18LCaller(__builtin_return_address(0)) ? C18LocalizeDisplayString(title) : title;
}
static BOOL C18LType(const char *actual,const char *expected) {
    if (!actual || !expected) return NO;
    while (*actual && strchr("rnNoORV",*actual)) actual++;
    if (expected[0]=='B') return actual[0]=='B' || actual[0]=='c';
    if (expected[0]=='@') return actual[0]=='@';
    return actual[0]==expected[0];
}
static BOOL C18LMethod(Class cls,SEL sel,const char *result,const char *argument,NSUInteger count) {
    Method m=class_getInstanceMethod(cls,sel);if (!m || method_getNumberOfArguments(m)!=count) return NO;
    char *ret=method_copyReturnType(m);BOOL ok=C18LType(ret,result);free(ret);
    for (NSUInteger i=2;ok && i<count;i++) {
        char *arg=method_copyArgumentType(m,(unsigned int)i);ok=C18LType(arg,argument ?: "@");free(arg);
    }
    return ok;
}
void C18LocalizationInstall(void) {
    static BOOL doneValue,doneTitle,doneGallery,doneContext,doneAirDrop,doneAction,doneItem;
    Class button=objc_getClass("C18ButtonModuleView");
    SEL value=NSSelectorFromString(@"_templateValue:");
    if (!doneValue && C18LMethod(button,value,"@","B",3)) {doneValue=YES;MSHookMessageEx(button,value,(IMP)C18LValueB,(IMP *)&oValueB);}
    else if (!doneValue && C18LMethod(button,value,"@","c",3)) {doneValue=YES;MSHookMessageEx(button,value,(IMP)C18LValueC,(IMP *)&oValueC);}
    SEL title=NSSelectorFromString(@"_templateTitle");
    if (!doneTitle && C18LMethod(button,title,"@",NULL,2)) {doneTitle=YES;MSHookMessageEx(button,title,(IMP)C18LTemplateTitle,(IMP *)&oTitle);}
    Class gallery=objc_getClass("C18GalleryItem");
    if (!doneGallery && C18LMethod(gallery,@selector(title),"@",NULL,2)) {doneGallery=YES;MSHookMessageEx(gallery,@selector(title),(IMP)C18LGalleryTitle,(IMP *)&oGalleryTitle);}
    SEL context=NSSelectorFromString(@"_contextMenu");
    if (!doneContext && C18LMethod(button,context,"@",NULL,2)) {doneContext=YES;MSHookMessageEx(button,context,(IMP)C18LContext,(IMP *)&oContextMenu);}
    Class connectivity=objc_getClass("C18ConnectivityView");SEL air=NSSelectorFromString(@"_airDropMenu");
    if (!doneAirDrop && C18LMethod(connectivity,air,"@",NULL,2)) {doneAirDrop=YES;MSHookMessageEx(connectivity,air,(IMP)C18LAirDrop,(IMP *)&oAirDropMenu);}
    Class action=object_getClass(UIAction.class);SEL factory=@selector(actionWithTitle:image:identifier:handler:);
    if (!doneAction && C18LMethod(action,factory,"@",NULL,6)) {doneAction=YES;MSHookMessageEx(action,factory,(IMP)C18LActionFactory,(IMP *)&oActionFactory);}
    Class item=objc_getClass("CCUIMenuModuleItem");
    if (!doneItem && C18LMethod(item,@selector(title),"@",NULL,2)) {doneItem=YES;MSHookMessageEx(item,@selector(title),(IMP)C18LNativeItemTitle,(IMP *)&oNativeItemTitle);}
}
