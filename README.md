# Sylyo — AI Fashion Stylist

Personal AI stylist for iOS. Scan clothing, sync a digital wardrobe to **Firebase**, and get weather-aware outfit recommendations with analytics exported to **BigQuery**.

## Architecture

```text
App/                 Composition root, auth gate, tabs
DesignSystem/        Colors, spacing, reusable UI
Domain/              Entities, protocols, use cases
Data/                (legacy local adapters retained for reference)
Infrastructure/      Firebase Auth/Firestore/Storage/Analytics, Vision, WeatherKit
Features/            SwiftUI screens + view models
```

**Backend (required):** Firebase Auth + Cloud Firestore + Cloud Storage + Analytics → BigQuery.

There is **no mock auth/database path**. Without `GoogleService-Info.plist` the app shows a setup screen.

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
| Analytics | Firebase Analytics + Firestore event mirror |
| Analysis | BigQuery SQL in `bigquery/queries.sql` |

## Requirements

- Xcode 16+
- iOS 17.6+
- Firebase project with `GoogleService-Info.plist`
- Capabilities: Camera, Photos, Location, WeatherKit

## Run

1. Open `fashionapp.xcodeproj` (SPM resolves `firebase-ios-sdk`)
2. Add your real `GoogleService-Info.plist`
3. Select a development team
4. Build & run on a device

## Localization

English and Italian in `en.lproj` / `it.lproj`.
