# Clean rebuild (CloudKit fully removed)

`origin/develop` and `origin/main` have **zero CloudKit code**.  
If Xcode still prints:

```text
📦 CloudKit Manager initialized...
📦 Container identifier: iCloud.apple.academy.fashionapp
```

you are running an **old binary** from before the Firebase rewrite. The old `fashionapp/Outfit.swift` CloudKit manager is deleted.

## Desktop fix (required)

```bash
cd /path/to/fashionapp_academy
git fetch origin
git checkout develop
git pull origin develop

# Prove CloudKit is gone from source
./scripts/verify-no-cloudkit.sh
# or: git grep -n 'CKContainer\|CloudKit Manager\|iCloud.apple.academy.fashionapp' || echo clean
```

Then in Xcode:

1. **Product → Clean Build Folder** (hold Option if needed)
2. Quit Xcode
3. Delete DerivedData for this project:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/fashionapp-*
   ```
4. On the iPhone: **delete the Sylyo / fashionapp app** (old CloudKit cache lives there)
5. Reopen `fashionapp.xcodeproj`, select the iPhone, **Run**

You should see Firebase bootstrap logs instead of `CloudKit Manager`.

## What replaced CloudKit

| Old | New |
|---|---|
| `iCloudAuthManager` | Firebase Auth |
| `Outfit.swift` CloudKit manager | `FirebaseWardrobeRepository` |
| Container `iCloud.apple.academy.fashionapp` | Firestore `users/{uid}/wardrobeItems` |

## WeatherKit JWT errors (`Code=2`)

`WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors Code=2` is **not a code bug**. Location works; Apple refuses to mint a WeatherKit JWT.

For team `T76V4FRBSW` / bundle `apple.academy.stylo` you must enable WeatherKit in **two** places on the App ID:

1. [Apple Developer → Identifiers](https://developer.apple.com/account/resources/identifiers/list) → `apple.academy.stylo`
2. **Capabilities** tab → enable **WeatherKit** → Save
3. **App Services** tab → enable **WeatherKit** → Save *(often missed)*
4. In Xcode: Signing & Capabilities → confirm WeatherKit is present
5. Product → Clean Build Folder, delete the app from the device, Run again (forces a fresh provisioning profile)

Until that is done, Discover shows a weather error with retry; the rest of the app still works.

## Firebase launch warnings

A one-shot `I-COR000003` / Analytics “started” line can appear while the SDK loads; Sylyo configures Firebase in `AppDelegate.init` and again in `didFinishLaunching`. After a clean pull + rebuild you should see `✅ Firebase configured for project: sylyo-fashion`. The IDFA / `GoogleAppMeasurementIdentitySupport` line is expected unless you link AdSupport for ads.
