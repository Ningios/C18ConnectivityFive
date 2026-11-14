#pragma once
#import <Foundation/Foundation.h>

// Only the third, package-owned module is controlled by the five-key layout.
// The Apple ConnectivityModule and the existing connectivity2 instance keep
// their native identifiers, grid candidates, and resize behavior untouched.
static inline NSString *C18FiveNativeModuleIdentifier(void) {
    return @"com.ning.c18connectivityfive";
}
static inline BOOL C18ShapeIdentifier(id value) {
    return [value isKindOfClass:NSString.class] && [value isEqualToString:C18FiveNativeModuleIdentifier()];
}
static inline NSString *C18ShapeGridClass(id value) {
    if ([value isKindOfClass:NSString.class] &&
        ([value isEqualToString:@"CCUIIconGridSizeClassMedium"] ||
         [value isEqualToString:@"CCUIIconGridSizeClassSmallExtraWide"])) return value;
    return @"CCUIIconGridSizeClassMedium";
}
static inline long long C18ShapeSize(long long size) { return size==3?3:4; }
