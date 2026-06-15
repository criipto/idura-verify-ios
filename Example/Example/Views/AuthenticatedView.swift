import IduraVerify
import SwiftUI

struct AuthenticatedView: View {
  @Binding var loginState: LoginState
  var iduraVerify: IduraVerify

  var body: some View {
    if case .loggedIn(_, let jwt) = loginState {
      VStack {
        Text("Successfully logged in!").font(.largeTitle)
          .padding().accessibilityIdentifier("login-success")
        Text("Sub").font(.title)
        Text(jwt.subject)
          .padding(.bottom)
        Text("eID provider").font(.title)
        Text(jwt.identityscheme).padding(.bottom).accessibilityIdentifier("identity-scheme")
        Text("Name").font(.title)
        Text(jwt.getClaimValue(key: "name") as? String ?? "").padding(.bottom)
        Spacer()
        Button(action: logout) { Text("Log out") }
      }.padding()
    }
  }

  func logout() {
    guard case .loggedIn(_, let jwt) = loginState
    else {
      return
    }

    Task {
      loginState = .notLoggedIn(
        errorMessage: nil, previouslyLoggedInAs: jwt.getClaimValue(key: "uuid") as? String)
    }
  }
}
