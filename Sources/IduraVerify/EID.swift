import Foundation

public enum Action: String {
  case login
  case confirm
  case accept
  case approve
  case sign
}

private func base64Encode(_ str: String) -> String {
  (str.data(using: .utf8)?.base64EncodedString(
    options: Data.Base64EncodingOptions(rawValue: 0)))!
}

public class EID<T> {
  internal var scopes: [String] = []
  internal var loginHints: [String] = []
  internal var action: Action?
  internal var acrValues: [String]

  internal init(acrValues: [String]) {
    self.acrValues = acrValues
  }

  public var acrValue: String { acrValues.joined(separator: ":") }

  internal func getThis() -> T { preconditionFailure("This method must be overridden") }

  public func withScope(_ scope: String) -> T {
    scopes.append(scope)
    return getThis()
  }

  public func withLoginHint(_ loginHint: String) -> T {
    loginHints.append(loginHint)
    return getThis()
  }

  internal func withAction(_ action: Action) -> T {
    self.action = action
    return getThis()
  }

  internal func withMessage(_ message: String) -> T {
    withLoginHint(
      "message:\(base64Encode(message))"
    )
  }
}

public class DanishMitID: EID<DanishMitID> {
  private init(modifier: String) {
    super.init(acrValues: ["urn:grn:authn:dk:mitid", modifier])
  }
  override internal func getThis() -> DanishMitID { self }

  public static func substantial() -> DanishMitID { DanishMitID(modifier: "substantial") }
  public static func high() -> DanishMitID { DanishMitID(modifier: "high") }
  public static func low() -> DanishMitID { DanishMitID(modifier: "low") }
  public static func business() -> DanishMitID { DanishMitID(modifier: "business") }

  public func prefillSsn(_ ssn: String) -> DanishMitID { withSsn().withLoginHint("sub:\(ssn)") }

  /// Prefilling the UUID allows the user to skip entering their username,
  /// https://docs.idura.com/verify/e-ids/danish-mitid/#reauthentication
  public func prefillUUID(_ uuid: UUID) -> DanishMitID { prefillUUID(uuid.uuidString) }

  /// Prefilling the UUID allows the user to skip entering their username,
  /// https://docs.idura.com/verify/e-ids/danish-mitid/#reauthentication
  public func prefillUUID(_ uuid: String) -> DanishMitID { withLoginHint("uuid:\(uuid)") }

  public func prefillVatId(_ vatId: String) -> DanishMitID { withLoginHint("vatid:DK\(vatId)") }

  public func withSsn() -> DanishMitID { withScope("ssn") }

  public func withAddress() -> DanishMitID { withScope("address") }

  // This override is changing the visibility of the method from internal to public.
  // swiftlint:disable:next unneeded_override
  public override func withAction(_ action: Action) -> DanishMitID { super.withAction(action) }
  // swiftlint:disable:next unneeded_override
  public override func withMessage(_ message: String) -> DanishMitID { super.withMessage(message) }
}

public class NorwegianBankID: EID<NorwegianBankID> {
  private init(modifier: String) {
    super.init(acrValues: ["urn:grn:authn:no:bankid", modifier])
  }
  override internal func getThis() -> NorwegianBankID { self }

  public static func substantial() -> NorwegianBankID { NorwegianBankID(modifier: "substantial") }
  public static func high() -> NorwegianBankID { NorwegianBankID(modifier: "high") }

  public func withSsn() -> NorwegianBankID { withScope("ssn") }
}

public class SwedishBankID: EID<SwedishBankID> {
  private init(modifier: String?) {
    super.init(acrValues: ["urn:grn:authn:se:bankid", modifier].compactMap { $0 })
  }
  override internal func getThis() -> SwedishBankID { self }

  public static func otherDevice() -> SwedishBankID { SwedishBankID(modifier: "another-device:qr") }
  public static func sameDevice() -> SwedishBankID { SwedishBankID(modifier: "same-device") }
  public static func selectorPage() -> SwedishBankID { SwedishBankID(modifier: nil) }

  public func withSsn() -> SwedishBankID { withScope("ssn") }

  public func sign(message: String) -> SwedishBankID { withMessage(message).withAction(.sign) }

  // swiftlint:disable:next unneeded_override
  public override func withMessage(_ message: String) -> SwedishBankID {
    super.withMessage(message)
  }
}

public class Vipps: EID<Vipps> {
  public init() {
    super.init(acrValues: ["urn:grn:authn:no:vipps"])
  }
  override internal func getThis() -> Vipps { self }

