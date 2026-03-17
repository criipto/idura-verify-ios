import IduraVerify
import SwiftUI

struct AuthenticatedView: View {
  @Binding var loginState: LoginState
  var iduraVerify: IduraVerify

  var body: some View {
    if case .loggedIn(_, var jwt) = loginState {
      VStack {
        Text("Successfully logged in!").font(.largeTitle)
          .padding()
        Text("Sub").font(.title)
        Text(jwt.subject)
          .padding(.bottom)
        Text("eID provider").font(.title)
        Text(jwt.identityscheme).padding(.bottom)
        Text("Name").font(.title)
        Text(jwt.getClaimValue(key: "name") as? String ?? "").padding(.bottom)
        Spacer()
        Button(action: logout) { Text("Log out") }
      }.padding()
    }
  }

  func logout() {
    guard case .loggedIn(let idToken, var jwt) = loginState
    else {
      return
    }

    Task {
      loginState = .loading
      do {
        try await iduraVerify.logout(idTokenHint: idToken)
      } catch {
        loginState = .notLoggedIn(
          errorMessage: error.localizedDescription,
          previouslyLoggedInAs: jwt.getClaimValue(key: "uuid") as? String,
        )
      }
      loginState = .notLoggedIn(
        errorMessage: nil, previouslyLoggedInAs: jwt.getClaimValue(key: "uuid") as? String)
    }
  }
}
