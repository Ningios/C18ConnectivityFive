#import "C18Five.h"

static NSString *C18SIMString(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *text=[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return text.length?text:nil;
}
static NSString *C18SIMChineseCarrier(NSString *mcc,NSString *mnc) {
    if (![mcc isEqualToString:@"460"] || !mnc.length) return nil;
    if ([@[@"00",@"02",@"04",@"07",@"08"] containsObject:mnc]) return @"中国移动";
    if ([@[@"01",@"06",@"09"] containsObject:mnc]) return @"中国联通";
    if ([@[@"03",@"05",@"11"] containsObject:mnc]) return @"中国电信";
    if ([mnc isEqualToString:@"15"]) return @"中国广电";
    return nil;
}
static NSString *C18SIMNormalizeCarrier(id value) {
    NSString *text=C18SIMString(value);
    if (!text || [@[@"--",@"Carrier",@"运营商",@"Unknown",@"未知"] containsObject:text]) return nil;
    NSString *lower=text.lowercaseString;
    if ([lower containsString:@"unicom"] || [text containsString:@"联通"]) return @"中国联通";
    if ([lower containsString:@"china telecom"] || [lower isEqualToString:@"ctcc"] || [text containsString:@"电信"]) return @"中国电信";
    if ([lower containsString:@"china mobile"] || [lower isEqualToString:@"cmcc"] || [text containsString:@"移动"]) return @"中国移动";
    if ([lower containsString:@"china broadnet"] || [text containsString:@"广电"]) return @"中国广电";
    return text;
}
static id C18SIMContextResult(id client,NSString *selectorName,id context) {
    SEL selector=NSSelectorFromString(selectorName);
    if (!context || ![client respondsToSelector:selector]) return nil;
    NSError *error=nil;
    return ((id(*)(id,SEL,id,NSError **))objc_msgSend)(client,selector,context,&error);
}
static NSDictionary<NSNumber *,NSString *> *C18SIMCarrierNames(id client) {
    NSMutableDictionary *names=[NSMutableDictionary dictionary];
    @try {
        NSMutableDictionary *contexts=[NSMutableDictionary dictionary];
        SEL infoSelector=NSSelectorFromString(@"getSubscriptionInfoWithError:");
        if ([client respondsToSelector:infoSelector]) {
            NSError *error=nil;
            id info=((id(*)(id,SEL,NSError **))objc_msgSend)(client,infoSelector,&error);
            id subscriptions=C18FiveObject(info,NSSelectorFromString(@"subscriptions"));
            if ([subscriptions isKindOfClass:NSArray.class]) for (id context in subscriptions) {
                SEL slotSelector=NSSelectorFromString(@"slotID");
                if (![context respondsToSelector:slotSelector]) continue;
                long long slot=((long long(*)(id,SEL))objc_msgSend)(context,slotSelector);
                if (slot>=1 && slot<=2) contexts[@(slot)]=context;
            }
        }
        id network=[NSClassFromString(@"CTTelephonyNetworkInfo") new];
        id providers=C18FiveObject(network,NSSelectorFromString(@"serviceSubscriberCellularProviders"));
        if (![providers isKindOfClass:NSDictionary.class]) providers=nil;
        Class contextClass=NSClassFromString(@"CTXPCServiceSubscriptionContext");
        SEL contextSelector=NSSelectorFromString(@"contextWithSlot:");
        for (long long slot=1;slot<=2;slot++) {
            id context=contexts[@(slot)];
            if (!context && [contextClass respondsToSelector:contextSelector]) context=((id(*)(id,SEL,long long))objc_msgSend)(contextClass,contextSelector,slot);
            NSString *mcc=C18SIMString(C18SIMContextResult(client,@"copyMobileSubscriberCountryCode:error:",context));
            NSString *mnc=C18SIMString(C18SIMContextResult(client,@"copyMobileSubscriberNetworkCode:error:",context));
            NSString *name=C18SIMChineseCarrier(mcc,mnc);
            id uuid=C18FiveObject(context,NSSelectorFromString(@"uuid"));
            NSString *uuidString=C18SIMString(C18FiveObject(uuid,NSSelectorFromString(@"UUIDString")));
            // Match by subscription UUID; provider dictionary order is not a card-slot identity.
            id carrier=nil;
            if (uuidString) for (id key in providers) {
                if ([key isKindOfClass:NSString.class] && [key caseInsensitiveCompare:uuidString]==NSOrderedSame) { carrier=[providers objectForKey:key]; break; }
            }
            if (!name && carrier) name=C18SIMNormalizeCarrier(C18FiveObject(carrier,NSSelectorFromString(@"carrierName"))) ?: C18SIMChineseCarrier(C18FiveObject(carrier,NSSelectorFromString(@"mobileCountryCode")),C18FiveObject(carrier,NSSelectorFromString(@"mobileNetworkCode")));
            if (!name) name=C18SIMNormalizeCarrier(C18SIMContextResult(client,@"getLocalizedOperatorName:error:",context));
            if (!name) name=C18SIMNormalizeCarrier(C18SIMContextResult(client,@"getOperatorName:error:",context));
            names[@(slot)]=name ?: @"运营商未知";
        }
    } @catch (NSException *exception) { /* The original SIM action remains available if names cannot be read. */ }
    return [names copy];
}
@protocol C18CarrierClientInit <NSObject>
- (instancetype)initWithQueue:(dispatch_queue_t)queue;
@end
void C18FiveResolveCarrierNames(id client, void (^completion)(NSDictionary<NSNumber *,NSString *> *names)) {
    if (!completion) return;
    // Names are presentation only. This provider never toggles a SIM or changes data selection.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        id resolvedClient=client;
        if (!resolvedClient) {
            Class cls=objc_getClass("CoreTelephonyClient");
            if (cls && [cls instancesRespondToSelector:@selector(initWithQueue:)]) {
                id<C18CarrierClientInit> allocated=[cls alloc];
                resolvedClient=[allocated initWithQueue:dispatch_get_global_queue(QOS_CLASS_UTILITY,0)];
            }
        }
        NSDictionary *names=resolvedClient?C18SIMCarrierNames(resolvedClient):@{};
        dispatch_async(dispatch_get_main_queue(),^{ completion(names ?: @{}); });
    });
}
