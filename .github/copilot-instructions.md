# Copilot Instructions

## Project Guidelines
- When building the iOS Drizzle app locally, must run `cp Assets/1024.png ios/Drizzle/AppIcon.png` before building in Xcode. The file is gitignored and not in the repo.
- When bumping the version for a new release, always update `versionName` in `android/app/build.gradle.kts` to match the new version number. The Android workflow reads this value to auto-rename the APK to `Drizzle_v{version}.apk`.