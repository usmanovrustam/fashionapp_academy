# Firebase Setup (real project only)

Sylyo does **not** use mock auth or mock databases. Auth, wardrobe, images, and analytics all require your Firebase project.

## 1. Create / select a Firebase project

1. Open [Firebase Console](https://console.firebase.google.com/)
2. Create a project (or select existing)
3. Add an **iOS app** with bundle id `apple.academy.stylo`
4. Download **GoogleService-Info.plist**

## 2. Install the plist in this repo

```bash
# Option A — drag GoogleService-Info.plist into fashionapp/ in Xcode
# Option B — CLI (after firebase login):
./scripts/fetch-google-service-info.sh
```

Target path:

```text
fashionapp/GoogleService-Info.plist
```

Without this file the app shows **Connect Firebase** and will not enter the main UI.

## 3. Enable products

In Firebase Console enable:

| Product | Settings |
|---|---|
| Authentication | Email/Password **on**; Anonymous **on** (guest) |
| Cloud Firestore | Production or test mode, then deploy rules below |
| Storage | Default bucket, deploy rules below |
| Analytics | Enabled (default) |
| BigQuery | Project Settings → Integrations → BigQuery → Link |

## 4. Deploy rules & indexes

```bash
firebase login
firebase use <your-project-id>
firebase deploy --only firestore:rules,firestore:indexes,storage
```

## 5. BigQuery analytics

### A. Firebase Analytics → BigQuery (required)

1. Firebase Console → Project Settings → Integrations → **BigQuery**
2. Link the Analytics property
3. Events appear in dataset `analytics_<property_id>` as `events_YYYYMMDD`
4. Use SQL in `bigquery/queries.sql`

Tracked events include:

- `sign_up`, `login`, `logout`
- `scan_started`, `scan_completed`, `item_saved`
- `recommendation_viewed`, `recommendation_accepted`, `recommendation_rejected`
- `assistant_asked`, `assistant_replied`
- `screen_view`, `weather_loaded`, `profile_updated`

### B. Firestore → BigQuery (recommended for wardrobe analysis)

Install extension **Stream Firestore to BigQuery** for:

- `users/{userId}/analyticsEvents`
- `users/{userId}/wardrobeItems`
- `users/{userId}/recommendations`

See `extensions/firestore-bigquery-export.env.example`.

## 6. Cursor Firebase MCP

Project config is in `.cursor/mcp.json`. After `firebase login`, Cursor can manage Auth users, Firestore, and rules via the Firebase MCP server.

## 7. Firestore data model

```text
users/{uid}/profile/main
users/{uid}/wardrobeItems/{itemId}
users/{uid}/outfits/{outfitId}
users/{uid}/recommendations/{id}
users/{uid}/events/{eventId}
users/{uid}/packingLists/{listId}
users/{uid}/outfitHistory/{entryId}
users/{uid}/weatherCache/latest
users/{uid}/analyticsEvents/{eventId}
```

Images live in Storage:

```text
users/{uid}/images/{filename}
```
