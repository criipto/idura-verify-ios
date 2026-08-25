import Foundation
import IduraVerify
import SwiftUI

struct MainView: View {
  @State var loginState = LoginState.notLoggedIn(errorMessage: nil, previouslyLoggedInAs: nil)
  // `try!`: a malformed IDURA_DOMAIN is a misconfigured build, so failing fast is what we want.
  // swiftlint:disable:next force_try
  @StateObject var iduraVerify = try! IduraVerify(
    // swiftlint:disable:next force_cast
    clientId: Bundle.main.object(forInfoDictionaryKey: "IDURA_CLIENT_ID") as! String,
    // swiftlint:disable:next force_cast
    domain: Bundle.main.object(forInfoDictionaryKey: "IDURA_DOMAIN") as! String,
  )

  var body: some View {
    VStack {
      switch loginState {
      case .loggedIn:
        AuthenticatedView(loginState: $loginState, iduraVerify: iduraVerify)
      case .notLoggedIn:
        UnAuthenticatedView(loginState: $loginState, iduraVerify: iduraVerify)
      case .loading:
        LoadingView()
      }
    }
  }
}
