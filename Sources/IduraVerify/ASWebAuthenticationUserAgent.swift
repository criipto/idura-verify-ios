internal import AppAuth
private import AuthenticationServices

/// An OIDC user agent, using `ASWebAuthenticationSession`.
@MainActor
class ASWebAuthenticationUserAgent: NSObject, @preconcurrency OIDExternalUserAgent,
  ASWebAuthenticationPresentationContextProviding
{
  fileprivate func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
    presenting.view.window!
  }

  private let presenting: UIViewController
  private let redirectUri: URL
  private let useEphemeralBrowserSession: Bool
  private let headers: [String: String]?

  private var webAuth: ASWebAuthenticationSession?

  init(
    presenting: UIViewController, redirectUri: URL, useEphemeralBrowserSession: Bool,
    headers: [String: String]? = nil
  ) {
    self.presenting = presenting
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
    webAuth.presentationContextProvider = self
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
