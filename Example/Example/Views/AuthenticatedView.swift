import IduraVerify
import SwiftUI

struct AuthenticatedView: View {
  @Binding var loginState: LoginState
  var iduraVerify: IduraVerify

  var body: some View {
    if case .loggedIn(_, let claims) = loginState {
      VStack {
        Text("Successfully logged in!").font(.largeTitle)
          .padding()
        Text("Sub").font(.title)
        Text(claims.sub)
          .padding(.bottom)
        Text("eID provider").font(.title)
        Text(claims.identityscheme).padding(.bottom)
        Text("Name").font(.title)
        Text(claims.name ?? "").padding(.bottom)
        Spacer()
        Button(action: logout) { Text("Log out") }
      }.padding()
    }
  }

  func logout() {
    guard case .loggedIn(let idToken, let claims) = loginState
    else {
      return
    }

    Task {
      loginState = .loading
      do {
        try await iduraVerify.logout(
          presenting: getViewController(),
          idTokenHint: idToken,
        )
      } catch {
        loginState = .notLoggedIn(
          errorMessage: error.localizedDescription,
          previouslyLoggedInAs: claims.uuid,
        )
      }
      loginState = .notLoggedIn(errorMessage: nil, previouslyLoggedInAs: claims.uuid)
    }
  }
}
