#!/bin/bash
# Hard-sync your Mac working copy onto origin/develop.
# Backs up local dirty files, then resets to remote. Does NOT restore old
# MaskEditorView / FashionShotService — those now live on develop with the
# fixed applyBrushStroke call site and no FirebaseFunctions SPM dependency.
#   bash scripts/sync-mac-to-develop.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Backing up Mac dirty files to .mac-backup/ (reference only)"
mkdir -p .mac-backup
timestamp=$(date +%Y%m%d-%H%M%S)
backup=".mac-backup/$timestamp"
mkdir -p "$backup"

git status --porcelain > "$backup/status.txt" || true
cp -R fashionapp/Features/Scanner "$backup/Scanner" 2>/dev/null || true
cp -R fashionapp/Infrastructure/Vision "$backup/Vision" 2>/dev/null || true
cp -R fashionapp/Infrastructure/Firebase "$backup/Firebase" 2>/dev/null || true
cp fashionapp.xcodeproj/project.pbxproj "$backup/project.pbxproj" 2>/dev/null || true

echo "==> Stashing tracked local changes"
git stash push -u -m "mac-local-before-sync-$timestamp" || true

echo "==> Fast-forwarding develop"
git fetch origin develop
git checkout develop
git reset --hard origin/develop

echo ""
echo "OK: working tree is exactly origin/develop."
echo "Backup (not restored): $backup"
echo "Stash:  git stash list   (recover with: git stash pop — avoid if it reintroduces FirebaseFunctions)"
echo ""
echo "Next in Xcode: File → Packages → Reset Package Caches, then Product → Clean Build Folder → Build"
echo "Confirm ImageProcessing.applyBrushStroke(to:at:radius:add:) and no import FirebaseFunctions."
