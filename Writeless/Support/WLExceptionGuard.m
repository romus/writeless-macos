#import "WLExceptionGuard.h"

NSErrorDomain const WLExceptionGuardErrorDomain = @"dev.romus.writeless.ExceptionGuard";

BOOL WLPerformCatchingExceptions(void (NS_NOESCAPE ^block)(void),
                                 NSError *_Nullable *_Nullable error) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error != NULL) {
            NSString *reason = exception.reason ?: @"no reason given";
            *error = [NSError errorWithDomain:WLExceptionGuardErrorDomain
                                         code:0
                                     userInfo:@{
                                         NSLocalizedDescriptionKey:
                                             [NSString stringWithFormat:@"%@: %@", exception.name, reason]
                                     }];
        }
        return NO;
    }
}
