# Firebase Setup (real project only)

Nook does **not** use mock auth or mock databases. Auth is **Firebase Authentication** (email/password, **Sign in with Apple**, and anonymous). Wardrobe, images, and analytics all require your Firebase project. There is no CloudKit dependency — see `CLEAN_BUILD.md` if an old install still logs CloudKit.

## Current status

| Service | Status |
|---|---|
| Project | `sylyo-fashion` (display: stylo) |
| GoogleService-Info.plist | In repo |
| Authentication | Email/Password + Apple + Anonymous enabled |
| Firestore | Database + rules deployed |
| Storage | Bucket `sylyo-fashion.firebasestorage.app` + rules |
| Google Analytics | Property `548069136` linked |
| BigQuery | Linked — dataset `analytics_548069136` (may take up to 24h to appear) |

## Active project

| | |
|---|---|
| Project | **Nook** |
| Project ID | `sylyo-fashion` |
| Console | https://console.firebase.google.com/project/sylyo-fashion/overview |
| iOS bundle id | `apple.academy.stylo` |
| Config file | `fashionapp/GoogleService-Info.plist` (already downloaded) |

Firestore database + security rules are deployed.

### Finish these 3 console steps (one-time)

1. **Authentication** → Get started → enable **Email/Password**, **Apple**, and **Anonymous**  
   https://console.firebase.google.com/project/sylyo-fashion/authentication/providers  
   For Apple: add the Services ID / team + key from Apple Developer (Sign in with Apple), and enable the capability on the `apple.academy.stylo` App ID.
2. **Storage** → Get started (may ask to enable billing / Blaze)  
   https://console.firebase.google.com/project/sylyo-fashion/storage
3. **BigQuery** link (Analytics)  
   https://console.firebase.google.com/project/sylyo-fashion/settings/integrations/bigquery

Then rebuild the iOS app in Xcode.

## 3. Enable products

In Firebase Console enable:

| Product | Settings |
|---|---|
| Authentication | Email/Password **on**; Apple **on**; Anonymous **on** (guest) |
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
