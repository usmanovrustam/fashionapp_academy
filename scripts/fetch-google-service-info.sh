#!/usr/bin/env bash
# Downloads GoogleService-Info.plist from a real Firebase iOS app into fashionapp/.
# Prerequisites: firebase login && firebase use <project-id>
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/fashionapp/GoogleService-Info.plist"
BUNDLE_ID="${1:-apple.academy.stylo}"

echo "Fetching iOS SDK config for bundle id: $BUNDLE_ID"
npx -y firebase-tools@latest apps:sdkconfig IOS --out "$OUT"

if [[ ! -f "$OUT" ]]; then
  echo "Failed to write $OUT"
  echo "Create an iOS app in Firebase Console with bundle id $BUNDLE_ID, then re-run."
  exit 1
fi

echo "Wrote $OUT"
echo "Rebuild the Xcode project to pick up the real Firebase config."
