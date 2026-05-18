@preconcurrency internal import AppAuthCore
internal import AuthenticationServices
import Foundation

/// All runtime errors thrown by `IduraVerify.login()`.
///
/// Every case carries a `traceId` - You can view the traces in the Idura dashboard
///
/// Catch the umbrella type to handle any SDK failure uniformly, or match a specific case to
/// distinguish e.g. user cancellation from a real error:
///
/// ```swift
/// do {
///   let result = try await iduraVerify.login(eid: DanishMitID.substantial())
/// } catch IduraVerifyError.userCancelled(let traceId) {
///   // User dismissed the browser or the IdP returned `access_denied`. Usually a normal
///   // action — quietly return them to the previous screen rather than showing an error.
///   _ = traceId
/// } catch IduraVerifyError.oauth(let error, let errorDescription, let traceId) {
///   // The IdP returned a non-cancellation OAuth error.
///   _ = (error, errorDescription, traceId)
/// } catch let err as IduraVerifyError {
///   // Catch-all for SDK-internal failures (PAR, JWT verification, browser plumbing).
///   // Treat as unrecoverable; surface a generic message and log err.traceId.
///   _ = err.traceId
/// }
/// ```
public enum IduraVerifyError: Error {
  /// The user dismissed the authentication flow before it completed. Sources include the
  /// browser's cancel/Done button and the spec-standard `access_denied` OAuth error from the
  /// IdP. Usually a normal action, not an error condition.
  case userCancelled(traceId: String)

  /// The authorization server returned an OAuth/OIDC error response. The `error` code
  /// corresponds to the OAuth 2.0 standard error codes (e.g. `invalid_request`,
  /// `temporarily_unavailable`), with an optional human-readable `errorDescription`.
  ///
  /// The spec-standard `access_denied` — typically signalling user cancellation at the IdP
  /// level — is translated into ``userCancelled`` before reaching this case, so consumers
  /// only need to handle one cancellation type.
  case oauth(error: String, errorDescription: String?, traceId: String)

  /// The SDK's underlying machinery failed in a way the consumer can't reasonably recover
  /// from — PAR endpoint error, JWT signing-key mismatch, state-parameter mismatch, browser
  /// plumbing failure. Treat as an unrecoverable error; surface a generic message to the
  /// user and log the cause for investigation.
  case internalError(message: String, cause: (any Error)?, traceId: String)

  /// The Idura trace ID - View traces in the Idura dashboard.
  public var traceId: String {
    switch self {
    case .userCancelled(let traceId): return traceId
    case .oauth(_, _, let traceId): return traceId
    case .internalError(_, _, let traceId): return traceId
    }
  }
}

extension IduraVerifyError {
  /// Translates an arbitrary error thrown from AppAuth, AuthenticationServices, URLSession,
  /// or JWT verification into the SDK's typed hierarchy. AppAuth's user-cancellation code
  /// and `access_denied` OAuth response both fold into ``userCancelled``; other OAuth
  /// authorization-endpoint errors surface as ``oauth``; anything else is opaque to the
  /// consumer and surfaces as ``internalError`` with the original error preserved as cause.
  static func from(_ error: any Error, traceId: String) -> IduraVerifyError {
    if let already = error as? IduraVerifyError {
      return already
    }

    let nsError = error as NSError

    let userCancelled =
      (nsError.domain == OIDGeneralErrorDomain
        && nsError.code == OIDErrorCode.userCanceledAuthorizationFlow.rawValue)
      || (nsError.domain == ASWebAuthenticationSessionErrorDomain
        && nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue)
    if userCancelled {
      return .userCancelled(traceId: traceId)
    }

    if nsError.domain == OIDOAuthAuthorizationErrorDomain {
      let response = nsError.userInfo[OIDOAuthErrorResponseErrorKey] as? [String: Any]
      let oauthError = response?[OIDOAuthErrorFieldError] as? String ?? "unknown_error"
      let oauthDescription = response?[OIDOAuthErrorFieldErrorDescription] as? String
      if oauthError == "access_denied" {
        return .userCancelled(traceId: traceId)
      }
      return .oauth(error: oauthError, errorDescription: oauthDescription, traceId: traceId)
    }

    return .internalError(message: nsError.localizedDescription, cause: error, traceId: traceId)
  }
}
