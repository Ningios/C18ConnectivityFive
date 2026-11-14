#pragma once
#import <Foundation/Foundation.h>

// Original _C18IsConnectivityModule also accepts numbered instances (#2+).
static inline BOOL C18ShapeIdentifier(id value) {
    if (![value isKindOfClass:NSString.class]) return NO;
    NSString *base=value;
    NSRange hash=[base rangeOfString:@"#" options:NSBackwardsSearch];
    if (hash.location!=NSNotFound) {
        NSString *suffix=[base substringFromIndex:hash.location+1];
        if (!suffix.length || [suffix rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location!=NSNotFound || suffix.longLongValue<2) return NO;
        base=[base substringToIndex:hash.location];
    }
    return [base isEqualToString:@"com.apple.control-center.ConnectivityModule"] ||
        [base isEqualToString:@"com.evgeniy558.controlcenter18.connectivity2"];
}
static inline NSString *C18ShapeGridClass(id value) {
    if ([value isKindOfClass:NSString.class] &&
        ([value isEqualToString:@"CCUIIconGridSizeClassMedium"] ||
         [value isEqualToString:@"CCUIIconGridSizeClassSmallExtraWide"])) return value;
    return @"CCUIIconGridSizeClassMedium";
}
static inline long long C18ShapeSize(long long size) { return size==3?3:4; }
