#!/usr/bin/env bash
# Fails the build/CI if any CloudKit / legacy iCloud wardrobe code reappears.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PATTERN='CloudKit|CKContainer|CKRecord|CKDatabase|CKQuery|CKAsset|iCloudAuthManager|iCloud\.apple\.academy\.fashionapp|privateCloudDatabase|CloudKit Manager'

if git grep -nE "$PATTERN" -- \
  ':!README.md' \
  ':!FIREBASE_SETUP.md' \
  ':!CLEAN_BUILD.md' \
  ':!scripts/verify-no-cloudkit.sh' \
  >/tmp/cloudkit-hits.txt 2>/dev/null; then
  echo "❌ CloudKit / legacy iCloud references found:"
  cat /tmp/cloudkit-hits.txt
  exit 1
fi

# Entitlements must not enable iCloud containers.
if rg -n 'com\.apple\.developer\.icloud|iCloud\.' fashionapp/*.entitlements NookWidgets/*.entitlements 2>/dev/null; then
  echo "❌ iCloud entitlements still present"
  exit 1
fi

echo "✅ No CloudKit / iCloud wardrobe code or entitlements in the project."
