@preconcurrency internal import AppAuth
@preconcurrency internal import AppAuthCore
import JWTKit
import SwiftUI
import os

public struct IDTokenClaims: JWTPayload {
  public var sub: String
  public var name: String?
  public var identityscheme: String
  public var uuid: String?
  var exp: ExpirationClaim
  var nbf: NotBeforeClaim

  public func verify(using _: some JWTAlgorithm) throws {
    try exp.verifyNotExpired(
      currentDate: Calendar.current.date(byAdding: .minute, value: 5, to: Date())!)
  }
}

public class IduraVerify: @unchecked Sendable {
  let logger = Logger(subsystem: "eu.idura.loginexample", category: "LoginManager")

  var prepared = false
  /// A JSON Web Key Set (JWKS), containing the public keys used to verify that the obtained JWT
  /// was actually issued by Idura
  var iduraJwks: JWTKeyCollection?
  var iduraServiceConfiguration: OIDServiceConfiguration?

  let clientId: String
  let domain: URL
  let redirectUri: URL
  let appSwitchUri: URL?
  let useEphemeralBrowserSession = true

  public init(clientId: String, domain: String) {
    self.domain = URL(string: domain)!
    redirectUri = self.domain.appendingPathComponent("/ios/callback")
    appSwitchUri = self.domain.appendingPathComponent("/ios/callback/appswitch")
    self.clientId = clientId
  }

  private var currentAuthorizationSession: OIDExternalUserAgentSession?
  public func login<T>(
    presenting: UIViewController,
    eid: EID<T>,
  ) async throws -> (String, IDTokenClaims) {
    try await ensurePrepared()

    Task {
      @MainActor in
      self.currentAuthorizationSession?.cancel()
    }

    logger.log("Starting login flow for \(eid.acrValue)")

    var loginHints = [] + eid.loginHints
    var extraParams = [String: String]()

    extraParams["acr_values"] = eid.acrValue

    if let action = eid.action {
      loginHints.append("action:\(action.rawValue.lowercased())")
    }
    if eid is DanishMitID {
      loginHints.append("appswitch:ios")
      if appSwitchUri != nil {
        loginHints.append("appswitch:resumeUrl:\(appSwitchUri!)")
      }
    }

    extraParams["login_hint"] = loginHints.joined(separator: " ")

    let request = OIDAuthorizationRequest(
      configuration: iduraServiceConfiguration!,
      clientId: clientId,
      clientSecret: nil,
      scopes: [OIDScopeOpenID] + eid.scopes,
      redirectURL: redirectUri,
      responseType: OIDResponseTypeCode,
      additionalParameters: extraParams,
    )

    logger.debug(
      "Starting external authentication flow with URL: \(request.authorizationRequestURL())",
    )

    let authState = try await withCheckedThrowingContinuation { continuation in
      Task {
        // This is the code that presents the browser to the user, so it needs to run on the
        // main thread
        @MainActor in
        self.currentAuthorizationSession =
          OIDAuthState.authState(
            byPresenting: request,
            externalUserAgent: ASWebAuthenticationUserAgent(
              presenting: presenting,
              redirectUri: self.redirectUri,
              useEphemeralBrowserSession: self.useEphemeralBrowserSession,
            ),
          ) { authState, error in
            if let authState {
              continuation.resume(returning: authState)
            } else {
              continuation.resume(throwing: error!)
            }
          }
      }
    }
    currentAuthorizationSession = nil

    let idToken = authState.lastTokenResponse!.idToken!
    logger.debug("Got ID Token: \(idToken)")
    let claims = try await iduraJwks!.verify(
      idToken,
      as: IDTokenClaims.self,
    )

    return (idToken, claims)
  }

  public func logout(
    presenting: UIViewController,
    idTokenHint: String? = nil,
  ) async throws {
    try await ensurePrepared()

    let request = OIDEndSessionRequest(
      configuration: iduraServiceConfiguration!,
      idTokenHint: idTokenHint ?? "",
      postLogoutRedirectURL: redirectUri,
      additionalParameters: nil,
    )

    try await withCheckedThrowingContinuation { continuation in
      Task {
        @MainActor in
        self.currentAuthorizationSession = OIDAuthorizationService.present(
          request,
          externalUserAgent: ASWebAuthenticationUserAgent(
            presenting: presenting,
            redirectUri: self.redirectUri,
            useEphemeralBrowserSession: true,
          ),
        ) { response, error in
          if response != nil {
            continuation.resume()
          } else if error != nil {
            continuation.resume(throwing: error!)
          }
        }
      }
    }
    currentAuthorizationSession = nil
  }

  /// Prepare the login manager by loading Idura OIDC configuration and JWK keyset.
  /// This should be called when you present the 'Login with X' button to your user, so that the
  /// required configuration is already loaded when a user clicks the button.
  public func prepare() async throws {
    try await loadIduraOIDCConfiguration()
    try await loadIduraJwks()
    prepared = true
  }

  /// A helper method, used to ensure that the login manager is in the expected state when a login
  /// or logout starts. Ideally, the login manager should be prepared as soon as the button to log
  /// in is shown, but if the developer forgot, or the end-user started the flow before the
  /// prepare operation completed, we call prepare here.
  private func ensurePrepared() async throws {
    if !prepared {
      logger
        .debug(
          // swiftlint:disable:next line_length
          "LoginManager was not in prepared state when calling login / logout. This can happen either if you forget to call `prepare()` from your own code, if the call to `prepare()` failed, or if the user started a session before your call to `prepare()` completed.",
        )
      try await prepare()
    }
  }

  private func loadIduraJwks() async throws {
    guard iduraJwks == nil else { return }

    let (data, _) = try await URLSession.shared
      .data(from: domain.appendingPathComponent("/.well-known/jwks"))
    iduraJwks = try await JWTKeyCollection().add(
      jwksJSON: String(
        data: data,
        encoding: .utf8,
      )!)
  }

  private func loadIduraOIDCConfiguration() async throws {
    guard iduraServiceConfiguration == nil else { return }

    iduraServiceConfiguration =
      try await withCheckedThrowingContinuation { continuation in
        OIDAuthorizationService
          .discoverConfiguration(forIssuer: self.domain) { configuration, error in
            if error != nil {
              continuation.resume(throwing: error!)
            } else if configuration != nil {
              continuation.resume(returning: configuration!)
            }
          }
      }
  }
}
