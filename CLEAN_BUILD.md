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

## WeatherKit JWT errors

`WeatherDaemon.WDSJWTAuthenticatorServiceListener` is **not CloudKit**. It means the App ID needs WeatherKit enabled in the Apple Developer portal for team `T76V4FRBSW` / bundle `apple.academy.stylo`. The app still runs; weather just falls back until that capability is active.
