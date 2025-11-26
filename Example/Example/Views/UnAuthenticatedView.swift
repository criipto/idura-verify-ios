import IduraVerify
import SwiftUI

extension View {
  func getViewController() -> UIViewController {
    // swiftlint:disable:next force_cast
    let scene = UIApplication.shared.connectedScenes.first as! UIWindowScene
    return scene.keyWindow!.rootViewController!
  }
}

struct UnAuthenticatedView: View {
  @Binding var loginState: LoginState
  var iduraVerify: IduraVerify

  var body: some View {
    if case .notLoggedIn(let errorMessage, _) = loginState {
      VStack {
        Image(systemName: "lock")
          .imageScale(.large)
          .foregroundStyle(.tint)
        Text(errorMessage ?? "")
          .font(.title)
        Button(
          action: { login(eid: .mock) },
          label: {
            Text("Login with Mock")
          },
        ).padding()
        Button(
          action: { login(eid: .mitID) },
          label: {
            Text("Login with MitID")
          },
        ).padding()
        Button(
          action: { login(eid: .seBankID) },
          label: {
            Text("Login with SE BankID")
          },
        ).padding()
        Button(
          action: { login(eid: .noBankID) },
          label: {
            Text("Login with NO BankID")
          },
        ).padding()
      }.padding()
        .onAppear(perform: onAppear)
    }
  }

  func onAppear() {
    Task {
      do {
        try await iduraVerify.prepare()
      } catch {
        loginState = .notLoggedIn(
          errorMessage: "Error while preparing login manager: \(error.localizedDescription)",
          previouslyLoggedInAs: nil,
        )
      }
    }
  }

  func login(eid: EID) {
    guard
      case .notLoggedIn(
        _, let previouslyLoggedInAs,
      ) = loginState
    else {
      return
    }

    Task {
      do {
        loginState = .loading
        let (idToken, claims) = try await iduraVerify.login(
          presenting: getViewController(),
          eid: eid,
          previouslyLoggedInAs: previouslyLoggedInAs,
        )
        loginState = .loggedIn(idToken: idToken, claims: claims)
      } catch {
        loginState = .notLoggedIn(
          errorMessage: "Error during login \(error.localizedDescription)",
          previouslyLoggedInAs: nil,
        )
      }
    }
  }
}
