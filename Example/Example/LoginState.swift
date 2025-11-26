import IduraVerify

enum LoginState {
  case loggedIn(idToken: String, claims: IDTokenClaims)
  case notLoggedIn(errorMessage: String?, previouslyLoggedInAs: String?)
  case loading
}
