# Example

This example application shows you how to integrate the Idura Verify iOS SDK.

Note that eIDs which use authenticator apps (Danish MitID, Swedish and Norwegian BankID) cannot be used in a simulator. So to test the full experience, you should have access to a physical iOS device.

1. Clone this repo.
2. Open the repo in XCode or VSCode with [SweetPad](https://sweetpad.hyzyla.dev/docs/intro/).
3. Create a domain in the [Idura dashboard](https://dashboard.idura.app/domains), if you haven't done so already.
4. Create a new Verify application in the Idura dashboard.
   1. Add `https://[YOUR DOMAIN]/ios/callback` as redirect URL.
   2. In the Native / Mobile section, set "Bundle ID" to `eu.idura.sdk.Example` (since this application will not be published, you don't need to use your own bundle name), and "Team ID" to your Apple team ID.

      You can find your Apple team ID at https://developer.apple.com/account. This requires a paid apple developer account.

5. Copy `Example/Configs/example.xxconfig` to `Example/Configs/config.xxconfig`, and add your Idura domain, client ID, and Apple team ID.
6. Run the application
7. Run a mock login, to verify that everything works as expected
8. :tada:

The mock provider works out of the box, but other eID providers require you to register test users before you can run a login. See https://docs.idura.com/verify/e-ids/.
