# Publishing iDrizzle to the App Store

This guide covers the full, repeatable process for releasing the Apple platform
apps. iOS/watchOS releases are automated with GitHub Actions
([`.github/workflows/ios-release.yml`](../.github/workflows/ios-release.yml)).

`iDrizzle` (iOS/iPadOS) and `iDrizzleWatch` (watchOS) are **two independent,
standalone apps** — the watch app is not embedded in the iOS app — so each gets
its **own App Store Connect app record** and its own listing.

> **Security note:** all credentials live in GitHub **encrypted repository
> secrets** (Settings → Secrets and variables → Actions). Nothing secret is ever
> stored in the repository, so there is nothing to `.gitignore`. The only local
> file involved is the `.p8` API key, which stays on your Mac and is never
> committed. No real IDs are printed in this repo.

---

## How a release works

Pushing a version tag — or running the **iOS Release** workflow manually from the
Actions tab — archives both apps with automatic signing and uploads them straight
to App Store Connect / TestFlight:

```sh
git tag v2.1.0
git push origin v2.1.0
```

No certificates or provisioning profiles are stored in the repo; Xcode's
`-allowProvisioningUpdates` creates them in CI using the App Store Connect API
key. Since the watch app changes rarely, a tagged release also re-uploads it, but
that only produces a new review if its version/build number was bumped.

---

## One-time setup

### 1. Register the bundle IDs

App Store Connect → *Certificates, Identifiers & Profiles → Identifiers* →
**+ → App IDs → App** (Explicit):

- `com.idrizzle.app` — iOS app
- `com.idrizzle.watchapp` — standalone watchOS app

> Old `com.drizzle.*` identifiers from earlier attempts are permanently locked by
> Apple once they've touched the App Store and **cannot be deleted**. This is
> expected and harmless — they never conflict with the `com.idrizzle.*` IDs and
> can be ignored.

### 2. Create two app records

App Store Connect → *My Apps → +*:

- **iDrizzle** bound to `com.idrizzle.app` (platforms: iOS, iPadOS, macOS as desired)
- **iDrizzleWatch** bound to `com.idrizzle.watchapp` (watchOS)

Leave the *Apple Watch* screenshot tab on the iOS record empty — the watch app is
shipped through its own record, not embedded.

### 3. Create an App Store Connect API key

App Store Connect → *Users and Access → Integrations tab → App Store Connect API*:

1. Click **+** to generate a key. Name it (e.g. `iDrizzle CI`), role **App Manager**.
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

To produce the base64 value, run on your **Mac**:

```sh
base64 -i ~/Downloads/AuthKey_XXXXXXXXXX.p8 | pbcopy
```

That copies the encoded key to the clipboard so you can paste it into the secret.

> The GitHub Action authenticates to Apple **solely** through these four secrets.
> It does not use Xcode's GitHub connection or your Apple ID login — the CI runner
> is a clean macOS VM that knows nothing about your accounts beyond these values.

---

## App Store Connect metadata fields

The store listing must be completed once per app (required even for a free app):

- **App name** and **subtitle** — `iDrizzle` / `iDrizzleWatch`
- **Primary category** (Weather) and optional secondary category
- **Description**, **keywords**, **promotional text**, and **support URL**
- **Privacy policy URL**
- **App Privacy** questionnaire — this app collects no user data; radar GIFs are fetched anonymously from AccuWeather
- **Age rating** questionnaire
- **Pricing & Availability** — Free
- **Screenshots** for each required device size (6.7"/6.5" iPhone, 12.9" iPad, and Apple Watch) — see [`Assets/screenshots/`](../Assets/screenshots)
- **App icon** (1024×1024, opaque) — `Assets/iDrizzle.png`
- **Export compliance** — uses only standard HTTPS, so exempt
- **Build** selection — auto-populated by the uploaded TestFlight build

---

## Verifying the link without a full release

Trigger the **iOS Release** workflow manually (Actions tab → *iOS Release* →
*Run workflow*). If any secret is missing or wrong, it fails at the
archive/upload step with a clear error — letting you confirm the Apple link
before committing to a real version tag.
