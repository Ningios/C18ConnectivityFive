#pragma once
#import <Foundation/Foundation.h>
#include <stdint.h>

// Only migration identities are retained, as length+digest rather than old
// catalog names or module classes. No construction/action path is available.
static inline BOOL C18RemovedModuleID(id identifier) {
    if (![identifier isKindOfClass:NSString.class]) return NO;
    NSData *data=[(NSString *)identifier dataUsingEncoding:NSUTF8StringEncoding];
    if (data.length!=40 && data.length!=34) return NO;
    const uint8_t *bytes=data.bytes;uint64_t digest=UINT64_C(14695981039346656037);
    for (NSUInteger i=0;i<data.length;i++) digest=(digest^bytes[i])*UINT64_C(1099511628211);
    return (data.length==40 && digest==UINT64_C(0x71bd801d90079b01)) ||
           (data.length==34 && digest==UINT64_C(0x3d4d019b04cfd5ea));
}
