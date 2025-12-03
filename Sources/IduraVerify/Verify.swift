@preconcurrency internal import AppAuth
@preconcurrency internal import AppAuthCore
import JWTKit
@preconcurrency import OpenTelemetryApi
import OpenTelemetryConcurrency
import SwiftUI
import os

// TODO: remember to update this when pushing a new version!
private let version = "0.0.1"

public enum IduraVerifyErrors: Error {
  case parInitializationError
}

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

public enum Prompt: String {
  case login = "login"
  case none = "none"
  case consent = "consent"
  case consentRevoke = "consent_revoke"
}

private class PARRequest: OIDAuthorizationRequest, @unchecked Sendable {
  var parRequestUri: URL?
  init(request: OIDAuthorizationRequest, parRequestUri: URL) {
    super.init(
      configuration: request.configuration,
      clientId: request.clientID,
      clientSecret: nil,
      scope: request.scope,
      redirectURL: request.redirectURL!,
      responseType: request.responseType,
      state: request.state,
      nonce: request.nonce,
      codeVerifier: request.codeVerifier,
      codeChallenge: request.codeChallenge,
      codeChallengeMethod: request.codeChallengeMethod,
      additionalParameters: request.additionalParameters,
    )
    self.parRequestUri = parRequestUri
  }
  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }
  override func externalUserAgentRequestURL() -> URL {
    return parRequestUri!
  }
}

public class IduraVerify: @unchecked Sendable {
  let logger = Logger(subsystem: "eu.idura.loginexample", category: "LoginManager")
  let tracer: Tracer
  let propagator: TextMapPropagator

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
    let (tracerProvider, propagator) = initTelemetry(serverAddress: domain, version: version)
    self.propagator = propagator
    tracer = tracerProvider.get(
      instrumentationName: "idura-verify", instrumentationVersion: version)

    self.domain = URL(string: "https://" + domain)!
    redirectUri = self.domain.appendingPathComponent("/ios/callback")
    appSwitchUri = self.domain.appendingPathComponent("/ios/callback/appswitch")
    self.clientId = clientId
  }

  public func login<T>(
    presenting: UIViewController,
    eid: EID<T>,
    prompt: Prompt? = .login
  ) async throws -> (String, IDTokenClaims) {
    return try await tracer.spanBuilder(spanName: "ios sdk login").setNoParent().setAttribute(
      key: "acr_value", value: eid.acrValue
    ).runWithSpan { span in
      try await ensurePrepared()

      logger.log(
        "Starting login flow for \(eid.acrValue), traceId \(span.context.traceId.hexString)")

      var loginHints = [] + eid.loginHints
      var extraParams = [String: String]()

      extraParams["acr_values"] = eid.acrValue

      if let prompt {
        extraParams["prompt"] = prompt.rawValue
      }

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

      let authorizationRequest = OIDAuthorizationRequest(
        configuration: iduraServiceConfiguration!,
        clientId: clientId,
        clientSecret: nil,
        scopes: [OIDScopeOpenID] + eid.scopes,
        redirectURL: redirectUri,
        responseType: OIDResponseTypeCode,
        additionalParameters: extraParams,
      )

      logger.debug(
        "Starting external authentication flow with URL: \(authorizationRequest.authorizationRequestURL())",
      )

      let parRequest = try await pushAuthorizationRequest(authorizationRequest, span: span)
      let codeResponse = try await launchBrowser(
        presenting: presenting, request: parRequest, span: span)

      return try await exchanceCode(codeResponse: codeResponse, span: span)
    }
  }

  private func launchBrowser(presenting: UIViewController, request: PARRequest, span: any SpanBase)
    async throws
    -> OIDAuthorizationResponse
  {
    return try await tracer.spanBuilder(spanName: "launch browser").setParent(span.context)
      .runWithSpan {
        _ in
        return try await Task {
          // This is the code that presents the browser to the user, so it needs to run on the
          // main thread
          @MainActor in
          return try await withCheckedThrowingContinuation { continuation in
            OIDAuthorizationService.present(
              request,
              externalUserAgent: ASWebAuthenticationUserAgent(
                presenting: presenting,
                redirectUri: self.redirectUri,
                useEphemeralBrowserSession: self.useEphemeralBrowserSession,
              )
            ) { response, error in
              if let response {
                continuation.resume(returning: response)
              } else if let error {
                continuation.resume(throwing: error)
              }
            }
          }
        }.value
      }
  }

  private func exchanceCode(codeResponse: OIDAuthorizationResponse, span: any SpanBase) async throws
    -> (
      String, IDTokenClaims
    )
  {
    let tokenResponse = try await tracer.spanBuilder(spanName: "code exchange").setParent(
      span.context
    ).runWithSpan { _ in
      return try await withCheckedThrowingContinuation { continuation in
        OIDAuthorizationService.perform(codeResponse.tokenExchangeRequest()!) { response, error in
          if let response {
            continuation.resume(returning: response)
          } else if let error {
            continuation.resume(throwing: error)
          }
        }
      }
    }

    let idToken = tokenResponse.idToken!
    logger.debug("Got ID Token: \(idToken)")
    let claims =
      try await tracer.spanBuilder(spanName: "JWT verification").setParent(span.context)
      .runWithSpan { _ in
        return try await iduraJwks!.verify(
          idToken,
          as: IDTokenClaims.self,
        )
      }
    return (idToken, claims)
  }

  private func pushAuthorizationRequest(
    _ authorizationRequest: OIDAuthorizationRequest, span: any SpanBase
  )
    async throws
    -> PARRequest
  {
    let parEndpoint = URL(
      string: iduraServiceConfiguration!.discoveryDocument!.discoveryDictionary[
        // We know the par endpoint will be defined
        // swiftlint:disable:next force_cast
        "pushed_authorization_request_endpoint"] as! String)!

    var parInitializationRequest = URLRequest(url: parEndpoint)
    parInitializationRequest.httpMethod = "POST"
    parInitializationRequest.httpBody = URLComponents(
      url: authorizationRequest.authorizationRequestURL(), resolvingAgainstBaseURL: false)?.query?
      .data(using: .utf8)

    propagator.inject(
      spanContext: span.context,
      carrier: &parInitializationRequest.allHTTPHeaderFields!,
      setter: URLRequestSetter.instance)

    let (data, response) = try await URLSession.shared.data(for: parInitializationRequest)
    if (response as? HTTPURLResponse)?.statusCode != 201 {
      throw IduraVerifyErrors.parInitializationError
    }

    struct ParResponse: Decodable {
      let requestUri: String
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let parResponse = try decoder.decode(ParResponse.self, from: data)

    var urlBuilder = URLComponents(
      url: iduraServiceConfiguration!.authorizationEndpoint, resolvingAgainstBaseURL: false)!
    urlBuilder.queryItems = [
      URLQueryItem(name: "client_id", value: clientId),
      URLQueryItem(name: "request_uri", value: parResponse.requestUri),
    ]
    return PARRequest(request: authorizationRequest, parRequestUri: urlBuilder.url!)
  }

  public func logout(
    presenting: UIViewController,
    idTokenHint: String? = nil,
  ) async throws {
    return try await tracer.spanBuilder(spanName: "ios sdk logout").setNoParent().runWithSpan {
      span in
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
          var headers = [String: String]()
          propagator.inject(
            spanContext: span.context,
            carrier: &headers,
            setter: URLRequestSetter.instance)
          OIDAuthorizationService.present(
            request,
            externalUserAgent: ASWebAuthenticationUserAgent(
              presenting: presenting,
              redirectUri: self.redirectUri,
              useEphemeralBrowserSession: true,
              headers: headers
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
    }
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
