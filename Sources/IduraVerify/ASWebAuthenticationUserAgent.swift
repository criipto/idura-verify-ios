internal import AppAuth
internal import AuthenticationServices

internal class PresentationContextProvider: NSObject,
  ASWebAuthenticationPresentationContextProviding
{
  public static let shared = PresentationContextProvider()

  public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }

    // Prioritize the scene that is currently active and visible
    let activeScene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first

    // Find the key window or the first available window in that scene
    return activeScene?.windows.first { $0.isKeyWindow } ?? activeScene?.windows.first
      // Fallback to a new ASPresentationAnchor (UIWindow) if all else fails
      ?? ASPresentationAnchor()
  }
}

/// An OIDC user agent, using `ASWebAuthenticationSession`.
@MainActor
class ASWebAuthenticationUserAgent: NSObject, @preconcurrency OIDExternalUserAgent {
  private let redirectUri: URL
  private let useEphemeralBrowserSession: Bool
  private let headers: [String: String]?

  private var webAuth: ASWebAuthenticationSession?

  init(
    redirectUri: URL, useEphemeralBrowserSession: Bool, headers: [String: String]? = nil,
  ) {
    self.redirectUri = redirectUri
    self.useEphemeralBrowserSession = useEphemeralBrowserSession
    self.headers = headers
  }

  func present(
    _ request: any OIDExternalUserAgentRequest,
    session: any OIDExternalUserAgentSession,
  ) -> Bool {
    let webAuth = ASWebAuthenticationSession(
      url: request.externalUserAgentRequestURL(),
      callback: ASWebAuthenticationSession.Callback.https(
        host: redirectUri.host()!,
        path: redirectUri.path(),
      ),
    ) { url, error in
      if let error {
        session.failExternalUserAgentFlowWithError(error)
      } else if let url {
        session.resumeExternalUserAgentFlow(with: url)
      }
    }
    self.webAuth = webAuth

    webAuth.prefersEphemeralWebBrowserSession = useEphemeralBrowserSession
    webAuth.presentationContextProvider = PresentationContextProvider.shared
    if let headers {
      webAuth.additionalHeaderFields = headers
    }

    return webAuth.start()
  }

  func dismiss(animated _: Bool, completion: @escaping () -> Void) {
    webAuth?.cancel()
    completion()
  }
}
