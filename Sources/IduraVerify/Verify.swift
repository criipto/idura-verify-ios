@preconcurrency internal import AppAuth
@preconcurrency internal import AppAuthCore
import Combine
import Foundation
import JWTKit
@preconcurrency import OpenTelemetryApi
import OpenTelemetryConcurrency
import OpenTelemetrySdk

private let version = "2.0.0"

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

/// Entry point for the Idura Verify SDK. One instance can serve many logins; construct it once
/// at app startup and hold it for the lifetime of the process.
///
/// `IduraVerify` is stateful: on construction it kicks off background work to fetch the OIDC
/// discovery document and JWKS, caches both, and runs a telemetry exporter. Constructing a new
/// instance on every screen render wastes those requests and leaves the previous exporter
/// dangling.
///
/// ## SwiftUI
///
/// Store the instance in `@StateObject` (or inject via `@Environment`) so SwiftUI keeps a single
/// instance across view rebuilds:
///
/// ```swift
/// struct MainView: View {
///   @StateObject private var iduraVerify = IduraVerify(clientId: ..., domain: ...)
///   var body: some View { ... }
/// }
/// ```
///
/// Do *not* assign `IduraVerify(...)` to a plain stored property of a `View` — every state
/// change recomputes the view and would build a new instance.
@MainActor
public final class IduraVerify: ObservableObject {
  /// Held only so `deinit` can drain the span exporter; not used elsewhere. Marked
  /// `nonisolated(unsafe)` so the deinit (which is implicitly nonisolated on a `@MainActor`
  /// class) can read it. Safe: the property is a `let`, and `TracerProviderSdk.shutdown()`
  /// is documented to handle being called at process teardown.
  nonisolated(unsafe) private let tracerProvider: TracerProviderSdk
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
    self.tracerProvider = tracerProvider
    self.propagator = propagator
    tracer = tracerProvider.get(
      instrumentationName: "idura-verify", instrumentationVersion: version)

    self.domain = URL(string: "https://" + domain)!
    self.redirectUri = redirectUri ?? self.domain.appendingPathComponent("/ios/callback")
    self.clientId = clientId
    self.useEphemeralBrowserSession = useEphemeralBrowserSession ?? true

    // Optimistically try to load the OIDC config and JWKS configuration, so it is ready when the
    // user initiates a login. We run this in a Task because the constructor isn't async. The
    // Task inherits the main-actor isolation, so it serialises correctly with later `prepare()`
    // calls from `login(...)`. If an error is thrown here it's swallowed; `login(...)` will
    // retry and surface it.
    Task {
      try await self.prepare()
    }
  }

  deinit {
    tracerProvider.shutdown()
  }

  public func login(
    eid: some EID,
    prompt: Prompt? = .login,
    useEphemeralBrowserSession: Bool? = nil
  ) async throws -> LoginResult {
    return try await tracer.spanBuilder(spanName: "ios sdk login").setNoParent().setAttribute(
      key: "acr_value", value: eid.acrValue
    ).runWithSpan { span in
      let traceId = span.context.traceId.hexString
      do {
        try await prepare()

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

        // This convenience initializer auto-generates a nonce; we capture it so
        // we can verify the value round-trips back in the ID token.
        guard let expectedNonce = authorizationRequest.nonce else {
          throw IduraVerifyError.internalError(
            message: "Authorization request was built without a nonce", cause: nil, traceId: traceId
          )
        }

        let parRequest = try await pushAuthorizationRequest(authorizationRequest, span: span)
        let codeResponse = try await launchBrowser(
          request: parRequest, span: span, useEphemeralBrowserSession: useEphemeralBrowserSession)

        let jwt = try await exchanceCode(
          codeResponse: codeResponse, span: span, expectedNonce: expectedNonce)
        return LoginResult(jwt: jwt, traceId: traceId)
      } catch {
        throw IduraVerifyError.from(error, traceId: traceId)
      }
    }
  }

  private func launchBrowser(
    request: PARRequest, span: any SpanBase, useEphemeralBrowserSession: Bool?
  ) async throws -> OIDAuthorizationResponse {
    return try await tracer.spanBuilder(spanName: "launch browser").setParent(span.context)
      .runWithSpan { _ in
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
      }
  }

  private func exchanceCode(
    codeResponse: OIDAuthorizationResponse, span: any SpanBase, expectedNonce: String
  ) async throws
    -> JWT
  {
    let traceId = span.context.traceId.hexString
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
    return try await tracer.spanBuilder(spanName: "JWT verification").setParent(span.context)
      .runWithSpan { _ in
        let claims = try await iduraJwks!.verify(
          idToken,
          as: IDTokenClaims.self,
        )

        // JWTKit's verify(using:) handles signature + exp/nbf. The remaining
        // OIDC checks (iss, aud, nonce) need context the claim struct doesn't
        // carry, so we do them here.
        let expectedIssuer = iduraServiceConfiguration!.discoveryDocument!.issuer.absoluteString
        guard claims.iss.value == expectedIssuer else {
          throw IduraVerifyError.internalError(
            message:
              "ID token issuer mismatch (expected \(expectedIssuer), got \(claims.iss.value))",
            cause: nil, traceId: traceId)
        }
        try claims.aud.verifyIntendedAudience(includes: clientId)
        guard claims.nonce == expectedNonce else {
          throw IduraVerifyError.internalError(
            message: "ID token nonce did not match the value sent in the authorization request",
            cause: nil, traceId: traceId)
        }

        return JWT(idToken: idToken, claims: claims)
      }
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

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    if httpStatus != 201 {
      // Per RFC 9126 §2.3, PAR error responses use the OAuth 2.0 JSON error format.
      // Surface those as `.oauth` so e.g. a misconfigured redirect_uri produces an
      // actionable message rather than an opaque internal error.
      struct ParErrorResponse: Decodable {
        let error: String
        let errorDescription: String?
      }
      if let parsedError = try? decoder.decode(ParErrorResponse.self, from: data) {
        throw IduraVerifyError.oauth(
          error: parsedError.error,
          errorDescription: parsedError.errorDescription,
          traceId: span.context.traceId.hexString,
        )
      }
      throw IduraVerifyError.internalError(
        message: "PAR request failed: \(httpStatus.map(String.init) ?? "non-HTTP response")",
        cause: nil,
        traceId: span.context.traceId.hexString,
      )
    }

    struct ParResponse: Decodable {
      let requestUri: String
    }
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
