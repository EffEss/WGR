#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ICON_SRC="$ROOT_DIR/Assets/iDrizzle.png"
IOS_APP_DIR="iDrizzle"
WATCH_APP_DIR="iDrizzleWatch"
ICON_DST="$ROOT_DIR/ios/$IOS_APP_DIR/AppIcon.png"
WATCH_ICON_DST="$ROOT_DIR/ios/$WATCH_APP_DIR/AppIcon.png"
XCCONFIG_TEMPLATE="$ROOT_DIR/ios/Local.xcconfig.template"
XCCONFIG_LOCAL="$ROOT_DIR/ios/Local.xcconfig"
PROJECT_PATH="$ROOT_DIR/ios/iDrizzle.xcodeproj"
WATCH_PROJECT_PATH="$ROOT_DIR/ios/iDrizzleWatch.xcodeproj"

if [[ ! -f "$ICON_SRC" ]]; then
  echo "Missing iOS icon source: $ICON_SRC"
  exit 1
fi

cp "$ICON_SRC" "$ICON_DST"
echo "Copied app icon -> ios/$IOS_APP_DIR/AppIcon.png"

if [[ -d "$ROOT_DIR/ios/$WATCH_APP_DIR" ]]; then
  cp "$ICON_SRC" "$WATCH_ICON_DST"
  echo "Copied app icon -> ios/$WATCH_APP_DIR/AppIcon.png"
fi

if [[ ! -f "$XCCONFIG_LOCAL" ]]; then
  cp "$XCCONFIG_TEMPLATE" "$XCCONFIG_LOCAL"
  echo "Created ios/Local.xcconfig from template"
fi

if ! grep -Eq '^\s*DRIZZLE_DEVELOPMENT_TEAM\s*=\s*[A-Za-z0-9]{10}\s*$' "$XCCONFIG_LOCAL"; then
  read -r -p "Enter your 10-character Apple Team ID: " TEAM_ID
  if [[ ! "$TEAM_ID" =~ ^[A-Za-z0-9]{10}$ ]]; then
	echo "Invalid Team ID. Expected exactly 10 alphanumeric characters."
	exit 1
  fi

  if grep -Eq '^\s*DRIZZLE_DEVELOPMENT_TEAM\s*=' "$XCCONFIG_LOCAL"; then
	sed -i.bak -E "s/^\s*DRIZZLE_DEVELOPMENT_TEAM\s*=.*/DRIZZLE_DEVELOPMENT_TEAM = $TEAM_ID/" "$XCCONFIG_LOCAL"
  else
	echo "DRIZZLE_DEVELOPMENT_TEAM = $TEAM_ID" >> "$XCCONFIG_LOCAL"
  fi
  rm -f "$XCCONFIG_LOCAL.bak"
  echo "Updated ios/Local.xcconfig"
fi

open "$PROJECT_PATH"
echo "Opened ios/iDrizzle.xcodeproj in Xcode"

if [[ -d "$WATCH_PROJECT_PATH" ]]; then
  open "$WATCH_PROJECT_PATH"
  echo "Opened ios/iDrizzleWatch.xcodeproj in Xcode"
fi
