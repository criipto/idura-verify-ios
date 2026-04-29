@preconcurrency internal import AppAuth
@preconcurrency internal import AppAuthCore
import Foundation
import JWTKit
@preconcurrency import OpenTelemetryApi
import OpenTelemetryConcurrency
import os

private let version = "1.0.1"

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
  let useEphemeralBrowserSession: Bool

  public init(
    clientId: String, domain: String, redirectUri: URL? = nil,
    useEphemeralBrowserSession: Bool? = nil,
  ) {
    let (tracerProvider, propagator) = initTelemetry(serverAddress: domain, version: version)
    self.propagator = propagator
    tracer = tracerProvider.get(
      instrumentationName: "idura-verify", instrumentationVersion: version)

    self.domain = URL(string: "https://" + domain)!
    self.redirectUri = redirectUri ?? self.domain.appendingPathComponent("/ios/callback")
    self.clientId = clientId
    self.useEphemeralBrowserSession = useEphemeralBrowserSession ?? true

    // Optimistically try to load the OIDC config and JWKS configuration, so it is ready when the
    // user initiates a login.
    // We run this in a detached task, since we don't want the constructor to be async. If an error
    // is thrown here, it will be swallowed. We then retry when calling `login`,
    // bubbling any errors.
    Task.detached {
      try await self.prepare()
    }
  }

  public func login(
    eid: some EID,
    prompt: Prompt? = .login,
    useEphemeralBrowserSession: Bool? = nil
  ) async throws -> (String, JWT) {
    do {
      return try await tracer.spanBuilder(spanName: "ios sdk login").setNoParent().setAttribute(
        key: "acr_value", value: eid.acrValue
      ).runWithSpan { span in
        try await prepare()

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
        if eid.supportsAppSwitch {
          if !eid.acrValue.starts(with: "urn:grn:authn:se:bankid") {
            loginHints.append("appswitch:ios")
          }
          loginHints.append("appswitch:resumeUrl:\(redirectUri)")
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
          request: parRequest, span: span, useEphemeralBrowserSession: useEphemeralBrowserSession)

        return try await exchanceCode(codeResponse: codeResponse, span: span)
      }
    } catch {
      throw IduraVerifyError.from(error)
    }
  }

  private func launchBrowser(
    request: PARRequest, span: any SpanBase, useEphemeralBrowserSession: Bool?
  )
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
                redirectUri: self.redirectUri,
                useEphemeralBrowserSession: useEphemeralBrowserSession
                  ?? self.useEphemeralBrowserSession,
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
      String, JWT
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
    let jwt =
      try await tracer.spanBuilder(spanName: "JWT verification").setParent(span.context)
      .runWithSpan { _ in
        let claims = try await iduraJwks!.verify(
          idToken,
          as: IDTokenClaims.self,
        )
        let jwt = JWT(idToken: idToken, claims: claims)

        return jwt
      }
    return (idToken, jwt)
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
    let httpStatus = (response as? HTTPURLResponse)?.statusCode
    if httpStatus != 201 {
      throw IduraVerifyError.internalError(
        message: "PAR request failed: \(httpStatus.map(String.init) ?? "non-HTTP response")",
        cause: nil,
      )
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

  /// Prepare the login manager by loading Idura OIDC configuration and JWK keyset.
  private func prepare() async throws {
    guard !prepared else { return }
    try await loadIduraOIDCConfiguration()
    try await loadIduraJwks()
    prepared = true
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
