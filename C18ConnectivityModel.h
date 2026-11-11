#ifndef C18_CONNECTIVITY_MODEL_H
#define C18_CONNECTIVITY_MODEL_H
#include <stdbool.h>
#include <math.h>

typedef struct { double x, y, side; bool primary; } C18Position;
// Geometry is independent of the module identifier stored in each slot.
static inline int C18CalculatePositions(int mode, double w, double h, C18Position out[7]) {
    if ((mode!=4 && mode!=5) || !out || !isfinite(w) || !isfinite(h) ||
        w<200 || h<45 || w<h*2.0) return 0;
    double gap=5.0, inset=6.0;
    double d=fmin(h-2*inset,(w-2*inset-4*gap)/5.0);
    if (d<35.0) return 0;
    double x=(w-5*d-4*gap)*0.5, y=(h-d)*0.5;
    for (int i=0;i<mode;i++) out[i]=(C18Position){x+i*(d+gap),y,d,true};
    if (mode==5) return 5;
    double s=(d-5.0)*0.5, start=x+4*(d+gap);
    for (int j=0;j<3;j++) {
        double sx=j==0 ? start : (j==1 ? start+s+5.0 : start+(d-s)*0.5);
        out[4+j]=(C18Position){sx,j==2 ? y+d-s : y,s,false};
    }
    return 7;
}
#endif
