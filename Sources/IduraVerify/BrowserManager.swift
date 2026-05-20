private import AuthenticationServices
import Foundation
import UIKit

/// Errors thrown by `BrowserManager`. Kept separate from `IduraVerifyError` because they
/// originate before any login flow has started, so there is no trace ID to attach.
public enum BrowserManagerError: Error {
  /// The browser session could not be configured or started. Thrown when `redirectUri` does
  /// not use the `https` scheme (init time), or when `ASWebAuthenticationSession` refuses to
  /// start — typically because the `redirectUri`'s host is not configured as an Associated
  /// Domain in the app's entitlements.
  case configurationError(message: String)
}

extension BrowserManagerError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .configurationError(let message):
      return message
    }
  }
}

private class PresentationContextProvider: NSObject,
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

/// Holds the live `ASWebAuthenticationSession` so the task-cancellation handler can reach
/// it from outside the main actor. Writes and reads of `session` are confined to the main
/// actor (the continuation body, and the `Task { @MainActor ... }` hop inside `onCancel`),
/// so the `@unchecked Sendable` conformance is safe.
private final class SessionBox: @unchecked Sendable {
  var session: ASWebAuthenticationSession?
}

/// A thin wrapper around `ASWebAuthenticationSession` that opens a URL in a system browser and
/// returns the callback URL when the flow completes.
///
/// `IduraVerify` uses this internally as part of the OIDC login flow, but it is also exposed as
/// public API so that applications that initialize the OIDC request on their own backend (e.g.
/// hybrid setups such as Auth0) can still use the SDK to present the browser and receive the
/// callback without pulling in AppAuth themselves.
public final class BrowserManager {
  private let redirectUri: URL
  private let useEphemeralBrowserSession: Bool

  public init(
    redirectUri: URL, useEphemeralBrowserSession: Bool,
  ) throws {
    if redirectUri.scheme != "https" {
      throw BrowserManagerError.configurationError(message: "redirectUri must use https scheme")
    }

    self.redirectUri = redirectUri
    self.useEphemeralBrowserSession = useEphemeralBrowserSession
  }

  @MainActor
  public func present(url: URL) async throws -> URL {
    let box = SessionBox()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let webAuth = ASWebAuthenticationSession(
          url: url,
          callback: ASWebAuthenticationSession.Callback.https(
            host: redirectUri.host()!,
            path: redirectUri.path(),
          ),
        ) { url, error in
          if let error {
            continuation.resume(throwing: error)
          } else if let url {
            continuation.resume(returning: url)
          }
        }

        webAuth.prefersEphemeralWebBrowserSession = useEphemeralBrowserSession
        webAuth.presentationContextProvider = PresentationContextProvider.shared

        box.session = webAuth

        if !webAuth.start() {
          continuation.resume(
            throwing: BrowserManagerError.configurationError(
              message:
                "ASWebAuthenticationSession failed to start. Verify that the redirectUri's host is configured as an Associated Domain in the app's entitlements."
            ))
          return
        }

        // If the task was cancelled while the continuation was being set up, cancel the
        // session now so the completion handler fires with `.canceledLogin` and the
        // continuation resumes.
        if Task.isCancelled {
          webAuth.cancel()
        }
      }
    } onCancel: { [box] in
      Task { @MainActor in
        box.session?.cancel()
      }
    }
  }
}
