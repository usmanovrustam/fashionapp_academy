# AGENTS.md

## Cursor Cloud specific instructions

### What runs where
This repo is the **Sylyo** native **iOS / SwiftUI** app (`fashionapp.xcodeproj`) plus its Firebase backend
config. The cloud VM is **Linux**, so the iOS app itself **cannot be built or run here** — that requires
macOS + Xcode with the iOS 27 SDK (see `README.md`). Do not attempt `xcodebuild`/`swift build` on this VM.

The part of the product that **is** runnable/testable on Linux is the **Firebase backend layer**
(Authentication + Cloud Firestore + Cloud Storage security rules), via the **Firebase Emulator Suite**.
Java (required by the Firestore/Storage emulators) and the `firebase` CLI are present after the update script runs.

### Running the Firebase emulators (backend dev/testing)
```bash
firebase emulators:start --project demo-sylyo --only auth,firestore,storage
```
- Use a `demo-` prefixed project id (e.g. `demo-sylyo`) so the emulators run **fully offline** with no
  Firebase login / credentials. Using the real project id (`sylyo-fashion` from `.firebaserc`) would try to
  reach live Firebase.
- Ports come from `firebase.json`: Auth `9099`, Firestore `8080`, Storage `9199`, Emulator UI `4000`.
- First `emulators:start` downloads emulator jars/zips; they are cached afterward.
- The emulators load `firestore.rules` and `storage.rules` automatically, so they are the right way to
  validate rules changes.

### Non-obvious gotchas
- The iOS app is **not wired to the emulators** — `Infrastructure/.../FirebaseBootstrap.swift` just calls
  `FirebaseApp.configure()`, so a real device/simulator build talks to **live Firebase**. The emulators are
  for validating backend rules/behavior, not for running the app.
- npm's default global prefix on this VM is root-owned (`/`), so `npm install -g ...` fails with EACCES
  unless the prefix points at the writable nvm dir. The update script fixes this; if you install other global
  npm tools manually, do the same.
- To exercise Auth + Firestore + rules end-to-end, drive the emulators with the Firebase **Web SDK**
  (`connectAuthEmulator` / `connectFirestoreEmulator`) from a throwaway Node script; the unauthenticated
  Firestore REST endpoint returns `PERMISSION_DENIED`, which is expected (owner-only rules).

### Standard setup / deploy commands
See `README.md` (app build in Xcode) and `FIREBASE_SETUP.md` (Firebase/BigQuery console steps and
`firebase deploy --only firestore:rules,firestore:indexes,storage`). `scripts/fetch-google-service-info.sh`
pulls `GoogleService-Info.plist` and requires `firebase login` first.
