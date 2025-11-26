import Foundation
import IduraVerify
import SwiftUI

struct MainView: View {
  @State var loginState = LoginState.notLoggedIn(errorMessage: nil, previouslyLoggedInAs: nil)
  var iduraVerify: IduraVerify

  init() {
    iduraVerify = IduraVerify(
      // swiftlint:disable:next force_cast
      clientId: (Bundle.main.object(forInfoDictionaryKey: "IDURA_CLIENT_ID") as! String),
      // swiftlint:disable:next force_cast
      domain: "https://" + (Bundle.main.object(forInfoDictionaryKey: "IDURA_DOMAIN") as! String),
    )
  }

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
