#import "C18Five.h"
#import "C18GlyphSources.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dlfcn.h>
#import <stdint.h>
#import <math.h>

static BOOL C18GlyphRectValid(CGRect r) {
    return !CGRectIsNull(r) && !CGRectIsInfinite(r) && isfinite(r.origin.x) && isfinite(r.origin.y) &&
        isfinite(r.size.width) && isfinite(r.size.height) && r.size.width>0 && r.size.height>0;
}
static CGRect C18GlyphScanImage(UIImage *image) {
    CGSize size=image.size;
    if (!isfinite(size.width) || !isfinite(size.height) || size.width<=0 || size.height<=0 || (size.width<=1 && size.height<=1)) return CGRectNull;
    // Measure at resource resolution (up to 1024 pixels), not at the 25pt
    // destination. This also rasterizes vector/SF images without a CGImage.
    CGFloat longest=MAX(size.width,size.height);
    CGFloat density=MAX(64,MIN(1024,ceil(longest*MAX(1,image.scale))))/longest;
    size_t width=(size_t)ceil(size.width*density),height=(size_t)ceil(size.height*density);
    if (!width || !height || width>1024 || height>1024) return CGRectNull;
    unsigned char *pixels=calloc(width*height,4); if (!pixels) return CGRectNull;
    CGColorSpaceRef colors=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=colors?CGBitmapContextCreate(pixels,width,height,8,width*4,colors,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big):NULL;
    if (colors) CGColorSpaceRelease(colors);
    CGRect result=CGRectNull;
    if (context) {
        // Explicit UIKit top-left coordinates, including UIImage orientation.
        CGContextTranslateCTM(context,0,height); CGContextScaleCTM(context,width/size.width,-(CGFloat)height/size.height);
        UIGraphicsPushContext(context); [image drawInRect:(CGRect){CGPointZero,size}]; UIGraphicsPopContext();
        size_t left=width,top=height,right=0,bottom=0;
        for (size_t y=0;y<height;y++) for (size_t x=0;x<width;x++) if (pixels[(y*width+x)*4+3]>8) {
            left=MIN(left,x);top=MIN(top,y);right=MAX(right,x+1);bottom=MAX(bottom,y+1);
        }
        if (right>left && bottom>top) result=CGRectMake(left*size.width/width,top*size.height/height,(right-left)*size.width/width,(bottom-top)*size.height/height);
        CGContextRelease(context);
    }
    free(pixels); return result;
}
CGRect C18GlyphImageVisibleBounds(UIImage *image) {
    if (![image isKindOfClass:UIImage.class]) return CGRectNull;
    static NSMapTable *cache; if (!cache) cache=[NSMapTable weakToStrongObjectsMapTable];
    NSValue *known=[cache objectForKey:image]; if (known) return known.CGRectValue;
    CGRect ink=CGRectNull;
    if (image.images.count) {
        // One envelope for every frame; no animation-size pumping or snapshot.
        for (UIImage *frame in image.images) ink=CGRectUnion(ink,C18GlyphScanImage(frame));
    } else ink=C18GlyphScanImage(image);
    [cache setObject:[NSValue valueWithCGRect:ink] forKey:image]; return ink;
}
UIImage *C18GlyphImageIfVisible(id value) {
    return [value isKindOfClass:UIImage.class] && C18GlyphRectValid(C18GlyphImageVisibleBounds(value))?value:nil;
}
static UIImage *C18GlyphDrawImage(UIImage *source,CGRect ink,CGFloat scale) {
    CGSize size=CGSizeMake(ink.size.width*scale,ink.size.height*scale);
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat preferredFormat]; format.opaque=NO;
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        (void)context;
        [source drawInRect:CGRectMake(-ink.origin.x*scale,-ink.origin.y*scale,source.size.width*scale,source.size.height*scale)];
    }];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}
