import Foundation

public enum Action: String, Sendable {
  case login
  case confirm
  case accept
  case approve
  case sign
}

private func base64Encode(_ str: String) -> String {
  Data(str.utf8).base64EncodedString()
}

private let appswitchAcrPrefixes = [
  "urn:grn:authn:dk:mitid",
  "urn:grn:authn:se:frejaid",
  "urn:grn:authn:se:bankid",
]

public protocol EID: Sendable {
  var acrValues: [String] { get }
  var scopes: [String] { get set }
  var loginHints: [String] { get set }
  var action: Action? { get set }
}

extension EID {
  public var acrValue: String { acrValues.joined(separator: ":") }

  /// Whether this eID's login supports app-switch redirection back to the consumer app.
  /// When true, the SDK injects an `appswitch:resumeUrl:` login hint so the eID app can
  /// universal-link back into the consumer when it finishes.
  ///
  /// Derived from the `acrValue` prefix so that `Other("urn:grn:authn:dk:mitid:substantial")`
  /// and the same value arrived at via `DanishMitID.substantial()` behave identically.
  internal var supportsAppSwitch: Bool {
    appswitchAcrPrefixes.contains { acrValue.hasPrefix($0) }
  }

  public func withScope(_ scope: String) -> Self {
    var copy = self
    copy.scopes.append(scope)
    return copy
  }

  public func withLoginHint(_ loginHint: String) -> Self {
    var copy = self
    copy.loginHints.append(loginHint)
    return copy
  }
}

/// eIDs that allow attaching a user-visible message (typically shown during signing).
public protocol SupportsMessage: EID {}

extension SupportsMessage {
  public func withMessage(_ message: String) -> Self {
    withLoginHint("message:\(base64Encode(message))")
  }
}

/// eIDs that allow setting a non-default action (e.g. `.sign`, `.approve`).
public protocol SupportsAction: EID {}

extension SupportsAction {
  public func withAction(_ action: Action) -> Self {
    var copy = self
    copy.action = action
    return copy
  }
}

public struct DanishMitID: SupportsMessage, SupportsAction {
  public let acrValues: [String]
  public var scopes: [String] = []
  public var loginHints: [String] = []
  public var action: Action?

  private init(modifier: String) {
    self.acrValues = ["urn:grn:authn:dk:mitid", modifier]
  }

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
}

public struct NorwegianBankID: EID {
  public let acrValues: [String]
  public var scopes: [String] = []
  public var loginHints: [String] = []
  public var action: Action?

  private init(modifier: String) {
    self.acrValues = ["urn:grn:authn:no:bankid", modifier]
  }

  public static func substantial() -> NorwegianBankID { NorwegianBankID(modifier: "substantial") }
  public static func high() -> NorwegianBankID { NorwegianBankID(modifier: "high") }

  public func withSsn() -> NorwegianBankID { withScope("ssn") }
}

public struct SwedishBankID: SupportsMessage {
  public let acrValues: [String]
  public var scopes: [String] = []
  public var loginHints: [String] = []
  public var action: Action?

  private init(modifier: String?) {
    self.acrValues = ["urn:grn:authn:se:bankid", modifier].compactMap { $0 }
  }

  public static func otherDevice() -> SwedishBankID { SwedishBankID(modifier: "another-device:qr") }
  public static func sameDevice() -> SwedishBankID { SwedishBankID(modifier: "same-device") }
  public static func selectorPage() -> SwedishBankID { SwedishBankID(modifier: nil) }

  public func withSsn() -> SwedishBankID { withScope("ssn") }

  public func sign(message: String) -> SwedishBankID {
    var result = withMessage(message)
    result.action = .sign
    return result
  }
}

public struct Vipps: EID {
  public let acrValues: [String] = ["urn:grn:authn:no:vipps"]
  public var scopes: [String] = []
  public var loginHints: [String] = []
  public var action: Action?

  public init() {}

  public func withEmail() -> Vipps { withScope("email") }
  public func withPhone() -> Vipps { withScope("phone") }
  public func withAddress() -> Vipps { withScope("address") }
  public func withBirthdate() -> Vipps { withScope("birthdate") }
  public func withSsn() -> Vipps { withScope("ssn") }
}

public protocol FrejaIDType: EID {}

extension FrejaIDType {
  public func withEmail() -> Self { withScope("frejaid:email_address") }
  public func withAllEmails() -> Self { withScope("frejaid:all_email_addresses") }
  public func withPhoneNumbers() -> Self { withScope("frejaid:all_phone_numbers") }
  public func withRegistrationLevel() -> Self { withScope("frejaid:registration_level") }
  public func sign(message: String, title: String?) -> Self {
    var result = self
    result.action = .sign
    if let title {
      result = result.withLoginHint("title:\(base64Encode(title))")
    }
    return result.withLoginHint("message:\(base64Encode(message))")
  }
}

public enum FrejaID {
  public static func basic() -> FrejaIDBasic { FrejaIDBasic() }
  public static func extended() -> FrejaIDExtendedOrPlus {
    FrejaIDExtendedOrPlus(minRegistrationLevel: "extended")
  }
  public static func plus() -> FrejaIDExtendedOrPlus {
    FrejaIDExtendedOrPlus(minRegistrationLevel: "plus")
  }
}

public struct FrejaIDBasic: FrejaIDType {
  public let acrValues: [String] = ["urn:grn:authn:se:frejaid"]
  public var scopes: [String] = []
  public var loginHints: [String]
  public var action: Action?

  fileprivate init() {
    self.loginHints = ["minregistrationlevel:basic"]
  }
}

public struct FrejaIDExtendedOrPlus: FrejaIDType {
  public let acrValues: [String] = ["urn:grn:authn:se:frejaid"]
  public var scopes: [String] = []
  public var loginHints: [String]
  public var action: Action?

  fileprivate init(minRegistrationLevel: String) {
    self.loginHints = ["minregistrationlevel:\(minRegistrationLevel)"]
  }

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

public struct Mock: EID {
  public let acrValues: [String] = ["urn:grn:authn:mock"]
  public var scopes: [String] = []
  public var loginHints: [String] = []
  public var action: Action?

  public init() {}

  /// Provide an object of mock data, which will be inserted into the returned JWT.
  /// The data must conform to the https://developer.apple.com/documentation/swift/encodable protocol
  public func withMockData(_ data: Encodable) throws -> Mock {
    withMockData(String(data: try JSONEncoder().encode(data), encoding: .utf8)!)
  }

  /// Provide a JSON stringified object of mock data, which will be inserted into the returned JWT
  public func withMockData(_ data: String) -> Mock { withLoginHint("mock:\(base64Encode(data))") }
}

public struct Other: EID {
  public let acrValues: [String]
  public var scopes: [String] = []
  public var loginHints: [String] = []
  public var action: Action?

  public init(acrValue: String) {
    self.acrValues = [acrValue]
  }
}

public enum AgeVerificationCountry: String, Sendable {
  case denmark = "DK"
  case sweden = "SE"
  case norway = "NO"
  case finland = "FI"
}

public enum AgeVerificationAge: Int, Sendable {
  case over15 = 15
  case over16 = 16
  case over18 = 18
  case over21 = 21
}

public struct AgeVerification: EID {
  public let acrValues: [String] = ["urn:age-verification"]
  public var scopes: [String] = []
  public var loginHints: [String] = []
  public var action: Action?

  private init() {}

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
