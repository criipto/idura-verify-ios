
## End-to-end tests

`ExampleUITests` drives the SDK end-to-end through the real `ASWebAuthenticationSession`
browser and eID app flows — the path the unit tests can't reach. The suite is split into
happy-path logins (`LoginUITests`) and cancellations (`CancellationUITests`).

### Why these run on a device, not the Simulator

Unlike the Android suite — where the mock login runs headless on the emulator — **none of the
login flows run on the iOS Simulator**, including mock. The SDK receives the OAuth callback
through an `ASWebAuthenticationSession` HTTPS (associated-domain) callback, and
`com.apple.developer.associated-domains` is a provisioned entitlement that is stripped from
Simulator builds (which use no provisioning profile). Without it the session fails immediately
with `IduraVerifyError.associatedDomainsNotConfigured`. So every login test needs a **physical
device** signed with a team whose App ID has Associated Domains enabled (the same setup the
README's getting-started steps describe).

Run the mock login on a connected device with:

```sh
cd Example
xcodebuild test -scheme Example \
  -destination 'platform=iOS,id=<DEVICE_UDID>' -allowProvisioningUpdates \
  -only-testing:ExampleUITests/LoginUITests/testMockLogin
```

The device must be unlocked and have **Settings → Privacy & Security → Developer Mode** on and
**Enable UI Automation** on, otherwise the run fails with "Timed out while enabling automation
mode". A USB connection is more reliable than wireless for automation.

The eID tests drive the real MitID, SE BankID and Vipps test apps (all the same staging/preprod
builds), which must be installed and enrolled. They read credentials from the environment, so
they stay out of the repo — `xcodebuild` forwards `TEST_RUNNER_<NAME>` to the test runner as
`<NAME>`. Run a specific eID test like:

```sh
TEST_RUNNER_SEBANKID_CODE=<code> xcodebuild test -scheme Example \
  -destination 'platform=iOS,id=<DEVICE_UDID>' -allowProvisioningUpdates \
  -only-testing:ExampleUITests/LoginUITests/testSEBankID
```

Credentials per flow: `MITID_USER_ID` + `MITID_PIN`; `SEBANKID_CODE`; `VIPPS_PIN`; `NOBANKID_ID`
+ `NOBANKID_PASSWORD`.
