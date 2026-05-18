import Foundation
import JWTKit
import Testing

@testable import IduraVerify

private func makeClaims(exp: Date, nbf: Date) -> IDTokenClaims {
  IDTokenClaims(
    sub: "test-sub",
    aud: "test-aud",
    iss: "https://test.example",
    identityscheme: "test",
    exp: ExpirationClaim(value: exp),
    nbf: NotBeforeClaim(value: nbf),
    iat: IssuedAtClaim(value: Date()),
    nonce: "test-nonce"
  )
}

@Test
func verifyTimeClaims_acceptsTokenJustExpired() throws {
  let now = Date()
  let claims = makeClaims(exp: now.addingTimeInterval(-60), nbf: now.addingTimeInterval(-3600))
  try claims.verifyTimeClaims(at: now)
}

@Test
func verifyTimeClaims_rejectsTokenExpiredBeyondSkew() {
  let now = Date()
  let claims = makeClaims(exp: now.addingTimeInterval(-600), nbf: now.addingTimeInterval(-3600))
  #expect(throws: (any Error).self) {
    try claims.verifyTimeClaims(at: now)
  }
}

@Test
func verifyTimeClaims_acceptsTokenWithFutureNbfWithinSkew() throws {
  let now = Date()
  let claims = makeClaims(exp: now.addingTimeInterval(3600), nbf: now.addingTimeInterval(60))
  try claims.verifyTimeClaims(at: now)
}

@Test
func verifyTimeClaims_rejectsTokenWithFutureNbfBeyondSkew() {
  let now = Date()
  let claims = makeClaims(exp: now.addingTimeInterval(3600), nbf: now.addingTimeInterval(600))
  #expect(throws: (any Error).self) {
    try claims.verifyTimeClaims(at: now)
  }
}
