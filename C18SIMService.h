#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface C18SIMLine : NSObject
@property(nonatomic) NSInteger slot;
@property(nonatomic,copy) NSString *name;
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL available;
@end

typedef void (^C18SIMReadCompletion)(NSArray<C18SIMLine *> *items, NSString * _Nullable error);
typedef void (^C18SIMActionCompletion)(BOOL accepted, NSString * _Nullable error);

@interface C18SIMService : NSObject
- (void)readItems:(C18SIMReadCompletion)completion;
- (void)setItem:(C18SIMLine *)item enabled:(BOOL)enabled completion:(C18SIMActionCompletion)completion;
@end

@interface C18SIMRow : UIControl
- (void)updateWithItem:(C18SIMLine *)item busy:(BOOL)busy;
@end

NS_ASSUME_NONNULL_END
