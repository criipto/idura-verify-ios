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
        Button(
          // swiftlint:disable:next force_try
          action: { login(eid: try! Mock().withMockData(MockData(name: "Foobar"))) },
          label: {
            Text("Login with Mock")
          },
        ).padding()
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
        Button(
          action: { login(eid: SwedishBankID.sameDevice().withMessage("Hello!")) },
          label: {
            Text("Login with SE BankID")
          },
        ).padding()
        Button(
          action: { login(eid: NorwegianBankID.high().withSsn()) },
          label: {
            Text("Login with NO BankID")
          },
        ).padding()
        Button(
          action: { login(eid: Vipps()) },
          label: {
            Text("Login with Vipps")
          },
        ).padding()
        Button(
          action: {
            login(
              eid: FrejaID.extended().withAllEmails().withDefaultAndFaceConfirmation())
          },
          label: {
            Text("Login with FrejaID")
          },
        ).padding()
      }.padding()
    }
  }

  func login<T>(eid: EID<T>) {
    Task {
      do {
        loginState = .loading
        let (idToken, jwt) = try await iduraVerify.login(eid: eid)
        loginState = .loggedIn(idToken: idToken, jwt: jwt)
      } catch {
        loginState = .notLoggedIn(
          errorMessage: "Error during login \(error.localizedDescription)",
          previouslyLoggedInAs: nil,
        )
      }
    }
  }
}
