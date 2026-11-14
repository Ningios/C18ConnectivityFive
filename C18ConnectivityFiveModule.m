#import <Foundation/Foundation.h>

@interface C18ConnectivityFiveModule : NSObject {
    id _module;
}
@end

@implementation C18ConnectivityFiveModule
- (instancetype)init {
    if ((self=[super init])) {
        NSBundle *bundle=[NSBundle bundleWithPath:@"/System/Library/ControlCenter/Bundles/ConnectivityModule.bundle"];
        [bundle load];
        Class cls=NSClassFromString(@"CCUIConnectivityModule");
        if (cls) _module=[cls new];
    }
    return self;
}
- (BOOL)respondsToSelector:(SEL)selector {
    return [super respondsToSelector:selector] || [_module respondsToSelector:selector];
}
- (BOOL)conformsToProtocol:(Protocol *)protocol {
    return [super conformsToProtocol:protocol] || [_module conformsToProtocol:protocol];
}
- (id)forwardingTargetForSelector:(SEL)selector {
    return [_module respondsToSelector:selector] ? _module : [super forwardingTargetForSelector:selector];
}
- (void)dealloc { _module=nil; }
@end
