import IduraVerify
import SwiftUI

extension View {
  func getViewController() -> UIViewController {
    // swiftlint:disable:next force_cast
    let scene = UIApplication.shared.connectedScenes.first as! UIWindowScene
    return scene.keyWindow!.rootViewController!
  }
}

struct MockData: Codable {
  var name: String
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
          // swiftlint:disable:next force_try
          action: { login(eid: try! Mock().withMockData(MockData(name: "Foobar"))) },
          label: {
            Text("Login with Mock")
          },
        ).padding()
        Button(
          action: {
            login(
              eid: DanishMitID.substantial().withAction(.sign).withMessage(
                "hello there!"))
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

  func login<T>(eid: EID<T>) {
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
