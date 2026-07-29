# Machine Setup And Bootstrap

## Goal

Use this checklist to move the project to a new Mac or another development machine and get back to a known-good state quickly.

## Recommended baseline

Install or verify:

- Flutter stable
- Xcode
- CocoaPods
- Android Studio or Android SDK tools
- JDK 17
- A working Android emulator
- At least one iOS simulator

The last known-good snapshot from this machine was:

- Flutter `3.44.1`
- Dart `3.12.1`
- Xcode `26.1`
- CocoaPods `1.16.2`
- Android SDK `36.0.0`
- JDK `17.0.12`

## Project copy strategy

This project currently lives in a generated Codex outputs directory.

Recommended on the new machine:

1. Copy the full `whatswave_flutter` folder to a normal workspace location.
2. If you want source control, initialize a real git repository there.
3. Keep the folder name stable if other scripts or docs refer to it.

## First run checklist

From the Flutter project root:

```bash
flutter pub get
flutter doctor -v
flutter analyze
flutter test
```

If those pass, confirm devices:

```bash
flutter devices
```

Then run the app:

```bash
flutter run -d "iPhone 17 Pro"
flutter run -d emulator-5554
```

If those exact device names do not exist on the new machine, use equivalent iOS and Android targets.

## Recommended local QA device matrix

Keep at least one compact and one larger device in mind during development:

- iOS compact: `iPhone SE (3rd generation)`
- iOS large: `iPhone 17 Pro`
- Android compact: `Small_Phone`
- Android medium: `Medium_Phone_API_35`

## Local runtime modes

Current defaults favor safe local development.

Useful run commands:

```bash
flutter run -d emulator-5554
```

```bash
flutter run -d emulator-5554 --dart-define=WW_DEMO_RESTORE_SESSION=true
```

```bash
flutter run -d emulator-5554 --dart-define=WW_ENABLE_DEMO_SURFACES=false
```

```bash
flutter run -d emulator-5554 --dart-define=WW_BACKEND_TARGET=firebase --dart-define=WW_APP_ENV=development
```

## Important local constraints inherited from this machine

- This PC could not create a Firebase project because of local policy and protocol limits
- The current codebase is therefore prepared for Firebase but not yet bound to a live Firebase project
- Another machine should handle Firebase project creation, CLI login, and any production secret management

## If iOS simulator launch fails

Run:

```bash
flutter doctor -v
flutter clean
flutter pub get
flutter run -d "iPhone 17 Pro"
```

If Flutter cache lock issues appear:

```bash
rm -f <your_flutter_sdk>/bin/cache/lockfile
```

If Flutter SDK permissions are broken, repair them on the new machine before continuing.

## If Android build fails

Verify the configured JDK:

```bash
flutter config --jdk-dir /Library/Java/JavaVirtualMachines/jdk-17.jdk/Contents/Home
flutter doctor -v
```

## Current dependency profile

Core packages already in use:

- `shared_preferences`
- `permission_handler`

Firebase packages are not yet added to `pubspec.yaml`.

That is intentional until a new machine can create or connect to a Firebase project.

## Recommended first read after setup

Once the app boots on the new machine, read:

1. `docs/handoff/05_development_guardrails.md`
2. `docs/handoff/06_testing_and_qa.md`
3. `docs/handoff/03_firebase_dev_setup.md`
