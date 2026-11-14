#import "C18SIMService.h"
#import "C18SIMPrivate.h"
#import "C18SIMRuntime.h"
#import <CoreTelephony/CTCarrier.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <dlfcn.h>
#import <spawn.h>
#import <sys/wait.h>
#import <unistd.h>
#import <errno.h>

extern char **environ;

@implementation C18SIMLine
- (instancetype)init {
    if ((self=[super init])) _name=@"运营商未知";
    return self;
}
@end

static NSString *SIMString(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *text=[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return text.length?text:nil;
}
static NSString *SIMChineseCarrier(NSString *mcc, NSString *mnc) {
    if (![mcc isEqualToString:@"460"] || !mnc.length) return nil;
    if ([@[@"00",@"02",@"04",@"07",@"08"] containsObject:mnc]) return @"中国移动";
    if ([@[@"01",@"06",@"09"] containsObject:mnc]) return @"中国联通";
    if ([@[@"03",@"05",@"11"] containsObject:mnc]) return @"中国电信";
    if ([mnc isEqualToString:@"15"]) return @"中国广电";
    return nil;
}
static NSString *SIMNormalizeCarrier(NSString *value) {
    NSString *text=SIMString(value);
    if (!text || [@[@"--",@"Carrier",@"运营商",@"Unknown",@"未知"] containsObject:text]) return nil;
    NSString *lower=text.lowercaseString;
    if ([lower containsString:@"unicom"] || [text containsString:@"联通"]) return @"中国联通";
    if ([lower containsString:@"china telecom"] || [lower isEqualToString:@"ctcc"] || [text containsString:@"电信"]) return @"中国电信";
    if ([lower containsString:@"china mobile"] || [lower isEqualToString:@"cmcc"] || [text containsString:@"移动"]) return @"中国移动";
    if ([lower containsString:@"china broadnet"] || [text containsString:@"广电"]) return @"中国广电";
    return text;
}
static NSString *SIMHelperPath(void) {
    // Resolve relative to this module's installed image, including the current RootHide root.
    Dl_info info={0};
    if (!dladdr((const void *)&SIMHelperPath,&info) || !info.dli_fname) return nil;
    NSString *image=[NSString stringWithUTF8String:info.dli_fname];
    NSRange marker=[image rangeOfString:@"/Library/ControlCenter/Bundles/" options:NSBackwardsSearch];
    if (marker.location==NSNotFound) return nil;
    NSString *prefix=[image substringToIndex:marker.location];
    // The CC18 package already owns this exact helper and its original signature.
    // Do not use the standalone package's separate /usr/libexec installation.
    NSString *path=[prefix stringByAppendingString:@"/usr/local/bin/CCSIMTool"];
    return access(path.fileSystemRepresentation,X_OK)==0?path:nil;
}

@interface C18SIMService ()
@property(nonatomic,strong) CoreTelephonyClient *client;
@property(nonatomic,strong) CTTelephonyNetworkInfo *network;
@property(nonatomic,strong) dispatch_queue_t workQueue;
- (NSArray<C18SIMLine *> *)readNow;
@end

@implementation C18SIMService
- (instancetype)init {
    if (!(self=[super init])) return nil;
    _workQueue=dispatch_queue_create("com.ning.simcontrol.telephony",DISPATCH_QUEUE_SERIAL);
    Class cls=NSClassFromString(@"CoreTelephonyClient");
    if ([cls instancesRespondToSelector:@selector(initWithQueue:)]) _client=[[(id)cls alloc] initWithQueue:dispatch_get_main_queue()];
    _network=[CTTelephonyNetworkInfo new];
    return self;
}
- (NSString *)carrierForContext:(CTXPCServiceSubscriptionContext *)context {
    NSError *error=nil;
    NSString *name=nil;
    // The SIM's home PLMN is stable while roaming; never use the user-editable SIM label.
    if ([self.client respondsToSelector:@selector(copyMobileSubscriberCountryCode:error:)] &&
        [self.client respondsToSelector:@selector(copyMobileSubscriberNetworkCode:error:)]) {
        NSString *mcc=SIMString([self.client copyMobileSubscriberCountryCode:context error:&error]);
        error=nil;
        NSString *mnc=SIMString([self.client copyMobileSubscriberNetworkCode:context error:&error]);
        name=SIMChineseCarrier(mcc,mnc);
    }
    NSDictionary<NSString *,CTCarrier *> *providers=self.network.serviceSubscriberCellularProviders;
    NSUUID *uuid=[context respondsToSelector:@selector(uuid)]?context.uuid:nil;
    // Match a provider only by this subscription UUID. Dictionary ordering is not a card-slot identity.
    CTCarrier *carrier=nil;
    if (uuid) for (NSString *key in providers) {
        if ([key caseInsensitiveCompare:uuid.UUIDString]==NSOrderedSame) { carrier=providers[key]; break; }
    }
    if (!name && carrier) name=SIMNormalizeCarrier(carrier.carrierName) ?: SIMChineseCarrier(carrier.mobileCountryCode,carrier.mobileNetworkCode);
    if (!name && [self.client respondsToSelector:@selector(getLocalizedOperatorName:error:)]) {
        error=nil; name=SIMNormalizeCarrier([self.client getLocalizedOperatorName:context error:&error]);
    }
    if (!name && [self.client respondsToSelector:@selector(getOperatorName:error:)]) {
        error=nil; name=SIMNormalizeCarrier([self.client getOperatorName:context error:&error]);
    }
    return name;
}
- (NSArray<C18SIMLine *> *)readNow {
    if (!self.client || ![self.client respondsToSelector:@selector(getSIMStatus:error:)]) return @[];
    NSMutableDictionary<NSNumber *,CTXPCServiceSubscriptionContext *> *contexts=[NSMutableDictionary dictionary];
    if ([self.client respondsToSelector:@selector(getSubscriptionInfoWithError:)]) {
        NSError *error=nil;
        id info=[self.client getSubscriptionInfoWithError:&error];
        id subscriptions=SIMObject(info,NSSelectorFromString(@"subscriptions"));
        if ([subscriptions isKindOfClass:NSArray.class]) for (CTXPCServiceSubscriptionContext *context in subscriptions) {
            if ([context respondsToSelector:@selector(slotID)] && context.slotID>=1 && context.slotID<=2) contexts[@(context.slotID)]=context;
        }
    }
    NSMutableArray *items=[NSMutableArray array];
    Class contextClass=NSClassFromString(@"CTXPCServiceSubscriptionContext");
    for (NSInteger slot=1;slot<=2;slot++) {
        CTXPCServiceSubscriptionContext *context=contexts[@(slot)];
        if (!context && [contextClass respondsToSelector:@selector(contextWithSlot:)]) context=[contextClass contextWithSlot:slot];
        C18SIMLine *item=[C18SIMLine new]; item.slot=slot;
        NSError *error=nil;
        NSString *status=context?SIMString([self.client getSIMStatus:context error:&error]):nil;
        item.enabled=[status isEqualToString:@"kCTSIMSupportSIMStatusReady"];
        BOOL configured=contexts[@(slot)]!=nil;
        BOOL readyState=status.length && ![status isEqualToString:@"kCTSIMSupportSIMStatusNotInserted"] &&
            ![status isEqualToString:@"kCTSIMSupportSIMStatusNotReady"];
        // Disabled subscriptions can report no SIM; keep configured lines re-enableable.
        item.available=context && !error && (configured || readyState);
        item.name=(context?[self carrierForContext:context]:nil) ?: @"运营商未知";
        [items addObject:item];
    }
    return items;
}
- (void)readItems:(C18SIMReadCompletion)completion {
    dispatch_async(self.workQueue,^{
        NSArray *items=nil; NSString *message=nil;
        @try { items=[self readNow]; if (!items.count) message=@"无法读取 SIM 信息"; }
        @catch (NSException *exception) { message=@"无法读取 SIM 信息"; }
        dispatch_async(dispatch_get_main_queue(),^{ completion(items ?: @[],message); });
    });
}
- (void)setItem:(C18SIMLine *)item enabled:(BOOL)enabled completion:(C18SIMActionCompletion)completion {
    NSInteger slot=item.slot;
    dispatch_async(self.workQueue,^{
        NSString *message=nil; BOOL accepted=NO;
        @try {
        NSArray<C18SIMLine *> *fresh=[self readNow];
        C18SIMLine *current=nil;
        for (C18SIMLine *value in fresh) if (value.slot==slot) current=value;
        if (!current.available || slot<1 || slot>2) message=@"此 SIM 卡当前不可操作";
        else if (current.enabled==enabled) accepted=YES;
        else {
            NSString *path=SIMHelperPath();
            if (!path) message=@"SIM 启停工具不可用";
            else {
                // Original CCSIM CLI: plan index 0/1, target enabled 0/1.
                NSString *index=[NSString stringWithFormat:@"%ld",(long)(slot-1)];
                NSString *target=enabled?@"1":@"0";
                char *args[]={(char *)path.fileSystemRepresentation,(char *)index.UTF8String,(char *)target.UTF8String,NULL};
                pid_t pid=0;
                int result=posix_spawn(&pid,path.fileSystemRepresentation,NULL,NULL,args,environ);
                if (result) message=@"无法启动 SIM 启停工具";
                else {
                    int status=0; pid_t waited;
                    do { waited=waitpid(pid,&status,0); } while (waited<0 && errno==EINTR);
                    accepted=waited==pid && WIFEXITED(status) && WEXITSTATUS(status)==0;
                    if (!accepted) message=@"SIM 启停请求失败";
                }
            }
        }
        } @catch (NSException *exception) { message=@"无法读取 SIM 信息，请关闭后重试"; }
        dispatch_async(dispatch_get_main_queue(),^{ completion(accepted,message); });
    });
}
@end
