#!/bin/bash
# Sync your Mac working copy onto origin/develop without losing Mac-only files
# (MaskEditorView, etc.). Run from repo root:
#   bash scripts/sync-mac-to-develop.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Backing up Mac-only / dirty files to .mac-backup/"
mkdir -p .mac-backup
timestamp=$(date +%Y%m%d-%H%M%S)
backup=".mac-backup/$timestamp"
mkdir -p "$backup"

# Save anything that would block pull
git status --porcelain > "$backup/status.txt" || true
cp -R fashionapp/Features/Scanner "$backup/Scanner" 2>/dev/null || true
cp -R fashionapp/Infrastructure/Vision "$backup/Vision" 2>/dev/null || true
cp fashionapp.xcodeproj/project.pbxproj "$backup/project.pbxproj" 2>/dev/null || true

echo "==> Stashing tracked local changes"
git stash push -u -m "mac-local-before-sync-$timestamp" || true

echo "==> Fast-forwarding develop"
git fetch origin develop
git checkout develop
git reset --hard origin/develop

echo "==> Restoring Mac-only files that are NOT on develop (if any)"
# MaskEditorView is Mac-only today — put it back if we backed it up.
if [[ -f "$backup/Scanner/MaskEditorView.swift" ]]; then
  mkdir -p fashionapp/Features/Scanner
  cp "$backup/Scanner/MaskEditorView.swift" fashionapp/Features/Scanner/MaskEditorView.swift
  echo "    restored MaskEditorView.swift"
fi

echo ""
echo "OK: branch is origin/develop + optional MaskEditorView restore."
echo "Backup: $backup"
echo "Stash:  git stash list   (recover with: git stash pop)"
echo ""
echo "Next in Xcode: Product → Clean Build Folder → Build"
echo "If MaskEditorView still errors, paste the applyBrushStroke call site."
