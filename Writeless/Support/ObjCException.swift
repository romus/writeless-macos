import Foundation

/// Swift cannot catch an `NSException`, and AVFAudio raises one whenever the
/// audio format it is handed disagrees with what its engine graph believes the
/// hardware is doing. Unhandled, that raise is an `abort()`. Everything that
/// hands a format to AVFAudio goes through here instead.
nonisolated enum ObjCException {
    /// Runs `body`, rethrowing its own errors and converting a raised
    /// `NSException` into a thrown one.
    static func guarding(_ body: () throws -> Void) throws {
        var thrown: Error?
        var raised: NSError?
        let completed = WLPerformCatchingExceptions({
            do { try body() } catch { thrown = error }
        }, &raised)

        if let thrown { throw thrown }
        guard completed else {
            throw raised ?? NSError(
                domain: WLExceptionGuardErrorDomain,
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "The audio engine refused the request."]
            )
        }
    }
}
