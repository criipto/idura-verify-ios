import Foundation
import Testing

@testable import IduraVerify

private let connectionLost = NSError(
  domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)

/// Shaped like AppAuth's `OIDErrorUtilities.errorWithCode:underlyingError:description:` output
/// for a failed token request: `OIDGeneralErrorDomain` / `OIDErrorCodeNetworkError`.
private func appAuthNetworkError(underlying: NSError?) -> NSError {
  var userInfo: [String: Any] = [:]
  userInfo[NSUnderlyingErrorKey] = underlying
  return NSError(domain: "org.openid.appauth.general", code: -5, userInfo: userInfo)
}

@Test func isConnectionLost_matchesBareURLError() {
  #expect(isConnectionLost(connectionLost))
}

@Test func isConnectionLost_matchesErrorWrappedByAppAuth() {
  #expect(isConnectionLost(appAuthNetworkError(underlying: connectionLost)))
}

@Test(
  arguments: [
    NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut),
    NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet),
    appAuthNetworkError(underlying: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)),
    appAuthNetworkError(underlying: nil),
    // Same code, different domain.
    NSError(domain: NSPOSIXErrorDomain, code: NSURLErrorNetworkConnectionLost),
  ])
func isConnectionLost_ignoresOtherErrors(error: NSError) {
  #expect(!isConnectionLost(error))
}

@MainActor
@Test func retryingOnceOnConnectionLost_retriesOnce() async throws {
  var attempts = 0
  var retries = 0
  let result = try await retryingOnceOnConnectionLost {
    attempts += 1
    if attempts == 1 { throw appAuthNetworkError(underlying: connectionLost) }
    return "token"
  } onRetry: { _ in
    retries += 1
  }
  #expect(result == "token")
  #expect(attempts == 2)
  #expect(retries == 1)
}

@MainActor
@Test func retryingOnceOnConnectionLost_doesNotRetryOtherErrors() async {
  var attempts = 0
  let timedOut = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
  await #expect(throws: timedOut) {
    try await retryingOnceOnConnectionLost { () async throws -> String in
      attempts += 1
      throw timedOut
    }
  }
  #expect(attempts == 1)
}

@MainActor
@Test func retryingOnceOnConnectionLost_surfacesSecondFailure() async {
  var attempts = 0
  let second = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
  await #expect(throws: second) {
    try await retryingOnceOnConnectionLost { () async throws -> String in
      attempts += 1
      throw attempts == 1 ? connectionLost : second
    }
  }
  #expect(attempts == 2)
}
