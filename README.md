# Sylyo — AI Fashion Stylist

Personal AI stylist for iOS. Scan clothing, sync a digital wardrobe to **Firebase**, and get weather-aware outfit recommendations with analytics exported to **BigQuery**.

## Architecture

```text
App/                 Composition root, Firebase auth gate, tabs
DesignSystem/        iOS 27 Liquid Glass tokens + reusable UI
Domain/              Entities, protocols, use cases
Data/Persistence/    Local image cache for Firebase Storage downloads
Infrastructure/      Firebase Auth/Firestore/Storage/Analytics, Vision, WeatherKit, Widgets
Features/            SwiftUI screens + view models
SylyoWidgets/        iOS 27 WidgetKit extension (App Group sync)
```

**Backend (required):** Firebase Auth + Cloud Firestore + Cloud Storage + Analytics → BigQuery.

Auth is **Firebase only** (email/password + anonymous). CloudKit was removed. Without `GoogleService-Info.plist` the app shows a setup screen.

If a device still logs `CloudKit Manager initialized`, follow **[CLEAN_BUILD.md](CLEAN_BUILD.md)** (old install — pull `develop`, clean DerivedData, delete the app, reinstall).

## Firebase + BigQuery

See **[FIREBASE_SETUP.md](FIREBASE_SETUP.md)** for the full checklist.

Quick start:

1. Download `GoogleService-Info.plist` from your Firebase iOS app
2. Place it at `fashionapp/GoogleService-Info.plist`
3. Enable Auth (Email/Password + Anonymous), Firestore, Storage, Analytics
4. `firebase deploy --only firestore:rules,firestore:indexes,storage`
5. Link Analytics → BigQuery; optionally install Firestore→BigQuery extension
6. Build & run in Xcode

Cursor Firebase MCP is configured in `.cursor/mcp.json` (`npx firebase-tools@latest mcp`).

## Features

| Area | Implementation |
|---|---|
| Auth | Firebase Email/Password + Anonymous |
| Wardrobe / profile / outfits | Cloud Firestore (per-user paths) |
| Images | Firebase Storage (+ local cache for UI) |
| Clothing scanner | U²-Net + metadata pipeline |
| Recommendations | Weather-aware engine |
| AI stylist chat | Wardrobe intent assistant |
| Liquid Glass UI | `.glassEffect` / `GlassEffectContainer` across custom surfaces |
| Brand colors | Soft pastel sky blue · light theme only · matte black / grey text |
| Home Screen widgets | Today Outfit + Wardrobe Glance |
| Analytics | Firebase Analytics + Firestore event mirror |
| Analysis | BigQuery SQL in `bigquery/queries.sql` |

## Requirements

- Xcode 16+ (iOS 26/27 SDK recommended for Liquid Glass)
- iOS 18.0+ (Liquid Glass on iOS 26+; material fallback earlier)
- Firebase project with `GoogleService-Info.plist`
- Capabilities: Camera, Photos, Location, WeatherKit, App Group `group.apple.academy.stylo`

## Run

1. Open `fashionapp.xcodeproj` (SPM resolves `firebase-ios-sdk`)
2. Add your real `GoogleService-Info.plist`
3. Select a development team
4. Build & run on a device

## Localization

English and Italian in `en.lproj` / `it.lproj`.
