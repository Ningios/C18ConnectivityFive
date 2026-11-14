#import "C18SIMController.h"

@interface CCSIM : NSObject <CCUIContentModule>
@property(nonatomic,strong) C18SIMController *controller;
@property(nonatomic,strong) CCUIContentModuleContext *contentModuleContext;
@end

@implementation CCSIM
- (UIViewController<CCUIContentModuleContentViewController> *)contentViewController {
    if (!self.controller) {
        self.controller=[C18SIMController new];
        self.controller.service=[C18SIMService new];
        self.controller.moduleContext=self.contentModuleContext;
    }
    return self.controller;
}
- (void)setContentModuleContext:(CCUIContentModuleContext *)context {
    _contentModuleContext=context;
    self.controller.moduleContext=context;
}
- (UIViewController *)backgroundViewController { return nil; }
@end
