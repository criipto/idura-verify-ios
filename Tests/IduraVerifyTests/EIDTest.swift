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
func builder_does_not_share_state_between_branches() {
  // Regression test for the value-type conversion: with the previous reference-type
  // implementation, builder methods returned `self` after mutating in place, so
  // every "branch" of a chain shared state with earlier references.
  let base = DanishMitID.substantial().withMessage("hello")
  let withUuid = base.prefillUUID("abc")

  #expect(base.loginHints == ["message:aGVsbG8="])
  #expect(withUuid.loginHints == ["message:aGVsbG8=", "uuid:abc"])
}

@Test
func other_falback() {
  let acrValue = "urn:grn:authn:foo:bar"
  let other = Other(acrValue: acrValue).withScope("something")

  #expect(other.acrValue == acrValue)
  #expect(other.scopes == ["something"])
}

// MARK: - supportsAppSwitch

@Test
func supportsAppSwitch_typedBuilders() {
  #expect(DanishMitID.substantial().supportsAppSwitch == true)
  #expect(FrejaID.basic().supportsAppSwitch == true)
  #expect(SwedishBankID.sameDevice().supportsAppSwitch == true)

  #expect(NorwegianBankID.substantial().supportsAppSwitch == false)
  #expect(Vipps().supportsAppSwitch == false)
}

@Test
func supportsAppSwitch_otherFallback() {
  // The whole point of the data-driven property: Other("...") should match the same
  // prefixes that the typed builders do, so wrappers (e.g. an Expo / RN wrapper that
  // only has a string acr_value from JS) get the correct behaviour without having to
  // map strings back to the typed eID classes.
  #expect(Other(acrValue: "urn:grn:authn:dk:mitid:substantial").supportsAppSwitch == true)
  #expect(Other(acrValue: "urn:grn:authn:se:frejaid").supportsAppSwitch == true)
  #expect(Other(acrValue: "urn:grn:authn:se:bankid:same-device").supportsAppSwitch == true)

  #expect(Other(acrValue: "urn:grn:authn:no:bankid:substantial").supportsAppSwitch == false)
  #expect(Other(acrValue: "urn:grn:authn:foo:bar").supportsAppSwitch == false)
}
