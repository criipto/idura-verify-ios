import JWTKit
import SwiftUI

// This struct is used internally, to extract and validate known claims.
internal struct IDTokenClaims: JWTPayload {
  public let sub: String
  public let aud: String
  public let iss: String
  public let identityscheme: String
  public let exp: ExpirationClaim
  public let nbf: NotBeforeClaim
  public let iat: IssuedAtClaim

  public func verify(using _: some JWTAlgorithm) throws {
    let currentDate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
    try exp.verifyNotExpired(currentDate: currentDate)
    try nbf.verifyNotBefore(currentDate: currentDate)
  }
}

public struct JWT {
  public let idToken: String

  public let subject: String
  public let audience: String
  public let issuer: String
  public let identityscheme: String
  public let expireAt: ExpirationClaim
  public let notBefore: NotBeforeClaim
  public let issuedAt: IssuedAtClaim

  internal init(idToken: String, claims: IDTokenClaims) {
    self.idToken = idToken
    self.subject = claims.sub
    self.audience = claims.aud
    self.issuer = claims.iss
    self.expireAt = claims.exp
    self.notBefore = claims.nbf
    self.issuedAt = claims.iat
    self.identityscheme = claims.identityscheme
  }

  public lazy var dictionary: [String: Any] = {
    let parser = DefaultJWTParser()

    // At this point, we have already extracted the token parts, and parsed the token. We know for
    // sure that extraction and parsing won't fail, so we use force tries and casts.
    // swiftlint:disable force_try force_cast
    let (_, encodedPayload, _) = try! parser.getTokenParts([UInt8](idToken.utf8))
    let payloadBytes = encodedPayload.base64URLDecodedBytes()

    let dictionary =
      try! JSONSerialization.jsonObject(with: Data(payloadBytes), options: []) as! [String: Any]
    // swiftlint:enable force_try force_cast

    return dictionary
  }()

  public mutating func getClaimValue(key: String) -> Any? {
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
