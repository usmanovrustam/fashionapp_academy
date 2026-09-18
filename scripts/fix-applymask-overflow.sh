#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
git fetch origin develop
git checkout origin/develop -- fashionapp/Infrastructure/Vision/ImageProcessing.swift
echo "OK: ImageProcessing.swift replaced with Int-safe applyMask"
echo "Now: Xcode → Product → Clean Build Folder → Run"
