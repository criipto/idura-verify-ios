/// The result of a successful `IduraVerify.login()` call.
///
/// The verified ID token JWT is on `jwt`; the raw, encoded ID token is available on
/// `jwt.idToken` if you need it. `traceId` is the Idura trace id. You can view traces in the
// Idura dashboard.
public struct LoginResult {
  public let jwt: JWT
  public let traceId: String
}
