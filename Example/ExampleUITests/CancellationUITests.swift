import XCTest

/// Aborting a login — closing the auth session, the in-page cancel control, or cancelling
/// inside the app-switch app — all surface as `IduraVerifyError.userCancelled`, which the
/// example renders as "User cancelled". Each test triggers one of those and asserts the
/// message comes back.
///
/// The "close the browser" tests only need the network and a configured domain, so they run
/// on the Simulator. The "in app" tests drive a real eID app and are device-only.
final class CancellationUITests: IduraUITestCase {
  /// Waits for the example to surface "User cancelled" in its error label.
  private func assertUserCancelled(timeout: TimeInterval = 60) {
    let error = app.staticTexts["login-error"]
    let predicate = NSPredicate(format: "label == %@", "User cancelled")
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: error)
    XCTAssertEqual(
      XCTWaiter().wait(for: [expectation], timeout: timeout), .completed,
      "Expected the app to show \"User cancelled\"")
  }

  /// Starts a login, waits for the auth session to come up, dismisses it with the system
  /// Cancel button, and asserts the cancellation propagates. Works for any eID since it never
  /// reaches the eID app.
  private func assertCancelByClosingBrowser(loginButton: String) {
    app.launch()
    app.buttons[loginButton].tap()
    Browser.close()
    assertUserCancelled()
  }

  func testDanishMitIDCancelByClosingBrowser() {
    assertCancelByClosingBrowser(loginButton: "login-mitid")
  }

  func testNorwegianBankIDCancelByClosingBrowser() {
    assertCancelByClosingBrowser(loginButton: "login-no-bankid")
  }

  func testVippsCancelByClosingBrowser() {
    assertCancelByClosingBrowser(loginButton: "login-vipps")
  }

  func testSwedishBankIDCancelByClosingBrowser() {
    assertCancelByClosingBrowser(loginButton: "login-se-bankid")
  }

  /// Cancels via the Cancel control rendered *on the Idura web page* (not the session chrome).
  /// Best-effort: depends on the auth-session web content being exposed to XCUITest — see the
  /// note on `Browser`. Confirm on-device before relying on it.
  func testDanishMitIDCancelInUi() {
    app.launch()
    app.buttons["login-mitid"].tap()
    XCTAssertTrue(Browser.tapWebButton("Cancel"), "In-page Cancel control not reachable")
    assertUserCancelled()
  }

  /// Local-only: aborts MitID from inside the app via its Close (X) button, before the PIN.
  func testDanishMitIDCancelInApp() throws {
    try requireRealDevice()
    let userID = try requireCredential("MITID_USER_ID")
    app.launch()

    let mitID = driveMitIDToApp(userID: userID)
    let close = mitID.buttons.matching(NSPredicate(format: "label == %@", "Close")).firstMatch
    XCTAssertTrue(close.waitForExistence(timeout: 15), "MitID Close button not found")
    close.tap()
    // Close opens a reject dialog; confirm it with "Yes".
    let confirmReject = mitID.buttons.matching(NSPredicate(format: "label == %@", "Yes")).firstMatch
    XCTAssertTrue(
      confirmReject.waitForExistence(timeout: 10), "MitID reject-dialog 'Yes' not found")
    confirmReject.tap()

    assertUserCancelled()
  }

  /// Local-only: aborts SE BankID from inside the app via its nav-bar Cancel button.
  func testSwedishBankIDCancelInApp() throws {
    try requireRealDevice()
    app.launch()
    app.buttons["login-se-bankid"].tap()
    XCTAssertTrue(Browser.tapWebButton("Open", timeout: 35), "SE BankID 'Open' link not found")

    let bankID = EIDApp.handle(EIDApp.seBankID)
    XCTAssertTrue(bankID.wait(for: .runningForeground, timeout: 30), "BankID app did not open")
    let cancel = bankID.buttons.matching(NSPredicate(format: "label == %@", "Cancel")).firstMatch
    XCTAssertTrue(cancel.waitForExistence(timeout: 15), "BankID Cancel button not found")
    cancel.tap()

    assertUserCancelled()
  }

  /// Local-only: app-switches into Vipps, enters its passcode, then closes the login
  /// confirmation to cancel.
  func testVippsCancelInApp() throws {
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

    // Dismiss the "Do you want to log in to Criipto?" confirmation via its Close (X) control,
    // then confirm the "Yes, cancel" prompt.
    let close = vipps.buttons["xmark"].firstMatch
    XCTAssertTrue(close.waitForExistence(timeout: 15), "Vipps confirmation Close not found")
    close.tap()
    let confirmCancel = vipps.buttons.matching(
      NSPredicate(format: "label == %@", "Yes, cancel")
    ).firstMatch
    XCTAssertTrue(confirmCancel.waitForExistence(timeout: 10), "Vipps 'Yes, cancel' not found")
    confirmCancel.tap()

    assertUserCancelled()
  }
}