UIImage *C18GlyphImageWithVisibleSide(UIImage *source,CGFloat side) {
    CGRect ink=C18GlyphImageVisibleBounds(source);
    if (!C18GlyphRectValid(ink) || !isfinite(side) || side<=0) return nil;
    CGFloat scale=side/MAX(ink.size.width,ink.size.height);
    if (source.images.count) {
        NSMutableArray *frames=[NSMutableArray arrayWithCapacity:source.images.count];
        for (UIImage *frame in source.images) [frames addObject:C18GlyphDrawImage(frame,ink,scale)];
        return [[UIImage animatedImageWithImages:frames duration:source.duration] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    return C18GlyphDrawImage(source,ink,scale);
}
static NSString *C18GlyphString(id value) { return [value isKindOfClass:NSString.class]?value:@""; }
static NSArray *C18GlyphArray(id value) { return [value isKindOfClass:NSArray.class]?value:@[]; }
static NSString *C18GlyphResourceRoot(void) {
    Class cls=objc_getClass("C18ConnectivityView"); const char *image=cls?class_getImageName(cls):NULL;
    if (!image) return nil;
    NSString *path=@(image);
    for (NSString *marker in @[@"/usr/lib/TweakInject/",@"/Library/MobileSubstrate/DynamicLibraries/"]) {
        NSRange r=[path rangeOfString:marker options:NSBackwardsSearch];
        if (r.location!=NSNotFound) return [[path substringToIndex:r.location] stringByAppendingString:@"/Library/Application Support/ControlCenter18"];
    }
    return nil;
}
static UIImage *C18GlyphVector(NSString *identifier,NSString *root) {
    if (!identifier.length || !root.length) return nil;
    static NSDictionary *controls; static NSString *loadedRoot;
    if (![loadedRoot isEqualToString:root]) {
        NSData *data=[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"ControlGlyphs18.json"]];
        id decoded=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;
        controls=[decoded isKindOfClass:NSDictionary.class] && [decoded[@"controls"] isKindOfClass:NSDictionary.class]?decoded[@"controls"]:@{};
        loadedRoot=[root copy];
    }
    NSDictionary *control=[controls[identifier] isKindOfClass:NSDictionary.class]?controls[identifier]:nil;
    NSArray *size=C18GlyphArray(control[@"iconSize"]),*layers=C18GlyphArray(control[@"layers"]);
    if (size.count!=2 || !layers.count) return nil;
    CGSize canvas=CGSizeMake([size[0] doubleValue],[size[1] doubleValue]);
    if (!(canvas.width>0 && canvas.width<512 && canvas.height>0 && canvas.height<512)) return nil;
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat preferredFormat];format.opaque=NO;
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:canvas format:format];
    UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *render) {
        CGContextRef context=render.CGContext;
        for (id value in layers) {
            if (![value isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *layer=value; CGFloat opacity=[layer[@"opacity"] respondsToSelector:@selector(doubleValue)]?[layer[@"opacity"] doubleValue]:1;
            if (opacity<=0) continue;
            CGContextSaveGState(context); CGContextSetAlpha(context,MIN(1,opacity));
            NSArray *commands=C18GlyphArray(layer[@"path"]);
            if (commands.count) {
                CGMutablePathRef path=CGPathCreateMutable(); BOOL valid=YES;
                for (id raw in commands) {
                    NSArray *c=C18GlyphArray(raw); if (!c.count || ![c[0] isKindOfClass:NSString.class]) { valid=NO;break; }
                    NSString *op=c[0];
                    if ([op isEqualToString:@"M"] && c.count==3) CGPathMoveToPoint(path,NULL,[c[1] doubleValue],[c[2] doubleValue]);
                    else if ([op isEqualToString:@"L"] && c.count==3) CGPathAddLineToPoint(path,NULL,[c[1] doubleValue],[c[2] doubleValue]);
                    else if ([op isEqualToString:@"Q"] && c.count==5) CGPathAddQuadCurveToPoint(path,NULL,[c[1] doubleValue],[c[2] doubleValue],[c[3] doubleValue],[c[4] doubleValue]);
                    else if ([op isEqualToString:@"C"] && c.count==7) CGPathAddCurveToPoint(path,NULL,[c[1] doubleValue],[c[2] doubleValue],[c[3] doubleValue],[c[4] doubleValue],[c[5] doubleValue],[c[6] doubleValue]);
                    else if ([op isEqualToString:@"Z"] && c.count==1) CGPathCloseSubpath(path);
                    else { valid=NO;break; }
                }
                if (valid) { CGContextAddPath(context,path);CGContextSetFillColorWithColor(context,UIColor.whiteColor.CGColor);CGContextDrawPath(context,[layer[@"fillRule"] isEqual:@"even-odd"]?kCGPathEOFill:kCGPathFill); }
                CGPathRelease(path);
            } else {
                NSString *file=C18GlyphString(layer[@"image"]); NSArray *frame=C18GlyphArray(layer[@"frame"]);
                if (file.length && frame.count==4) {
                    UIImage *part=[UIImage imageWithContentsOfFile:[root stringByAppendingPathComponent:file]];
                    [part drawInRect:CGRectMake([frame[0] doubleValue],[frame[1] doubleValue],[frame[2] doubleValue],[frame[3] doubleValue])];
                }
            }
            CGContextRestoreGState(context);
        }
    }];
    image=C18GlyphImageIfVisible(image); return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}
