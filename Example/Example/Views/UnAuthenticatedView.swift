import IduraVerify
import SwiftUI

struct MockData: Codable {
  var name: String
}

struct UnAuthenticatedView: View {
  @Binding var loginState: LoginState
  var iduraVerify: IduraVerify

  var body: some View {
    if case .notLoggedIn(let errorMessage, let previouslyLoggedInAs) = loginState {
      VStack {
        Image(systemName: "lock")
          .imageScale(.large)
          .foregroundStyle(.tint)
        Text(errorMessage ?? "")
          .font(.title)
          .accessibilityIdentifier("login-error")
        Button(
          // swiftlint:disable:next force_try
          action: { login(eid: try! Mock().withMockData(MockData(name: "Foobar"))) },
          label: {
            Text("Login with Mock")
          },
        ).padding()
          .accessibilityIdentifier("login-mock")
        Button(
          action: {
            var mitID = DanishMitID.substantial().withMessage("hello there!")

            if let previouslyLoggedInAs {
              mitID = mitID.prefillUUID(previouslyLoggedInAs)
            }
            login(eid: mitID)
          },
          label: {
            Text("Login with MitID")
          },
        ).padding()
          .accessibilityIdentifier("login-mitid")
        Button(
          action: { login(eid: SwedishBankID.sameDevice().withMessage("Hello!")) },
          label: {
            Text("Login with SE BankID")
          },
        ).padding()
          .accessibilityIdentifier("login-se-bankid")
        Button(
          action: { login(eid: NorwegianBankID.high().withSsn()) },
          label: {
            Text("Login with NO BankID")
          },
        ).padding()
          .accessibilityIdentifier("login-no-bankid")
        Button(
          action: { login(eid: Vipps()) },
          label: {
            Text("Login with Vipps")
          },
        ).padding()
          .accessibilityIdentifier("login-vipps")
        Button(
          action: {
            login(
              eid: FrejaID.extended().withAllEmails().withDefaultAndFaceConfirmation())
          },
          label: {
            Text("Login with FrejaID")
          },
        ).padding()
          .accessibilityIdentifier("login-frejaid")
        Button(
          action: {
            login(
              eid: AgeVerification.over(.over15).over(.over18).withCountry(.denmark))
          },
          label: {
            Text("Age verification (over 15 and 18)")
          },
        ).padding()
          .accessibilityIdentifier("login-age")
      }.padding()
    }
  }

  func login(eid: some EID) {
    Task {
      do {
        loginState = .loading
        let result = try await iduraVerify.login(eid: eid)
        loginState = .loggedIn(idToken: result.jwt.idToken, jwt: result.jwt)
        print("Completed login with trace ID \(result.traceId)")
      } catch IduraVerifyError.userCancelled {
        loginState = .notLoggedIn(
          errorMessage: "User cancelled",
          previouslyLoggedInAs: nil,
        )
      } catch IduraVerifyError.associatedDomainsNotConfigured(let traceId) {
        loginState = .notLoggedIn(
          errorMessage:
            "Associated Domains entitlement missing for the redirect URI host (trace \(traceId))",
          previouslyLoggedInAs: nil,
        )
      } catch IduraVerifyError.oauth(let error, let errorDescription, let traceId) {
        loginState = .notLoggedIn(
          errorMessage:
            "Error during login \(error), \(errorDescription ?? "No description") (trace \(traceId))",
          previouslyLoggedInAs: nil,
        )
      } catch let err as IduraVerifyError {
        loginState = .notLoggedIn(
          errorMessage: "Error during login \(err.localizedDescription) (trace \(err.traceId))",
          previouslyLoggedInAs: nil,
        )
      }
    }
  }
}
