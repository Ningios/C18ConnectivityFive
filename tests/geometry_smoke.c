#include <assert.h>
#include <math.h>
#include "../C18ConnectivityModel.h"
int main(void) {
    C18Position p[7];
    int n=C18CalculatePositions(5,252,60,p); assert(n==5);
    for(int i=0;i<n;i++) {
        assert(p[i].primary && p[i].side>=35);
        assert(p[i].x>=0 && p[i].y>=0);
        assert(p[i].x+p[i].side<=252 && p[i].y+p[i].side<=60);
        if(i) assert(p[i].x>=p[i-1].x+p[i-1].side);
    }
    n=C18CalculatePositions(5,132,132,p); assert(n==4);
    for(int i=0;i<n;i++) {
        assert(p[i].primary && p[i].side>=35);
        assert(p[i].x>=0 && p[i].y>=0);
        assert(p[i].x+p[i].side<=132 && p[i].y+p[i].side<=132);
    }
    assert(C18CalculatePositions(5,400,330,p)==4);
    assert(C18CalculatePositions(5,70,70,p)==0);
    assert(C18CalculatePositions(5,NAN,132,p)==0);
    assert(C18CalculatePositions(4,252,60,p)==7);
    return 0;
}
