#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <string.h>

static inline id SIMObject(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) return nil;
    NSMethodSignature *signature=[object methodSignatureForSelector:selector];
    const char *type=signature.methodReturnType;
    if (!type || (*type!='@' && *type!='#')) return nil;
    return ((id(*)(id,SEL))objc_msgSend)(object,selector);
}
static inline id SIMValue(id object, NSString *key) {
    @try { return object?[object valueForKey:key]:nil; }
    @catch (NSException *exception) { return nil; }
}
static inline BOOL SIMNoArgVoid(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) return NO;
    NSMethodSignature *signature=[object methodSignatureForSelector:selector];
    if (signature.numberOfArguments!=2 || strcmp(signature.methodReturnType,"v")) return NO;
    ((void(*)(id,SEL))objc_msgSend)(object,selector);
    return YES;
}
