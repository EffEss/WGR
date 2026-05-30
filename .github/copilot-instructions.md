# Copilot Instructions

## Project Guidelines
- When building the iOS app locally, must run `cp Assets/iDrizzle.png ios/iDrizzle/AppIcon.png` before building in Xcode. The destination file is gitignored and not in the repo.
- When building the watchOS app (`ios/iDrizzleWatch`) locally, must run `cp Assets/iDrizzle.png ios/iDrizzleWatch/AppIcon.png` before building in Xcode. The destination file is gitignored and not in the repo. `setup-ios-local.sh` copies both icons automatically.
- When building the iOS app locally, must create `ios/Local.xcconfig` from `ios/Local.xcconfig.template` and set `DRIZZLE_DEVELOPMENT_TEAM` to the Apple Developer Team ID. The file is gitignored so the Team ID is never committed. The watchOS app reuses the same `ios/Local.xcconfig`.
- When bumping the version for a new release, always update `versionName` in `android/app/build.gradle.kts` to match the new version number. The Android workflow reads this value to auto-rename the APK/AAB to `Drizzle_v{version}`.
- For Play Store Android releases, always build a signed AAB (`bundleRelease`) and keep signing secrets in gitignored `android/keystore.properties` or GitHub Actions secrets, never in tracked files.
- When bumping the version for a new release, also update `CFBundleShortVersionString` in `ios/iDrizzle/Info.plist` to match the new version number.
- When bumping the version for a new release, also update `CFBundleShortVersionString` in `ios/iDrizzleWatch/Info.plist` to match the new version number (keep it aligned with the iOS app).