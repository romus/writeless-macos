#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Domain of the errors `WLPerformCatchingExceptions` produces. `code` is always
/// zero; the exception's name and reason are in `NSLocalizedDescriptionKey`.
extern NSErrorDomain const WLExceptionGuardErrorDomain;

/// Runs `block`, turning any raised `NSException` into an `NSError`.
///
/// AVFAudio reports a format its engine graph disagrees with by raising rather
/// than by returning an error, and a raise that reaches Swift is an `abort()` —
/// which is how a 24 kHz microphone used to take the whole app down. Returns
/// YES when the block ran to completion.
BOOL WLPerformCatchingExceptions(void (NS_NOESCAPE ^block)(void),
                                 NSError *_Nullable *_Nullable error);

NS_ASSUME_NONNULL_END
