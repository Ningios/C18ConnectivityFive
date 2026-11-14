#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

@class CCUIContentModuleContext;

@protocol CCUIContentModuleContentViewController <NSObject>
- (double)preferredExpandedContentHeight;
@optional
- (double)preferredExpandedContentWidth;
- (bool)providesOwnPlatter;
- (bool)shouldBeginTransitionToExpandedContentModule;
- (bool)shouldFinishTransitionToExpandedContentModule;
- (void)willTransitionToExpandedContentMode:(bool)expanded;
- (void)didTransitionToExpandedContentMode:(bool)expanded;
- (void)controlCenterWillPresent;
- (void)controlCenterDidDismiss;
- (bool)canDismissPresentedContent;
@end

@protocol CCUIContentModule <NSObject>
- (UIViewController<CCUIContentModuleContentViewController> *)contentViewController;
@optional
- (UIViewController *)backgroundViewController;
- (void)setContentModuleContext:(CCUIContentModuleContext *)context;
@end

@interface CCUIContentModuleContext : NSObject
- (void)requestExpandModule;
- (void)dismissModule;
@end

// Declaration-only interfaces. Implementations are provided by iOS 16/17.
@interface CoreTelephonyClient : NSObject
- (instancetype)initWithQueue:(dispatch_queue_t)queue;
- (id)getSubscriptionInfoWithError:(NSError **)error;
- (id)getSIMStatus:(id)context error:(NSError **)error;
- (id)getLocalizedOperatorName:(id)context error:(NSError **)error;
- (id)getOperatorName:(id)context error:(NSError **)error;
- (id)copyMobileSubscriberCountryCode:(id)context error:(NSError **)error;
- (id)copyMobileSubscriberNetworkCode:(id)context error:(NSError **)error;
@end

@interface CTXPCServiceSubscriptionContext : NSObject
+ (instancetype)contextWithSlot:(long long)slot;
@property(nonatomic,readonly) long long slotID;
@property(nonatomic,readonly) NSUUID *uuid;
@property(nonatomic,readonly) bool isSimPresent;
@end
