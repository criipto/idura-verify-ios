import XCTest

/// Base class for the Idura Verify UI tests.
///
/// On top of `XCTestCase` it adds:
///
/// - **Failure diagnostics.** On a failing test it attaches the element hierarchies of the
///   app, the browser and SpringBoard to the test report, so a CI failure is diagnosable
///   from the `.xcresult` artifact without a local repro. (Xcode already captures a
///   screenshot on every failure on its own.) This is the iOS analog of the Android suite's
///   `CaptureOnFailure` rule.
/// - **`requireRealDevice()`** to skip flows that drive a real eID app. Those apps are App
///   Store builds that can't be installed on the Simulator — the same reason the Android
///   suite kept its MitID/BankID/Vipps tests off the CI emulator.
///
/// There is no `RetryRule` analog: flaky app-switch tests are re-run via
/// `xcodebuild test -retry-tests-on-failure -test-iterations N` instead.
class IduraUITestCase: XCTestCase {
  let app = XCUIApplication()

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  override func tearDownWithError() throws {
    guard let testRun, testRun.failureCount > 0 else { return }
    attachHierarchy(app, name: "app-hierarchy")
    attachHierarchy(Browser.app, name: "browser-hierarchy")
    attachHierarchy(Springboard.app, name: "springboard-hierarchy")
  }

  private func attachHierarchy(_ application: XCUIApplication, name: String) {
    let attachment = XCTAttachment(string: application.debugDescription)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// Skips flows that need a real eID app (MitID, BankID, Vipps); they can't be installed on
  /// the Simulator. Call at the top of such a test.
  func requireRealDevice() throws {
    #if targetEnvironment(simulator)
      throw XCTSkip("Requires a real device with the eID test app installed.")
    #endif
  }

  /// Drives MitID from the example through the hosted ID page into the MitID app, returning the
  /// app handle on its PIN screen. Shared by the happy-path login and the in-app-cancel test.
  /// Assumes the example app has already been launched.
  func driveMitIDToApp(userID: String) -> XCUIApplication {
    app.buttons["login-mitid"].tap()

    // MitID hosted page: type the user id, then CONTINUE (disabled until the field is filled).
    let userIDField = Browser.app.textFields["User ID"]
    XCTAssertTrue(userIDField.waitForExistence(timeout: 20), "MitID User ID field not found")
    userIDField.tap()
    userIDField.typeText(userID)
    Browser.app.buttons["CONTINUE"].tap()

    // The next page ("Open MitID app and approve") deep-links into the app via this link.
    XCTAssertTrue(
      Browser.tapWebButton("OPEN MITID APP", timeout: 35), "MitID 'OPEN MITID APP' link not found")

    let mitID = EIDApp.handle(EIDApp.mitID)
    XCTAssertTrue(mitID.wait(for: .runningForeground, timeout: 30), "MitID app did not open")
    return mitID
  }
}

/// Handles to the cross-process UIs the login flow touches: the browser that hosts the
/// `ASWebAuthenticationSession`, SpringBoard, and (via `EIDApp`) the eID apps.
///
/// The auth session's web content *is* reachable from XCUITest — fields, buttons and links on
/// the rendered pages are queryable (match web elements by `label`, since their `identifier` is
/// usually empty). The main gotcha is the on-screen keyboard, which obscures buttons lower on
/// the page; dismiss it (the accessory "Done", or submit with a `\n`) before tapping them.
enum Browser {
  /// The process that hosts the `ASWebAuthenticationSession` UI (the Safari view, its
  /// nav-bar Cancel button, and the rendered web page).
  static let app = XCUIApplication(bundleIdentifier: "com.apple.SafariViewService")

  /// Dismisses the auth session via its system "Cancel" button. The SDK maps this to
  /// `IduraVerifyError.userCancelled`, which the example renders as "User cancelled".
  static func close(timeout: TimeInterval = 15) {
    let cancel = app.buttons["Cancel"].firstMatch
    XCTAssertTrue(cancel.waitForExistence(timeout: timeout), "Auth session Cancel button not found")
    cancel.tap()
  }

  /// Taps a button/link rendered on the auth-session web page, found by its visible text.
  /// Web elements expose their text as `label` (not `identifier`), so we match on label rather
  /// than the identifier-based subscript, polling across the element types the page might use.
  @discardableResult
  static func tapWebButton(_ label: String, timeout: TimeInterval = 20) -> Bool {
    let predicate = NSPredicate(format: "label == %@ OR identifier == %@", label, label)
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      for query in [app.buttons, app.links, app.staticTexts] {
        let element = query.matching(predicate).firstMatch
        if element.exists {
          element.tap()
          return true
        }
      }
      Thread.sleep(forTimeInterval: 0.5)
    } while Date() < deadline
    return false
  }
}

enum Springboard {
  static let app = XCUIApplication(bundleIdentifier: "com.apple.springboard")
}

enum EIDApp {
  static let mitID = "eu.nets.mitid.ios.staging"
  static let seBankID = "com.bankidapp.BankID"
  static let noBankId = "no.bankid.preprod.BankID"
  static let vipps = "no.vipps.internal.mt.vipps"

  static func handle(_ bundleId: String) -> XCUIApplication {
    XCUIApplication(bundleIdentifier: bundleId)
  }
}

/// Reads a test credential from the environment, failing the test if it's absent. Pass these
/// at run time so they stay out of the repo — xcodebuild forwards `TEST_RUNNER_<NAME>` to the
/// test runner as `<NAME>`, e.g. `TEST_RUNNER_MITID_USER_ID=… xcodebuild test …`.
func requireCredential(_ name: String) throws -> String {
  guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
    throw MissingCredentialError(name: name)
  }
  return value
}

/// Thrown when a required `TEST_RUNNER_*` credential is unset. Unlike `XCTSkip`, throwing this
/// fails the test — a credentialed eID test that can't see its secret is a misconfigured run,
/// not one to pass over silently. The message names the variable to set.
private struct MissingCredentialError: LocalizedError {
  let name: String
  var errorDescription: String? {
    "Missing credential: set TEST_RUNNER_\(name) to run this test."
  }
}
