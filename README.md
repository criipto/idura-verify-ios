# idura-verify-ios

The Idura Verify iOS SDK allows your users to authenticate with a host of European eID providers. It allows your application to act as a [_public client_](https://docs.idura.app/verify/getting-started/glossary/#public-clients), meaning it does not use a client secret, but instead employs [PKCE](https://docs.idura.app/verify/getting-started/glossary/#pkce-proof-key-for-code-exchange) to ensure that a malicious actor cannot intercept the authorization code.

In addition to the basic OIDC flow, the SDK also supports [app switching](https://docs.idura.app/verify/guides/appswitch/) for the Danish MitID, Swedish BankID, and Swedish FrejaID apps.

This project is built using Swift, and targets iOS 17.4 and up. It builds on top of the [AppAuth library](https://github.com/openid/AppAuth-ios), which is maintained by the OpenID foundation. It has been tested on iOS 17.4, 18.6, and 26.

# Installation

## Using XCode

Open the following menu item in Xcode:

File > Add Package Dependencies...

In the Search or Enter Package URL search box enter this URL:

```
https://github.com/criipto/idura-verify-ios
```

Then, select the dependency rule and press Add Package.

## Using SwiftPM

```
swift package add-dependency https://github.com/criipto/idura-verify-ios --from 2.0.1
```

# Usage

If you prefer a more interactive approach, there is an [example project](https://github.com/criipto/idura-verify-ios/blob/master/Example/README.md) which your can run and play around with.

## Initialization

The SDK needs to be configured with two pieces of information:

- Your Idura domain.
- Your Idura client ID.

The SDK assumes that:

- You will be using your [Idura domain](https://docs.idura.app/verify/getting-started/glossary/#domain-idura-domain) to host your redirect URL (both custom domains, \*.criipto.id, and \*.idura.broker domains can be used).
- Your redirect URL will be `https://[YOUR IDURA DOMAIN]/ios/callback`.

You should register the callback URL in the [Idura dashboard](https://dashboard.idura.app). To use your a different domain, or redirect path, see the [Customization section](#customization).

The domain needs to be configured as an [Associated domain](https://developer.apple.com/documentation/xcode/configuring-an-associated-domain) in order for redirect and app switch to work. This is a two-way association:

1. You should add the following entitlements to your app:
   ```
   webcredentials:this-is-an-example.idura.broker # Always required
   applinks:this-is-an-example.idura.broker # Required for app-switching
   ```
2. The domain should host an [Associated Domains Entitlement](https://developer.apple.com/documentation/xcode/supporting-associated-domains) file. When you use your Idura domain, Idura manages this for you, as long as you configure your Apple team ID and the bundle ID of your app in the Idura dashboard.

The domain must also be passed when initializing the SDK. In order to prevent drift between the value stored in your entitlements and your code, we recommend adding your domain and client ID as config fields, and adding them to your `Info.plist` file:

`config.xxconfig`

```
IDURA_CLIENT_ID = this-is-an-example.idura.broker
IDURA_DOMAIN = urn:my:application:identifier:XXXX
```

`Info.plist`

```xml
<dict>
	<key>IDURA_CLIENT_ID</key>
    <!-- Don't put the actual value here, this is a reference to your config file -->
	<string>$(IDURA_CLIENT_ID)</string>
	<key>IDURA_DOMAIN</key>
	<string>$(IDURA_DOMAIN)</string>
</dict>
```

`App.entitlements`

```xml
<dict>
	<key>com.apple.developer.associated-domains</key>
	<array>
        <!-- Don't put the actual value here, this is a reference to your config file -->
		<string>webcredentials:$(IDURA_DOMAIN)</string>
		<string>applinks:$(IDURA_DOMAIN)</string>
	</array>
</dict>
</plist>
```

You can then instantiate the SDK like this:

```swift
let iduraVerify = IduraVerify(
    clientId: Bundle.main.object(forInfoDictionaryKey: "IDURA_CLIENT_ID") as! String,
    domain: Bundle.main.object(forInfoDictionaryKey: "IDURA_DOMAIN") as! String,
)
```

`IduraVerify` is stateful — it caches the OIDC discovery document and JWKS and runs a telemetry exporter. Construct one instance and hold it for the lifetime of the app. In SwiftUI, store it with `@StateObject` (or inject via `@Environment`) so the instance survives view rebuilds:

```swift
struct MainView: View {
    @StateObject private var iduraVerify = IduraVerify(
        clientId: Bundle.main.object(forInfoDictionaryKey: "IDURA_CLIENT_ID") as! String,
        domain: Bundle.main.object(forInfoDictionaryKey: "IDURA_DOMAIN") as! String,
    )

    var body: some View { /* ... */ }
}
```

### Ephemeral sessions

The web view used to display the login page to the user allows you to choose between using an ephemeral or a shared browser session.

- **An ephemeral session** Shares no cookies with the user's browser, so the user may have to enter their login details. This is the default.
- **A shared session** Shares cookies with the user's browser, so login details may be remembered between logins. However, the user is presented with the following dialog each time they want to log in:

<img width="325" height="198" src="https://github.com/user-attachments/assets/5f476841-d909-479b-8470-ec89cad8b1c0" />

It is up to you to decide which flow is better, based on the UX requirements of your application. Not all eIDs require the user to enter anything in the webview - For example, Swedish BankID will take the user directly to their authenticator app. For this reason, you may also choose to use an ephemeral session for some eIDs, but not for others. You can pass the `useEphemeralBrowserSession` parameter both to the SDK initializer, and to the `login` method.

Danish MitID supports a [re-authentication flow](https://docs.criipto.com/verify/e-ids/danish-mitid/#reauthentication), so you do not need to rely on a shared browser session if you need to re-authenticate the user with MitID.

## Logging in

```swift
let result = try await iduraVerify.login(eid: DanishMitID.substantial())
print(result.jwt.sub)
```

`login()` returns a `LoginResult`. The verified JWT is on `result.jwt`; the base64 encoded ID token is on `result.jwt.idToken` if you need it.

`result.traceId` is the Idura trace ID — Log it alongside your own error reporting so you can locate the flow in the Idura dashboard.

The SDK provides builder classes for some of the eIDs supported by Idura Verify. You should use these when possible, since they provide helper methods for the scopes and login hints supported by the specific eID provider. For example, Danish MitID supports SSN prefilling, which you can access using the `prefillSsn` method:

```swift
let result = try await iduraVerify.login(
    eid: DanishMitID.substantial().prefillSsn("123456-7890").withMessage("Hello there!"),
)
```

The returned JWT class has properties for some common claims such as `subject` and `identityscheme`. For other claims, use the `getClaimValue` function. For example, if you requested the `address` scope, you can access the address like so:

```swift
let address = result.jwt.getClaimValue(key: "address") as? [String: Any]
let streetAddress = address?["street_address"]
```

## Error handling

`IduraVerify.login()` throws `IduraVerifyError` for any runtime failure, with concrete cases you can pattern-match on. Every case also carries a `traceId`. Log it alongside your own error reporting so you can locate the flow in the Idura dashboard.

```swift
import IduraVerify

do {
  let result = try await iduraVerify.login(eid: DanishMitID.substantial())
  // ...
} catch IduraVerifyError.userCancelled(let traceId) {
  // User dismissed the browser or the IdP returned `access_denied`. Usually a normal
  // action — quietly return them to the previous screen rather than showing an error.
  _ = traceId
} catch IduraVerifyError.oauth(let error, let errorDescription, let traceId) {
  // The IdP returned a non-cancellation OAuth error. `error` is the OAuth 2.0 error code,
  // `errorDescription` is the optional human-readable text.
  _ = (error, errorDescription, traceId)
} catch let err as IduraVerifyError {
  // Catch-all for SDK-internal failures (PAR, JWT verification, browser plumbing). Treat
  // as unrecoverable; surface a generic error to the user and log `err.traceId`.
}
```

`IduraVerifyError` conforms to [`LocalizedError`](https://developer.apple.com/documentation/foundation/localizederror), so `err.localizedDescription` returns a meaningful string suitable for logging.

# Customization

## Using a custom callback domain

In this context, a _custom_ domain means a domain _not_ hosted by Idura. If you have registered a custom (vanity) domain in the Idura dashboard, and pointed it towards criipto.id / idura.broker, you do not need to do anything else.

If you want to use another domain, you need to host an `apple-app-site-association` file on the domain, as described in the [Apple documentation](https://developer.apple.com/documentation/xcode/supporting-associated-domains).

## Using a custom callback URL

If you want to a different callback URL you can pass it when initializing the SDK:

```swift
let domain = Bundle.main.object(forInfoDictionaryKey: "IDURA_DOMAIN") as! String
let iduraVerify = IduraVerify(
  clientId: Bundle.main.object(forInfoDictionaryKey: "IDURA_CLIENT_ID") as! String,
  domain: domain,
  redirectUri: URL(string: "https://" + domain)!.appendingPathComponent("/my/custom/callback")
)
```

## Presenting the browser yourself (backend-initialized flow)

By default, the SDK handles the entire OIDC flow end-to-end: it builds the authorization request, pushes it to Idura, opens the browser, receives the callback, exchanges the code, and returns the verified JWT on the device.

Some applications instead want the authorization request to be initialized by their own backend — for example, when the JWT must stay on the server rather than reaching the device, or in hybrid setups such as Auth0 where the token exchange happens server-side. In that case the SDK does not need to generate the OIDC request at all, but it can still be used to open the browser and receive the callback URL. The `BrowserManager` class is exposed for exactly this purpose:

```swift
let browser = try BrowserManager(
  redirectUri: URL(string: "https://your-domain.idura.broker/ios/callback")!,
  useEphemeralBrowserSession: true
)

// `authorizeUrl` is the authorization URL your backend returned after initializing the flow.
let callbackUrl = try await browser.present(url: authorizeUrl)

// `callbackUrl` contains the OIDC response (code, state, or error). Send it to your backend
// to complete the code exchange.
```

The same Associated Domain setup described in [Initialization](#initialization) applies: `redirectUri` must be an `https://` URL on a domain configured as an Associated Domain in your app's entitlements, otherwise `ASWebAuthenticationSession` will not match the callback. The initializer throws `BrowserManagerError.configurationError` if `redirectUri` does not use the `https` scheme.

### App-switching when using `BrowserManager`

In the default end-to-end flow, the SDK appends the app-switch `login_hint`s automatically — `appswitch:ios` for Danish MitID and FrejaID, and `appswitch:resumeUrl:<redirectUri>` for Danish MitID, FrejaID, and Swedish BankID — so that the authenticator apps can open the eID app and return the user to your app afterwards.

When you initialize the OIDC request on your own backend and only use `BrowserManager` to present it, **your backend is responsible for including these hints** in the authorization request it pushes to Idura. If they are missing, the flow still works in the web view, but users will not be switched back from the authenticator app to your app. Add the following `login_hint` values (space-separated, alongside any other hints) when initializing the request:

| eID               | Hints to include                                                      |
| ----------------- | --------------------------------------------------------------------- |
| Danish MitID      | `appswitch:ios`, `appswitch:resumeUrl:<your redirectUri>`             |
| FrejaID           | `appswitch:ios`, `appswitch:resumeUrl:<your redirectUri>`             |
| Swedish BankID    | `appswitch:resumeUrl:<your redirectUri>`                              |
