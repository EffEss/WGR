# Publishing iDrizzle to the App Store

This guide covers the full, repeatable process for releasing the Apple platform
apps. iOS/watchOS releases are automated with GitHub Actions
([`.github/workflows/ios-release.yml`](../.github/workflows/ios-release.yml)).

`iDrizzle` and `iDrizzleWatch Watch App` now live in **one Xcode project**
(`ios/iDrizzle.xcodeproj`). The watch target is `WKWatchOnly` (independent on
watch hardware) but is packaged through the iOS archive via Xcode's
**Embed Watch Content** relationship.

> **Security note:** all credentials live in GitHub **encrypted repository
> secrets** (Settings → Secrets and variables → Actions). Nothing secret is ever
> stored in the repository, so there is nothing to `.gitignore`. The only local
> file involved is the `.p8` API key, which stays on your Mac and is never
> committed. No real IDs are printed in this repo.

---

## How a release works

Pushing a version tag — or running the **iOS Release** workflow manually from the
Actions tab — archives the `iDrizzle` scheme (which includes the embedded watch
app) and uploads once to App Store Connect / TestFlight:

```sh
git tag v2.1.0
git push origin v2.1.0
```

No certificates or provisioning profiles are stored in the repo; CI imports one
Apple Distribution certificate and then Xcode's `-allowProvisioningUpdates`
resolves the needed App Store profiles for both `com.idrizzle.app` and
`com.idrizzle.app.watchkitapp` using the App Store Connect API key.

---

## One-time setup

### 1. Register the bundle IDs

Apple Developer → *Certificates, Identifiers & Profiles → Identifiers* →
**+ → App IDs → App** (Explicit):

- `com.idrizzle.app` — iOS app
- `com.idrizzle.app.watchkitapp` — embedded watch app target

> Old `com.drizzle.*` identifiers from earlier attempts are permanently locked by
> Apple once they've touched the App Store and **cannot be deleted**. This is
> expected and harmless — they never conflict with the `com.idrizzle.*` IDs and
> can be ignored.

### 2. Create the iOS app record

App Store Connect → *My Apps → +*:

- **iDrizzle** bound to `com.idrizzle.app`

The watch app is delivered through the iOS app's archive (embedded watch content),
so there is no separate watch upload pipeline or `altool --upload-package` step.
Keep watch metadata/screenshots aligned in the iOS app's App Store Connect record.

### 3. Create an App Store Connect API key

App Store Connect → *Users and Access → Integrations tab → App Store Connect API*:

1. Click **+** to generate a key. Name it (e.g. `iDrizzle CI`), role **Admin**.
   The **Admin** role is required: cloud signing in CI (`-allowProvisioningUpdates`)
   has to create the Apple Distribution certificate and App Store provisioning
   profile, which the lesser *App Manager* role cannot do — it fails with
   `Cloud signing permission error` / `No profiles for 'com.idrizzle.app' were found`.
2. Note the **Key ID** (in the keys list) and the **Issuer ID** (shown above the list).
3. **Download** the `AuthKey_XXXXXXXXXX.p8` — you can only download it **once**.
   Keep it on your Mac, outside the repo.

---

## Required GitHub repository secrets

Add these under *Settings → Secrets and variables → Actions → New repository secret*:

| Secret | Where to get it |
| --- | --- |
| `DRIZZLE_DEVELOPMENT_TEAM` | Your 10-character Apple Developer **Team ID** (developer.apple.com → Membership details). Same value as local `ios/Local.xcconfig`. |
| `ASC_API_KEY_ID` | The API **Key ID** from the App Store Connect API keys list. |
| `ASC_API_ISSUER_ID` | The **Issuer ID** (UUID) shown above the API keys list. |
| `ASC_API_KEY_P8_BASE64` | The downloaded `.p8`, base64-encoded. |
| `WATCH_DIST_CERT_P12_BASE64` | Your Apple **Distribution** certificate **and private key** exported as a `.p12`, then base64-encoded. CI imports this cert into a temporary keychain so Xcode reuses it instead of trying to create a new distribution certificate each run. |
| `WATCH_DIST_CERT_PASSWORD` | The password you set when exporting the `.p12`. |

To produce the base64 value, run on your **Mac**:

```sh
base64 -i ~/Downloads/AuthKey_XXXXXXXXXX.p8 | pbcopy
```

That copies the encoded key to the clipboard so you can paste it into the secret.

### Generating the distribution certificate

CI uses automatic signing with `-allowProvisioningUpdates`, but a clean runner
still needs an Apple Distribution certificate + private key available in its
keychain so Xcode can reuse it (instead of trying to create a new one each run).
One-time setup:

1. In **Xcode → Settings → Accounts → (your team) → Manage Certificates… → + → Apple Distribution**, create/select your distribution cert, then right-click it →
   **Export Certificate** to save a `.p12` (set a password).
2. Base64-encode the `.p12` and store it in `WATCH_DIST_CERT_P12_BASE64`, and
   store the export password in `WATCH_DIST_CERT_PASSWORD`:

   ```sh
   base64 -i ~/Desktop/distribution.p12 | pbcopy
   ```

Xcode then manages provisioning profiles for both bundle IDs (`com.idrizzle.app`
and `com.idrizzle.app.watchkitapp`) during CI archive/export using the App Store
Connect API key.

> The GitHub Action authenticates to Apple **solely** through these secrets.
> It does not use Xcode's GitHub connection or your Apple ID login — the CI runner
> is a clean macOS VM that knows nothing about your accounts beyond these values.

---

## App Store Connect metadata fields

The store listing must be completed for the iOS app record (required even for a free app):

- **App name** and **subtitle** — `iDrizzle`
- **Primary category** (Weather) and optional secondary category
- **Description**, **keywords**, **promotional text**, and **support URL**
- **Privacy policy URL**
- **App Privacy** questionnaire — this app collects no user data; radar GIFs are fetched anonymously from AccuWeather
- **Age rating** questionnaire
- **Pricing & Availability** — Free
- **Screenshots** for each required device size (6.7"/6.5" iPhone, 12.9" iPad, and Apple Watch) — see [`Assets/screenshots/`](../Assets/screenshots)
- **App icon** (1024×1024, opaque) — `Assets/appicon_drizzle_1024_opaque.png`
- **Export compliance** — uses only standard HTTPS, so exempt
- **Build** selection — auto-populated by the uploaded TestFlight build

---

## Verifying the link without a full release

Trigger the **iOS Release** workflow manually (Actions tab → *iOS Release* →
*Run workflow*). If any secret is missing or wrong, it fails at the
archive/upload step with a clear error — letting you confirm the Apple link
before committing to a real version tag.
