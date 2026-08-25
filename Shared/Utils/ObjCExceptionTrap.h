#import <Foundation/Foundation.h>

/// Runs `body`, converting any Objective-C exception it raises into an error.
///
/// AVFoundation reports misuse by raising `NSException` rather than returning an
/// `NSError`, and Swift has no `catch` for that: the raise unwinds into
/// `objc_terminate` and the process takes `SIGABRT`. Roam 1.51 died this way on
/// macOS when `-[AVAudioPlayerNode play]` raised from `AudioPlayer.start`.
///
/// `try?` cannot help there, so calls into AVFAudio that can raise go through
/// here instead. Returns `YES` when `body` ran to completion, `NO` when it
/// raised, in which case `error` (when non-NULL) carries the exception's name and
/// reason.
///
/// This is a backstop, not a licence to ignore preconditions -- an exception
/// still means the graph was in a state the caller should have rejected. Check
/// the condition first and use this to survive the cases that slip through.
static inline BOOL roamRunCatchingNSException(
    __attribute__((noescape)) void (^body)(void), NSError **error) {
    @try {
        body();
        return YES;
    } @catch (NSException *exception) {
        if (error != NULL) {
            NSMutableDictionary *info = [NSMutableDictionary dictionary];
            info[NSLocalizedDescriptionKey] =
                exception.reason ?: @"Objective-C exception with no reason";
            info[@"RoamExceptionName"] = exception.name ?: @"(unnamed)";
            *error = [NSError errorWithDomain:@"io.msd3.roam.ObjCException"
                                         code:1
                                     userInfo:info];
        }
        return NO;
    }
}
