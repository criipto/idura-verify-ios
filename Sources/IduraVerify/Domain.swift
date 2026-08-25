import Foundation

/// Errors thrown while constructing ``IduraVerify``. Kept separate from ``IduraVerifyError``
/// because they originate before any login flow has started, so there is no trace ID to attach.
public enum IduraVerifyConfigurationError: Error {
  /// The `domain` passed to ``IduraVerify`` is not a bare hostname. The message names the
  /// offending value and what is wrong with it; it is aimed at the developer, not the end user.
  case invalidDomain(message: String)
}

extension IduraVerifyConfigurationError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidDomain(let message):
      return message
    }
  }
}

/// Turn a configured Idura domain into the base URL the SDK talks to.
///
/// The domain is expected to be a bare hostname — `your-tenant.criipto.id`, no scheme and no path —
/// because the same value is interpolated into the `webcredentials:`/`applinks:` entries of the
/// app's Associated Domains entitlement, where anything else is invalid. It normally reaches the
/// SDK from `Info.plist` via an xcconfig, so it can pick up surrounding whitespace on the way;
/// that we trim. Everything else is rejected rather than repaired, so a broken entitlement can't
/// hide behind a URL the SDK quietly fixed up.
func iduraDomainURL(_ domain: String) throws -> URL {
  func invalid(_ reason: String) -> IduraVerifyConfigurationError {
    .invalidDomain(
      message: "Invalid Idura domain \(domain.debugDescription): \(reason). Expected a bare "
        + "hostname such as \"your-tenant.criipto.id\".")
  }

  let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else { throw invalid("the value is empty") }
  guard !trimmed.contains("://") else { throw invalid("it must not include a scheme") }

  // `URL(string:)` returns nil for characters that can't appear in an authority — a space, a
  // newline, `[`, a stray `%` — and yields a nil host for input that parses as something other
  // than a hostname.
  guard let url = URL(string: "https://" + trimmed), let host = url.host(), !host.isEmpty else {
    throw invalid("it is not a valid hostname")
  }

  // A path, query or fragment here would survive into every URL derived from the domain: a
  // `?a=b` suffix, for instance, ends up on the JWKS and callback URLs. A trailing slash is
  // harmless for those, but the Associated Domains entitlement rejects it — "Don't include path
  // and query components or a trailing slash (/)" — so it can't be allowed either.
  // https://developer.apple.com/documentation/xcode/supporting-associated-domains
  guard url.path().isEmpty else {
    throw invalid("it must not include a path or a trailing slash")
  }
  guard url.query() == nil else { throw invalid("it must not include a query string") }
  guard url.fragment() == nil else { throw invalid("it must not include a fragment") }
  guard url.user() == nil else { throw invalid("it must not include credentials") }

  return url
}
