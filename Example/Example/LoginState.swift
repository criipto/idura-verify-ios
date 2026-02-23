import IduraVerify

enum LoginState {
  case loggedIn(idToken: String, jwt: JWT)
  case notLoggedIn(errorMessage: String?, previouslyLoggedInAs: String?)
  case loading
}
