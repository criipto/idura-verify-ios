import Testing

@testable import IduraVerify

@Test func mitid_substantial_with_scopes() async throws {
  let mitid = DanishMitID.substantial().withSsn()

  #expect(mitid.acrValue == "urn:grn:authn:dk:mitid:substantial")
  #expect(mitid.scopes == ["ssn"])
}

@Test
func mitid_high_prefill() {
  let ssn = "1234564444"
  let mitid = DanishMitID.high().prefillSsn(ssn)

  #expect(mitid.acrValue == "urn:grn:authn:dk:mitid:high")
  #expect(mitid.scopes == ["ssn"])
  #expect(mitid.loginHints == ["sub:\(ssn)"])
}

@Test
func other_falback() {
  let acrValue = "urn:grn:authn:foo:bar"
  let other = Other(acrValue: acrValue).withScope("something")

  #expect(other.acrValue == acrValue)
  #expect(other.scopes == ["something"])
}
