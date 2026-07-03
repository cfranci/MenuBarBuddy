#import "include/ExceptionShield.h"

NSException *MBBTryCatch(void (NS_NOESCAPE ^block)(void)) {
    @try {
        block();
        return nil;
    } @catch (NSException *exception) {
        return exception;
    }
}
