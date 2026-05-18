/// The result of a successful `IduraVerify.login()` call.
///
/// The verified ID token JWT is on `jwt`; the raw, encoded ID token is available on
/// `jwt.idToken` if you need it.
public struct LoginResult {
  public let jwt: JWT
}
