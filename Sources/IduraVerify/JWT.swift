import JWTKit
import SwiftUI

// This struct is used internally, to extract and validate known claims.
internal struct IDTokenClaims: JWTPayload {
  let sub: String
  let aud: AudienceClaim
  let iss: IssuerClaim
  let identityscheme: String
  let exp: ExpirationClaim
  let nbf: NotBeforeClaim
  let iat: IssuedAtClaim
  let nonce: String

  func verify(using _: some JWTAlgorithm) throws {
    try verifyTimeClaims(at: Date())
  }

  // Lenient on both sides: a token that just expired is still accepted, and a
  // token whose nbf is just in the future is also accepted.
  func verifyTimeClaims(at now: Date, skew: TimeInterval = 5 * 60) throws {
    try exp.verifyNotExpired(currentDate: now.addingTimeInterval(-skew))
    try nbf.verifyNotBefore(currentDate: now.addingTimeInterval(skew))
  }
}

public struct JWT {
  public let idToken: String

  public let subject: String
  public let audience: String
  public let issuer: String
  public let identityscheme: String
  public let expireAt: Date
  public let notBefore: Date
  public let issuedAt: Date
  public let dictionary: [String: Any]

  internal init(idToken: String, claims: IDTokenClaims) {
    self.idToken = idToken
    self.subject = claims.sub
    // OIDC ID tokens for a public client are scoped to a single client. The JWT
    // spec also permits an audience array, which JWTKit's AudienceClaim decodes
    // transparently — we surface the first entry here.
    self.audience = claims.aud.value.first ?? ""
    self.issuer = claims.iss.value
    self.expireAt = claims.exp.value
    self.notBefore = claims.nbf.value
    self.issuedAt = claims.iat.value
    self.identityscheme = claims.identityscheme

    let parser = DefaultJWTParser()

    // At this point, we have already extracted the token parts, and parsed the token. We know for
    // sure that extraction and parsing won't fail, so we use force tries and casts.
    // swiftlint:disable force_try force_cast
    let (_, encodedPayload, _) = try! parser.getTokenParts([UInt8](idToken.utf8))
    let payloadBytes = encodedPayload.base64URLDecodedBytes()

    self.dictionary =
      try! JSONSerialization.jsonObject(with: Data(payloadBytes), options: []) as! [String: Any]
    // swiftlint:enable force_try force_cast
  }

  public func getClaimValue(key: String) -> Any? {
    return dictionary[key]
  }
}

// START: extension methods borrowed from JWTKit. Needed to convert a base64 URL encoded JWT payload
// to regular base64.

extension DataProtocol {
  fileprivate func base64URLDecodedBytes() -> [UInt8] {
    Data(base64Encoded: Data(copyBytes()).base64URLUnescaped())?.copyBytes() ?? []
  }
}

extension Data {
  /// Converts base64-url encoded data to a base64 encoded data.
  ///
  /// https://tools.ietf.org/html/rfc4648#page-7
  fileprivate mutating func base64URLUnescape() {
    for idx in self.indices {
      switch self[idx] {
      case 0x2D:  // -
        self[idx] = 0x2B  // +
      case 0x5F:  // _
        self[idx] = 0x2F  // /
      default: break
      }
    }
    /// https://stackoverflow.com/questions/43499651/decode-base64url-to-base64-swift
    let padding = count % 4
    if padding > 0 {
      self += Data(repeating: 0x3D, count: 4 - count % 4)
    }
  }

  /// Converts base64-url encoded data to a base64 encoded data.
  ///
  /// https://tools.ietf.org/html/rfc4648#page-7
  fileprivate func base64URLUnescaped() -> Data {
    var data = self
    data.base64URLUnescape()
    return data
  }
}
// END: extension methods borrowed from JWTKit
