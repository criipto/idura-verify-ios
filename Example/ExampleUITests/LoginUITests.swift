import XCTest

/// Happy-path logins. `testMockLogin` runs headless on the Simulator (and in CI); the eID
/// tests are local-only against a real device with the enrolled test apps installed, and read
/// their credentials from `TEST_RUNNER_*` environment variables (see `requireCredential`).
final class LoginUITests: IduraUITestCase {
  /// The single test CI runs on every push. The mock IdP auto-completes the OAuth flow from
  /// the inline `mock:<base64>` login hint, so the `ASWebAuthenticationSession` opens and
  /// closes with no browser-side interaction — fully headless on the Simulator.
  func testMockLogin() {
    app.launch()
    app.buttons["login-mock"].tap()
    XCTAssertTrue(
      app.staticTexts["login-success"].waitForExistence(timeout: 90),
      "Expected a successful mock login")
  }

  /// Local-only: drives the real MitID test app. Enters the user id on the hosted page,
  /// app-switches into MitID, enters the PIN, swipes to approve, and asserts the redirect back.
  func testMitID() throws {
    try requireRealDevice()
    let userID = try requireCredential("MITID_USER_ID")
    let pin = try requireCredential("MITID_PIN")
    app.launch()

    let mitID = driveMitIDToApp(userID: userID)

    // The PIN pad exposes each digit as a `Key` (identifier == the digit).
    XCTAssertTrue(mitID.keys["1"].waitForExistence(timeout: 15), "MitID PIN pad did not appear")
    for digit in pin {
      mitID.keys[String(digit)].tap()
    }

    // The PIN is followed by a swipe-to-approve control: drag its full width, left to right.
    let approve = mitID.buttons.matching(NSPredicate(format: "label == %@", "Approve")).firstMatch
    XCTAssertTrue(approve.waitForExistence(timeout: 15), "MitID Approve control not found")
    approve.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
      .press(
        forDuration: 0.2,
        thenDragTo: approve.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)))

    XCTAssertTrue(app.staticTexts["login-success"].waitForExistence(timeout: 60))
    XCTAssertEqual(app.staticTexts["identity-scheme"].label, "dkmitid")
  }

  /// Local-only: drives the real Vipps test app. Enters its passcode, then double-taps the login
  /// confirmation. Requires Touch ID disabled in the Vipps test app so it prompts for the code.
  func testVipps() throws {
    try requireRealDevice()
    let code = try requireCredential("VIPPS_PIN")
    // Start from a clean Vipps session so it consistently prompts for the passcode.
    EIDApp.handle(EIDApp.vipps).terminate()
    app.launch()
    app.buttons["login-vipps"].tap()

    XCTAssertTrue(Browser.tapWebButton("Open Vipps", timeout: 35), "Vipps 'Open' link not found")

    let vipps = EIDApp.handle(EIDApp.vipps)
    XCTAssertTrue(vipps.wait(for: .runningForeground, timeout: 30), "Vipps app did not open")

    XCTAssertTrue(vipps.keys["1"].waitForExistence(timeout: 15), "Vipps PIN pad did not appear")
    for digit in code {
      vipps.keys[String(digit)].tap()
      // Vipps drops keypad taps that arrive too quickly; pace them so each digit registers.
      Thread.sleep(forTimeInterval: 0.3)
    }

    // Vipps's "Do you want to log in to Criipto?" confirmation requires a double-tap; the button
    // is label-only, so match on label rather than the identifier subscript.
    let confirm = vipps.buttons.matching(
      NSPredicate(format: "label == %@", "Double tap to confirm log in")
    ).firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 10), "Vipps confirm button not found")
    confirm.doubleTap()

    XCTAssertTrue(app.staticTexts["login-success"].waitForExistence(timeout: 60))
    XCTAssertEqual(app.staticTexts["identity-scheme"].label, "novippslogin")
  }

  /// Local-only: drives the real SE BankID test app, same-device flow, entering the test user's
  /// security code on BankID's PIN keypad.
  func testSEBankID() throws {
    try requireRealDevice()
    let code = try requireCredential("SEBANKID_CODE")
    app.launch()
    app.buttons["login-se-bankid"].tap()
    XCTAssertTrue(Browser.tapWebButton("Open", timeout: 35), "SE BankID 'Open' link not found")

    let bankID = EIDApp.handle(EIDApp.seBankID)
    XCTAssertTrue(bankID.wait(for: .runningForeground, timeout: 30), "BankID app did not open")
    addTeardownBlock { bankID.terminate() }

    bankID.buttons["Identify with security code"].firstMatch.tap()
    for digit in code {
      bankID.keys[String(digit)].tap()
    }
    bankID.buttons["Identify"].firstMatch.tap()

    XCTAssertTrue(app.staticTexts["login-success"].waitForExistence(timeout: 60))
    XCTAssertEqual(app.staticTexts["identity-scheme"].label, "sebankid")
  }

  /// Local-only: Norwegian BankID (password-based on this test setup). Enters the national ID on
  /// the hosted page; the BankID app is then launched via a push notification rather than an
  /// in-page app-switch, so the test switches to the app manually, approves, and — since there
  /// is no app-switch back — returns to the example app manually to enter the BankID password.
  func testNorwegianBankID() throws {
    try requireRealDevice()
    let idNumber = try requireCredential("NOBANKID_ID")
    let password = try requireCredential("NOBANKID_PASSWORD")

    let bankID = EIDApp.handle(EIDApp.noBankId)
    bankID.terminate()

    app.launch()
    app.buttons["login-no-bankid"].tap()

    let idField = Browser.app.textFields.firstMatch
    XCTAssertTrue(idField.waitForExistence(timeout: 15), "NO BankID ID field not found")
    idField.tap()
    idField.typeText(idNumber)
    // The keyboard obscures the page's Continue button; dismiss it via the accessory "Done".
    let doneKey = Browser.app.buttons.matching(
      NSPredicate(format: "label == %@", "Done")
    ).firstMatch
    if doneKey.waitForExistence(timeout: 3) { doneKey.tap() }
    Thread.sleep(forTimeInterval: 1)

    XCTAssertTrue(Browser.tapWebButton("Continue", timeout: 15), "NO BankID 'Continue' not found")
    // Once the request is sent (and the push fired) the page shows "Confirm in app".
    let confirmInApp = Browser.app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS[c] %@", "Confirm in app")
    ).firstMatch
    XCTAssertTrue(confirmInApp.waitForExistence(timeout: 30), "NO BankID did not send the request")

    bankID.activate()
    let approve = bankID.buttons["approveAuthButton"]  // "Yes, it's me"
    XCTAssertTrue(approve.waitForExistence(timeout: 20), "BankID approval button not found")
    approve.tap()

    // After approval, BankID hands control back to the auth session (no auto app-switch), which
    // then asks for the BankID password. Submit with the keyboard return key — the page's "Next"
    // button sits under the keyboard and iOS's "Use Strong Password?" AutoFill sheet.
    app.activate()
    let passwordField = Browser.app.secureTextFields.firstMatch
    XCTAssertTrue(passwordField.waitForExistence(timeout: 25), "BankID password field not found")
    passwordField.tap()
    passwordField.typeText(password + "\n")

    XCTAssertTrue(app.staticTexts["login-success"].waitForExistence(timeout: 60))
    XCTAssertEqual(app.staticTexts["identity-scheme"].label, "nobankid-oidc")
  }
}
