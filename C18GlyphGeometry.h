#pragma once
#include <math.h>

// Preserve beta10's physical size for normally sized sources. Correct only
// an image/package whose old visible extent is below 90% of the fixed glyph.
// Inputs are in one coordinate space; zero/unknown extent is never enlarged.
static inline double C18GlyphDesiredVisibleSide(double inkSide,double canvasSide,
                                               double legacyTarget,double referenceInk) {
    if (!isfinite(inkSide) || !isfinite(canvasSide) || !isfinite(legacyTarget) ||
        !isfinite(referenceInk) || inkSide<=0 || canvasSide<=0 || legacyTarget<=0 || referenceInk<=0) return 0;
    double original=inkSide*legacyTarget/canvasSide;
    return original<referenceInk*.90?referenceInk:original;
}
