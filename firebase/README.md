# ClearWash POS — Firebase Setup & Environment Guide

This directory holds the Cloud Firestore schema, security rules, composite indexes, and project alias templates for **ClearWash POS** across **dev** and **prod** environments.

---

## 1. Firebase Environments (`dev` & `prod`)

| Alias | Firebase Project ID | Compile-time Flag | Purpose |
| :--- | :--- | :--- | :--- |
| `dev` (default) | `clearwash-pos-dev` | `--dart-define=APP_ENV=dev` | Local QA, emulator/staging testing, demo terminals |
| `prod` | `clearwash-pos-prod` | `--dart-define=APP_ENV=prod` | Live outlet POS handhelds and production Firestore |

In Dart, [`AppEnvironment.fromDefine()`](../lib/firebase/firebase_options.dart) reads `APP_ENV` (defaulting to `'dev'`) and [`DefaultFirebaseOptions.currentPlatform`](../lib/firebase/firebase_options.dart) resolves `DefaultFirebaseOptions.dev` or `DefaultFirebaseOptions.prod`.

> **Offline Fallback Safety:** Until live `flutterfire configure` credentials replace the `AIzaSyDummyKey...` stubs in `lib/firebase/firebase_options.dart`, `main.dart` automatically runs ClearWash POS on `InMemoryCarwashRepository` so the app never fails to boot offline.

---

## 2. Project Alias Setup (Firebase CLI)

1. Copy `.firebaserc.example` to `.firebaserc` at the repository root (or inside `firebase/` alongside your `firebase.json`):
   ```bash
   cp firebase/.firebaserc.example .firebaserc
   ```
2. Authenticate and select an environment alias:
   ```bash
   firebase login
   firebase use dev    # targets clearwash-pos-dev
   # or:
   firebase use prod   # targets clearwash-pos-prod
   ```
3. Ensure `firebase.json` points Firestore to the files in `firebase/`:
   ```json
   {
     "firestore": {
       "rules": "firebase/firestore.rules",
       "indexes": "firebase/firestore.indexes.json"
     }
   }
   ```

---

## 3. Deploying Firestore Rules & Indexes

Deploy rules and composite indexes to **dev** first, verify queries, then promote to **prod**:

```bash
# Deploy both rules and composite indexes to dev
firebase deploy --only firestore:rules,firestore:indexes --project dev

# Deploy rules only
firebase deploy --only firestore:rules --project prod

# Deploy composite indexes only
firebase deploy --only firestore:indexes --project prod
```

Verify active index build status in Firebase Console (`Firestore Database -> Indexes`) before rolling out production POS builds.

---

## 4. Generating Live Android Credentials (`FlutterFire CLI`)

When provisioning real Firebase projects, run `flutterfire configure` separately per environment and populate `DefaultFirebaseOptions.dev` and `DefaultFirebaseOptions.prod` in `lib/firebase/firebase_options.dart`:

```bash
flutterfire configure --project=clearwash-pos-dev --platforms=android
flutterfire configure --project=clearwash-pos-prod --platforms=android
```

Keep `AIzaSyDummyKey...` stubs only for unconfigured environments so `main.dart` continues to guard against unconfigured builds.

---

## 5. Switching `APP_ENV=dev|prod` in Flutter

```bash
# Run development build (default)
flutter run --dart-define=APP_ENV=dev

# Run production build
flutter run --dart-define=APP_ENV=prod

# Build release APK / App Bundle for production outlet terminals
flutter build apk --release --dart-define=APP_ENV=prod
flutter build appbundle --release --dart-define=APP_ENV=prod
```
