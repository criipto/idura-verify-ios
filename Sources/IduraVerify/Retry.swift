import Foundation

/// Whether `error`, or any error it wraps, is URLSession's "network connection lost" (-1005).
/// AppAuth reports transport failures as `OIDErrorCodeNetworkError` with the URLSession error
/// under `NSUnderlyingErrorKey`, so the top-level code alone never matches.
func isConnectionLost(_ error: any Error) -> Bool {
  var current: NSError? = error as NSError
  while let nsError = current {
    if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorNetworkConnectionLost {
      return true
    }
    current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
  }
  return false
}

/// Runs `operation`, and runs it once more if the first attempt fails with a lost connection.
///
/// iOS suspends the app while the user is in an eID app, and the keep-alive connection pooled
/// from before the switch can be dead by the time the app resumes. The first request on it then
/// fails with -1005. URLSession only retries that on its own for idempotent requests, so a POST
/// surfaces it to the caller. See https://developer.apple.com/library/archive/qa/qa1941/_index.html
@MainActor
func retryingOnceOnConnectionLost<T>(
  _ operation: @MainActor () async throws -> T,
  onRetry: @MainActor (any Error) -> Void = { _ in }
) async throws -> T {
  do {
    return try await operation()
  } catch  where isConnectionLost(error) {
    onRetry(error)
    return try await operation()
  }
}