static UIImage *C18GlyphDeclaredImage(NSDictionary *entry) {
    NSString *path=C18GlyphString(entry[@"path"]); if (!path.length) return nil;
    NSBundle *bundle=[NSBundle bundleWithPath:path];
    // These are declared module glyph resources. Do not substitute a random
    // bundle image or a generic grid icon and claim the module is fixed.
    for (id raw in C18GlyphArray(entry[@"iconNames"])) {
        NSString *name=C18GlyphString(raw);if (!name.length) continue;
        UIImage *image=C18GlyphImageIfVisible([UIImage imageNamed:name inBundle:bundle compatibleWithTraitCollection:nil]);
        if (image) return image;
    }
    return nil;
}
static UIImage *C18GlyphNativeSymbol(NSString *name) {
    if (!name.length) return nil;
    typedef UIImage *(*Symbol)(NSString *,UIImageSymbolConfiguration *);
    Symbol original=(Symbol)dlsym(RTLD_DEFAULT,"C18Symbol");
    UIImageSymbolConfiguration *configuration=[UIImageSymbolConfiguration configurationWithPointSize:25 weight:UIImageSymbolWeightSemibold scale:UIImageSymbolScaleSmall];
    UIImage *image=original?original(name,configuration):nil;
    if (!image) image=[UIImage systemImageNamed:name withConfiguration:configuration];
    return C18GlyphImageIfVisible(image);
}
UIImage *C18GlyphFallbackForSlot(NSString *slotID) {
    static NSCache *cache;if (!cache) cache=[NSCache new];
    NSString *identifier=C18FiveModuleID(slotID); if (!identifier.length) return nil;
    UIImage *cached=[cache objectForKey:identifier];if (cached) return cached;
    NSDictionary *entry=C18FiveEntry(slotID);
    UIImage *image=C18GlyphVector(identifier,C18GlyphResourceRoot());
    if (!image) image=C18GlyphDeclaredImage(entry);
    if (!image) image=C18GlyphNativeSymbol(C18GlyphString(entry[@"nativeSymbol"]));
    if (image) [cache setObject:image forKey:identifier];return image;
}
// Only painted content contributes: a transparent 48/66pt wrapper is not ink.
static CGRect C18GlyphLayerContents(CALayer *layer) {
    id contents=layer.contents; if (!contents) return CGRectNull;
    if (CFGetTypeID((__bridge CFTypeRef)contents)!=CGImageGetTypeID()) return CGRectNull;
    static char key;
    NSArray *cached=objc_getAssociatedObject(layer,&key);
    CGRect unit;
    CGImageRef cg=(__bridge CGImageRef)contents;
    if (cached.count==2 && cached[0]==contents) unit=[cached[1] CGRectValue];
    else {
        UIImage *image=[UIImage imageWithCGImage:cg]; CGRect ink=C18GlyphImageVisibleBounds(image);
        unit=C18GlyphRectValid(ink)?CGRectMake(ink.origin.x/image.size.width,ink.origin.y/image.size.height,ink.size.width/image.size.width,ink.size.height/image.size.height):CGRectNull;
        objc_setAssociatedObject(layer,&key,@[contents,[NSValue valueWithCGRect:unit]],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGRect crop=layer.contentsRect;
    unit=CGRectIntersection(unit,crop); if (!C18GlyphRectValid(unit) || !C18GlyphRectValid(crop)) return CGRectNull;
    // Nine-slice resampling is non-linear: keep a conservative painted extent.
    if (!CGRectEqualToRect(layer.contentsCenter,CGRectMake(0,0,1,1))) return layer.bounds;
    CGFloat density=layer.contentsScale>0?layer.contentsScale:1;
    CGSize size=CGSizeMake(CGImageGetWidth(cg)*crop.size.width/density,CGImageGetHeight(cg)*crop.size.height/density);
    CGRect box=layer.bounds; NSString *gravity=layer.contentsGravity;
    if (![gravity isEqualToString:kCAGravityResize]) {
        CGFloat scale=1;
        if ([gravity isEqualToString:kCAGravityResizeAspect]) scale=MIN(box.size.width/size.width,box.size.height/size.height);
        else if ([gravity isEqualToString:kCAGravityResizeAspectFill]) scale=MAX(box.size.width/size.width,box.size.height/size.height);
        size.width*=scale;size.height*=scale;
        CGFloat x=CGRectGetMidX(box)-size.width*.5,y=CGRectGetMidY(box)-size.height*.5;
        if ([gravity isEqualToString:kCAGravityLeft] || [gravity isEqualToString:kCAGravityTopLeft] || [gravity isEqualToString:kCAGravityBottomLeft]) x=CGRectGetMinX(box);
        if ([gravity isEqualToString:kCAGravityRight] || [gravity isEqualToString:kCAGravityTopRight] || [gravity isEqualToString:kCAGravityBottomRight]) x=CGRectGetMaxX(box)-size.width;
        if ([gravity isEqualToString:kCAGravityTop] || [gravity isEqualToString:kCAGravityTopLeft] || [gravity isEqualToString:kCAGravityTopRight]) y=CGRectGetMinY(box);
        if ([gravity isEqualToString:kCAGravityBottom] || [gravity isEqualToString:kCAGravityBottomLeft] || [gravity isEqualToString:kCAGravityBottomRight]) y=CGRectGetMaxY(box)-size.height;
        box=(CGRect){CGPointMake(x,y),size};
    }
    return CGRectMake(box.origin.x+(unit.origin.x-crop.origin.x)*box.size.width/crop.size.width,
        box.origin.y+(unit.origin.y-crop.origin.y)*box.size.height/crop.size.height,
        unit.size.width*box.size.width/crop.size.width,unit.size.height*box.size.height/crop.size.height);
}
static CGRect C18GlyphMaskRect(CALayer *mask,CGRect ink) {
    // A mask is not a sublayer (superlayer may be nil), so convertRect:toLayer:
    // cannot be used to find its owner's coordinates.
    if (!C18GlyphRectValid(ink) || !CATransform3DIsAffine(mask.transform)) return CGRectNull;
    CGPoint anchor=CGPointMake(mask.bounds.origin.x+mask.anchorPoint.x*mask.bounds.size.width,mask.bounds.origin.y+mask.anchorPoint.y*mask.bounds.size.height);
    ink=CGRectOffset(ink,-anchor.x,-anchor.y);
    ink=CGRectApplyAffineTransform(ink,CATransform3DGetAffineTransform(mask.transform));
    return CGRectOffset(ink,mask.position.x,mask.position.y);
}
static CGRect C18GlyphLayerInk(CALayer *layer,NSUInteger depth,NSUInteger *remaining) {
    if (!layer || !*remaining || layer.hidden || layer.opacity<=.01) return CGRectNull;
    if (depth>32) { *remaining=0; return CGRectNull; }
    --*remaining;
    // A subtractive compositing layer removes pixels; its rectangle must not
    // enlarge the glyph envelope. Model values, never presentation opacity.
    id filter=layer.compositingFilter; NSString *kind=nil;
    if ([filter isKindOfClass:NSString.class]) kind=filter;
    else if (filter) { @try { id value=[filter valueForKey:@"type"]; if ([value isKindOfClass:NSString.class]) kind=value; } @catch (__unused NSException *e) {} }
    if ([kind isEqualToString:@"destOut"] || [kind isEqualToString:@"destinationOut"]) return CGRectNull;
    CGRect ink=C18GlyphLayerContents(layer);
    if (layer.backgroundColor && CGColorGetAlpha(layer.backgroundColor)>0) ink=CGRectUnion(ink,layer.bounds);
    // CALayer's default borderColor is opaque black even when the property
    // getter returns nil; many original ring glyphs rely on that default.
    if (layer.borderWidth>0 && (!layer.borderColor || CGColorGetAlpha(layer.borderColor)>0)) ink=CGRectUnion(ink,layer.bounds);
    if ([layer isKindOfClass:CAShapeLayer.class]) {
        CAShapeLayer *shape=(CAShapeLayer *)layer;
        if (shape.path) {
            if (shape.fillColor && CGColorGetAlpha(shape.fillColor)>0) ink=CGRectUnion(ink,CGPathGetPathBoundingBox(shape.path));
            if (shape.lineWidth>0 && shape.strokeColor && CGColorGetAlpha(shape.strokeColor)>0) {
                CGLineCap cap=[shape.lineCap isEqualToString:kCALineCapRound]?kCGLineCapRound:([shape.lineCap isEqualToString:kCALineCapSquare]?kCGLineCapSquare:kCGLineCapButt);
                CGLineJoin join=[shape.lineJoin isEqualToString:kCALineJoinRound]?kCGLineJoinRound:([shape.lineJoin isEqualToString:kCALineJoinBevel]?kCGLineJoinBevel:kCGLineJoinMiter);
                CGPathRef stroke=CGPathCreateCopyByStrokingPath(shape.path,NULL,shape.lineWidth,cap,join,shape.miterLimit);
                if (stroke) { ink=CGRectUnion(ink,CGPathGetPathBoundingBox(stroke));CGPathRelease(stroke); }
            }
        }
    }
    // Use the active model-state layers only. Hidden light/dark branches and
    // transparent portal helpers are not visible glyphs. State-independent
    // resource frames are not allowed to inflate the measurement.
    for (CALayer *child in layer.sublayers) {
        CGRect part=C18GlyphLayerInk(child,depth+1,remaining);
        if (C18GlyphRectValid(part)) {
            part=[child convertRect:part toLayer:layer];
            if (C18GlyphRectValid(part)) ink=CGRectUnion(ink,part);
        }
    }
    if (layer.mask) {
        CGRect mask=C18GlyphMaskRect(layer.mask,C18GlyphLayerInk(layer.mask,depth+1,remaining));
        if (!C18GlyphRectValid(mask)) return CGRectNull;
        // A backdrop paints through its mask even without contents/background.
        if ([NSStringFromClass(layer.class) containsString:@"BackdropLayer"]) ink=CGRectUnion(ink,mask);
        ink=CGRectIntersection(ink,mask);
    }
    if (layer.masksToBounds) ink=CGRectIntersection(ink,layer.bounds);
    return C18GlyphRectValid(ink)?ink:CGRectNull;
}
CGRect C18GlyphPackageVisibleBounds(UIView *view) {
    if (![view isKindOfClass:UIView.class]) return CGRectNull;
    [view layoutIfNeeded]; [view.layer layoutIfNeeded];
    // State controllers change child geometry/hidden/opacity without replacing
    // package or outer sublayers. Recompute from the current model tree.
    NSUInteger remaining=2048;
    CGRect ink=C18GlyphLayerInk(view.layer,0,&remaining);
    return remaining && C18GlyphRectValid(ink)?ink:CGRectNull;
}
UIView *C18GlyphPackageView(id button) {
    id package=C18FiveGet(button,@"_glyphPackageView");
    if (![package isKindOfClass:UIView.class]) return nil;
    // A CCUICAPackageView can exist before any package is installed. It is
    // not a successful source until it owns actual Core Animation content.
    id contents=C18FiveObject(package,NSSelectorFromString(@"package"))?:C18FiveGet(package,@"_package");
    return contents && ![(UIView *)package isHidden]?(UIView *)package:nil;
}
