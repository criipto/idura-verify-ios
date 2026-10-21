import Foundation
import Testing

@testable import IduraVerify

private let connectionLost = NSError(
  domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)

/// What `login()` throws when AppAuth's token request loses its connection: AppAuth's
/// `OIDErrorCodeNetworkError` wrapping the URLSession error, wrapped in turn by the SDK.
private let tokenRequestFailure = IduraVerifyError.internalError(
  message: "Connection error making token request",
  cause: NSError(
    domain: "org.openid.appauth.general", code: -5,
    userInfo: [NSUnderlyingErrorKey: connectionLost]),
  traceId: "trace")

@Test func iduraVerifyError_exposesCauseAsUnderlyingError() {
  let underlying = (tokenRequestFailure as NSError).userInfo[NSUnderlyingErrorKey] as? NSError
  #expect(underlying?.domain == "org.openid.appauth.general")
  #expect(underlying?.code == -5)
}

@Test func iduraVerifyError_keepsLocalizedDescriptionAlongsideUserInfo() {
  #expect(
    (tokenRequestFailure as NSError).localizedDescription == "Connection error making token request"
  )
}

@Test func errorChain_walksFromSDKErrorToURLError() {
  #expect(
    errorChain(tokenRequestFailure).map(errorTypeName) == [
      "IduraVerifyError.internalError",
      "org.openid.appauth.general(-5)",
      "NSURLErrorDomain(-1005)",
    ])
}

@Test func errorChain_stopsAtErrorWithoutCause() {
  #expect(
    errorChain(IduraVerifyError.userCancelled(traceId: "trace")).map(errorTypeName) == [
      "IduraVerifyError.userCancelled"
    ])
}

@Test func exceptionAttributes_identifyInnermostError() {
  let attributes = exceptionAttributes(tokenRequestFailure)
  #expect(attributes["idura.error.domain"] == .string(NSURLErrorDomain))
  #expect(attributes["idura.error.code"] == .int(NSURLErrorNetworkConnectionLost))
  #expect(
    attributes["idura.error.chain"]
      == .string(
        "IduraVerifyError.internalError → org.openid.appauth.general(-5) → NSURLErrorDomain(-1005)"
      ))
}
