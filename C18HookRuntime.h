#ifndef C18_HOOK_RUNTIME_H
#define C18_HOOK_RUNTIME_H
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

static inline const char *C18HookUnqualified(const char *type) {
    if (!type) return "";
    while (*type && strchr("rnNoORV",*type)) type++;
    return type;
}
static inline BOOL C18HookTypeMatches(const char *actual,const char *expected) {
    actual=C18HookUnqualified(actual);
    if (!expected || !*actual || !*expected) return NO;
    if (!strcmp(expected,"B")) {
        if (*actual!='B' && *actual!='c') return NO;
        actual++;
    } else if (!strcmp(expected,"@")) {
        if (*actual++!='@' || *actual=='?') return NO;
        if (*actual=='"') { actual++;while (*actual && *actual!='"') actual++;if (*actual++!='"') return NO; }
    } else {
        size_t length=strlen(expected);
        if (strncmp(actual,expected,length)) return NO;
        actual+=length;
    }
    // Runtime copy APIs may retain byte offsets; do not accept extra ABI tokens.
    if (*actual=='+' || *actual=='-') actual++;
    while (*actual && isdigit((unsigned char)*actual)) actual++;
    return !*actual;
}
static inline BOOL C18HookSignatureMatches(Method method,const char *result,NSArray<NSString *> *arguments) {
    if (!method || method_getNumberOfArguments(method)!=arguments.count+2) return NO;
    char *type=method_copyReturnType(method);BOOL valid=C18HookTypeMatches(type,result);free(type);
    for (NSUInteger i=0;valid && i<arguments.count+2;i++) {
        const char *expected=i==0?"@":i==1?":":[arguments[i-2] UTF8String];
        type=method_copyArgumentType(method,(unsigned int)i);
        valid=C18HookTypeMatches(type,expected);free(type);
    }
    return valid;
}
static inline BOOL C18HookCanInstall(Class cls,SEL selector,const char *result,NSArray<NSString *> *arguments) {
    return cls && C18HookSignatureMatches(class_getInstanceMethod(cls,selector),result,arguments);
}
#endif
