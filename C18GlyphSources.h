#import <UIKit/UIKit.h>
FOUNDATION_EXPORT UIImage *C18GlyphImageIfVisible(id image);
FOUNDATION_EXPORT UIImage *C18GlyphFallbackForSlot(NSString *slotID);
FOUNDATION_EXPORT UIView *C18GlyphPackageView(id button);
// Visible ink in UIImage points / package-view local coordinates. CGRectNull
// means blank or unmeasurable; view bounds are never assumed to be glyph ink.
FOUNDATION_EXPORT CGRect C18GlyphImageVisibleBounds(UIImage *image);
FOUNDATION_EXPORT UIImage *C18GlyphImageWithVisibleSide(UIImage *image, CGFloat side);
FOUNDATION_EXPORT CGRect C18GlyphPackageVisibleBounds(UIView *view);
