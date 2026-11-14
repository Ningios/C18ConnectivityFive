#import "C18SIMPrivate.h"
#import "C18SIMService.h"

@interface C18SIMController : UIViewController <CCUIContentModuleContentViewController>
@property(nonatomic,strong) CCUIContentModuleContext *moduleContext;
@property(nonatomic,strong) C18SIMService *service;
- (void)openPanel;
- (BOOL)c18PerformLongPress;
@end