  public func withEmail() -> Vipps { withScope("email") }
  public func withPhone() -> Vipps { withScope("phone") }
  public func withAddress() -> Vipps { withScope("address") }
  public func withBirthdate() -> Vipps { withScope("birthdate") }
  public func withSsn() -> Vipps { withScope("ssn") }
}

public class FrejaID<T>: EID<T> {
  internal init(minRegistrationLevel: String) {
    super.init(acrValues: ["urn:grn:authn:se:frejaid"])
    self.withLoginHint("minregistrationlevel:\(minRegistrationLevel)")
  }

  public func withEmail() -> T { withScope("frejaid:email_address") }
  public func withAllEmails() -> T { withScope("frejaid:all_email_addresses") }
  public func withPhoneNumbers() -> T { withScope("frejaid:all_phone_numbers") }
  public func withRegistrationLevel() -> T { withScope("frejaid:registration_level") }
  public func sign(message: String, title: String?) -> T {
    withAction(.sign)
    if let title {
      withLoginHint("title:\(base64Encode(title))")
    }
    return withMessage(message)
  }
}

// For the static methods, we don't care about T https://stackoverflow.com/a/62559410/800016
extension FrejaID where T == Any {
  public static func basic() -> FrejaIDBasic { FrejaIDBasic(minRegistrationLevel: "basic") }
  public static func extended() -> FrejaIDExtendedOrPlus {
    FrejaIDExtendedOrPlus(minRegistrationLevel: "extended")
  }
  public static func plus() -> FrejaIDExtendedOrPlus {
    FrejaIDExtendedOrPlus(minRegistrationLevel: "plus")
  }

}

public class FrejaIDBasic: FrejaID<FrejaIDBasic> {
  override internal func getThis() -> FrejaIDBasic { self }
}
public class FrejaIDExtendedOrPlus: FrejaID<FrejaIDExtendedOrPlus> {
  override internal func getThis() -> FrejaIDExtendedOrPlus { self }
  public func withBasicUserInfo() -> FrejaIDExtendedOrPlus { withScope("frejaid:basic_user_info") }
  public func withDateOfBirth() -> FrejaIDExtendedOrPlus { withScope("frejaid:date_of_birth") }
  public func withAge() -> FrejaIDExtendedOrPlus { withScope("frejaid:age") }
  public func withSsn() -> FrejaIDExtendedOrPlus { withScope("frejaid:ssn") }
  public func withAddresses() -> FrejaIDExtendedOrPlus { withScope("frejaid:addresses") }
  public func withDocument() -> FrejaIDExtendedOrPlus { withScope("frejaid:document") }
  public func withPhoto() -> FrejaIDExtendedOrPlus { withScope("frejaid:photo") }
  public func withDocumentPhoto() -> FrejaIDExtendedOrPlus { withScope("frejaid:document_photo") }
  public func withDefaultAndFaceConfirmation() -> FrejaIDExtendedOrPlus {
    withLoginHint("userconfirmationmethod:defaultandface")
  }
}

public class Mock: EID<Mock> {
  public init() {
    super.init(acrValues: ["urn:grn:authn:mock"])
  }
  override internal func getThis() -> Mock { self }

  /// Provide an object of mock data, which will be inserted into the returned JWT.
  /// The data must confirm to the https://developer.apple.com/documentation/swift/encodable protocol
  public func withMockData(_ data: Encodable) throws -> Mock {
    withMockData(String(data: try JSONEncoder().encode(data), encoding: .utf8)!)
  }

  /// Provide a JSON stringified object of mock data, which will be inserted into the returned JWT
  public func withMockData(_ data: String) -> Mock { withLoginHint("mock:\(base64Encode(data))") }
}

public class Other: EID<Other> {
  public init(acrValue: String) {
    super.init(acrValues: [acrValue])
  }
  override internal func getThis() -> Other { self }
}

public enum AgeVerificationCountry: String {
  case denmark = "DK"
  case sweden = "SE"
  case norway = "NO"
  case finland = "FI"
}

public enum AgeVerificationAge: Int {
  case over15 = 15
  case over16 = 16
  case over18 = 18
  case over21 = 21
}

public class AgeVerification: EID<AgeVerification> {
  private init() {
    super.init(acrValues: ["urn:age-verification"])
  }
  override internal func getThis() -> AgeVerification { self }

  public static func over(_ age: AgeVerificationAge) -> AgeVerification {
    AgeVerification().over(age)
  }

  public func over(_ age: AgeVerificationAge) -> AgeVerification {
    withScope("is_over_\(age.rawValue)")
  }

  public func withCountry(_ country: AgeVerificationCountry) -> AgeVerification {
    withLoginHint("country:\(country.rawValue)")
  }
}
