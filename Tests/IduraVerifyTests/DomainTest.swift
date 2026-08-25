import Foundation
import Testing

@testable import IduraVerify

@Test(
  arguments: [
    ("samples.criipto.id", "https://samples.criipto.id"),
    ("samples.criipto.id:8443", "https://samples.criipto.id:8443"),
    // Whitespace is what an xcconfig or a hand-edited Info.plist tends to add.
    ("  samples.criipto.id  ", "https://samples.criipto.id"),
    ("samples.criipto.id\n", "https://samples.criipto.id"),
  ])
func iduraDomainURL_accepts(domain: String, expected: String) throws {
  #expect(try iduraDomainURL(domain).absoluteString == expected)
}

@Test(
  arguments: [
    "",
    "   ",
    // Characters that are invalid in an authority: `URL(string:)` returns nil for all of these,
    // which used to be force-unwrapped.
    "samples criipto id",
    "sam ples.criipto.id",
    "samples\n.criipto.id",
    "sam[ples.criipto.id",
    "sam%ples.criipto.id",
    // Parses, but not as a hostname.
    "foo:bar",
    // Parses as a URL with the wrong host ("https"), so the SDK would talk to the wrong place.
    "https://samples.criipto.id",
    "http://samples.criipto.id",
    // Would leak into every derived URL, including the JWKS request.
    "samples.criipto.id/some/path",
    // Harmless in a URL, but invalid in the Associated Domains entitlement.
    "samples.criipto.id/",
    "samples.criipto.id?a=b",
    "samples.criipto.id#fragment",
    "user:pw@samples.criipto.id",
  ])
func iduraDomainURL_rejects(domain: String) {
  #expect(throws: IduraVerifyConfigurationError.self) {
    try iduraDomainURL(domain)
  }
}

@Test
func iduraDomainURL_errorMessageNamesTheOffendingValue() throws {
  let error = #expect(throws: IduraVerifyConfigurationError.self) {
    try iduraDomainURL("sam ples.criipto.id")
  }

  let message = try #require(error?.errorDescription)
  #expect(message.contains("sam ples.criipto.id"))
  #expect(message.contains("your-tenant.criipto.id"))
}

@Test
func iduraDomainURL_derivedURLs() throws {
  let domain = try iduraDomainURL(" samples.criipto.id ")

  #expect(
    domain.appendingPathComponent("/ios/callback").absoluteString
      == "https://samples.criipto.id/ios/callback")
  #expect(
    domain.appendingPathComponent("/.well-known/jwks").absoluteString
      == "https://samples.criipto.id/.well-known/jwks")
}
