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
