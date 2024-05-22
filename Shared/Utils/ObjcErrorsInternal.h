#import <Foundation/Foundation.h>

NS_INLINE NSException * _Nullable ExecuteWithObjCExceptionHandling(void(NS_NOESCAPE^_Nonnull tryBlock)(void)) {
    @try {
        tryBlock();
    }
    @catch (NSException *exception) {
        return exception;
    }
    return nil;
}
