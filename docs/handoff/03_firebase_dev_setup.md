# Firebase Dev Setup

## Goal

Connect the Flutter app to a temporary development Firebase project on a new machine, without introducing production secrets or breaking the current local fallback architecture.

## What is already prepared in code

The codebase is ready for a Firebase-first path in these ways:

- runtime backend mode selection exists
- repository bundle selection exists
- push registration and media transfer seams exist
- settings already expose backend and sync readiness
- local seeded fallback remains stable while Firebase adapters are added incrementally

Read these existing docs first:

- `docs/backend_integration_plan.md`
- `docs/release_readiness.md`
- `docs/handoff/01_project_state.md`

## Current dev app identifiers

Use these for the dev Firebase app registrations unless you intentionally rename the app on the new machine first:

- iOS bundle ID: `com.tsjaydevra.whatswave`
- Android package name: `com.tsjaydevra.whatswave`

These are already in the Flutter project.

## Important rule

Do not create the dev Firebase project on this machine.

Create it on the new machine or any machine that allows:

- Google login
- Firebase console access
- CLI authentication
- downloading config files

## Safe items that can be shared with the project

These are acceptable in the client repo for development:

- `google-services.json`
- `GoogleService-Info.plist`
- `firebase_options.dart`
- Firebase project ID

Do not store these in the project:

- service account JSON keys
- Firebase Admin private keys
- CI deploy tokens
- backend-only credentials

## Firebase console setup checklist

1. Create a new Firebase project for development only.
2. Add an Android app using package name `com.tsjaydevra.whatswave`.
3. Download `google-services.json`.
4. Add an iOS app using bundle ID `com.tsjaydevra.whatswave`.
5. Download `GoogleService-Info.plist`.
6. Enable the first required Firebase products:
   - Authentication
   - Firestore
   - Storage
   - Cloud Messaging
7. If phone auth is part of the first slice:
   - enable Phone sign-in
   - add test phone numbers
   - add Android debug SHA values

## File placement in this repo

Place the native config files here:

- Android: `android/app/google-services.json`
- iOS: `ios/Runner/GoogleService-Info.plist`

## CLI setup on the new machine

Install the CLIs on the new machine:

```bash
npm install -g firebase-tools
dart pub global activate flutterfire_cli
```

Log in:

```bash
firebase login
```

Then from the Flutter project root:

```bash
flutterfire configure
```

Expected result:

- `lib/firebase_options.dart` is generated
- Android Gradle integration is updated as needed
- selected Firebase apps are linked to the Flutter project

Re-run `flutterfire configure` any time you add a new Firebase service or start supporting another platform.

## Recommended package-add order

Do not add every Firebase package at once.

Recommended slice order:

1. `firebase_core`
2. `firebase_auth`
3. `cloud_firestore`
4. `firebase_storage`
5. `firebase_messaging`
6. `firebase_crashlytics`
7. `firebase_analytics`

Choose compatible latest stable package versions on the new machine.

## Recommended code integration order

### Slice 1: core bootstrap

- add `firebase_core`
- generate `firebase_options.dart`
- initialize Firebase in app bootstrap
- keep the default backend mode local until the Firebase path is verified

### Slice 2: auth

- create a Firebase-backed `AuthRepository`
- keep the existing local repository as fallback
- support phone auth test numbers first
- bind the repository bundle so Firebase mode can pick the Firebase auth adapter

### Slice 3: chats and updates

- create Firestore-backed adapters for:
  - chat threads
  - chat messages
  - story metadata
  - channels if desired
- keep presentation code unchanged
- use repository contracts and tracked wrappers

### Slice 4: media uploads

- connect the existing media transfer seam to Firebase Storage
- preserve the current failure and retry semantics
- confirm full-screen viewers still work with remote media metadata

### Slice 5: push

- add `firebase_messaging`
- request notification permissions using existing platform-aware UX
- map APNs token and FCM token registration into the existing push service seam
- do not treat FCM setup as complete until server-side token registration also exists

### Slice 6: observability

- wire Crashlytics and Analytics behind the current telemetry seam
- keep local telemetry useful for debug builds
- ensure consent and privacy requirements are considered before analytics rollout

## Recommended runtime flags during Firebase dev

Use these flags while the Firebase dev project is being wired:

```bash
flutter run -d emulator-5554 \
  --dart-define=WW_BACKEND_TARGET=firebase \
  --dart-define=WW_APP_ENV=development
```

Once files and setup are actually present, update readiness flags while testing:

- `WW_FIREBASE_PROJECT_ID`
- `WW_FIREBASE_OPTIONS_READY=true`
- `WW_IOS_FIREBASE_CONFIG_READY=true`
- `WW_ANDROID_FIREBASE_CONFIG_READY=true`
- `WW_FIREBASE_AUTH_READY=true`
- `WW_FIRESTORE_READY=true`
- `WW_FIREBASE_STORAGE_READY=true`
- `WW_FCM_READY=true`
- `WW_APNS_READY=true`

## Phone auth testing notes

Development recommendation:

- use Firebase test phone numbers first
- avoid real SMS during early adapter work
- confirm Android SHA setup before debugging real phone-auth issues

Important product note:

- phone numbers used for Firebase phone auth involve abuse-prevention handling by Google, so final product rollout needs explicit consent and privacy review

## Firebase-specific manual QA after first integration

1. App launches with Firebase initialization enabled
2. Existing local mode still works if Firebase flags are off
3. Dev Firebase mode boots without crashes
4. Test phone auth works with Firebase test numbers
5. Chat fetch and send works from Firestore adapter
6. Status creation works with Firestore and Storage
7. Notification permission flow still behaves cleanly on both iOS and Android
8. Backend and sync screen shows meaningful readiness instead of stale scaffold state

## Official docs to verify on the new machine

- Firebase Flutter setup:
  - https://firebase.google.com/docs/flutter/setup
- Firebase Android setup:
  - https://firebase.google.com/docs/android/setup
- Firebase iOS setup:
  - https://firebase.google.com/docs/ios/setup
- Firebase phone auth for Flutter:
  - https://firebase.google.com/docs/auth/flutter/phone-auth
- Firebase Cloud Messaging:
  - https://firebase.google.com/docs/cloud-messaging

## What not to do

- do not mix production and development Firebase projects
- do not add private backend credentials to the app repo
- do not bypass repository contracts by calling Firebase directly from widgets or screens
- do not replace the local fallback path until Firebase flows are stable
