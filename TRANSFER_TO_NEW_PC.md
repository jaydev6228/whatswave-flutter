# Transfer To New PC

This is the single entry point for handing this Flutter project to another developer, another AI agent, or another machine.

## What to share

Share this whole folder:

- `outputs/whatswave_flutter`

This folder already contains:

- full Flutter source code
- Flutter `ios/` and `android/` runner projects
- architecture docs
- handoff docs
- backend/Firebase/AWS planning docs
- tests
- release-readiness notes

Do not share or rely on the older native Swift iOS project outside this folder unless someone explicitly needs that separate app.

## Best transfer format

Preferred:

1. Share a clean archive of `outputs/whatswave_flutter`
2. On the new PC, extract it anywhere
3. Run `flutter pub get`
4. Run `flutter analyze`
5. Run `flutter test`
6. Launch on one iOS simulator and one Android emulator

If you are not using the archive, you can copy the folder directly.

## Files and folders that matter most

Core project:

- `lib/`
- `test/`
- `assets/`
- `docs/`
- `android/`
- `ios/`
- `pubspec.yaml`
- `pubspec.lock`
- `README.md`
- `analysis_options.yaml`

These are generated or machine-local and do not need to be preserved:

- `build/`
- `.dart_tool/`
- `.DS_Store`
- local Flutter run logs such as `flutter_01.log`

## Read this first on the new machine

Read in this order:

1. `PROJECT_BRIEF_FOR_NEW_DEVELOPER.md`
2. `README.md`
3. `docs/handoff/README.md`
4. `docs/handoff/01_project_state.md`
5. `docs/handoff/02_machine_setup.md`
6. `docs/handoff/05_development_guardrails.md`
7. `docs/handoff/06_testing_and_qa.md`
8. `docs/architecture.md`

If backend work is next, also read:

1. `docs/handoff/03_firebase_dev_setup.md`
2. `docs/handoff/04_aws_path.md`
3. `docs/backend_integration_plan.md`
4. `docs/release_readiness.md`

If another AI agent is taking over, also read:

1. `docs/handoff/07_agent_resume_brief.md`

## Short explanation for another developer or AI

Use this summary:

```text
This project is the Flutter app only, located in outputs/whatswave_flutter.
Do not modify the older native Swift iOS app outside this folder.
The app is locally feature-rich and uses seeded local data by default.
Firebase and AWS seams are scaffolded but not yet connected to live infrastructure.
Read docs/handoff/README.md first, then follow the documented guardrails.
After meaningful changes, run flutter analyze, flutter test, and launch on iOS and Android.
```

## Current working style and coding standard

This project expects:

- clear feature boundaries under `lib/features/`
- repository and service seams between UI and backend providers
- no direct Firebase or AWS SDK usage inside presentation code
- compact-device support
- light and dark mode parity
- smooth UX over rough prototype behavior
- tests added with behavior changes

The detailed rules live in:

- `docs/handoff/05_development_guardrails.md`
- `docs/architecture.md`
- `docs/test_strategy.md`

## Current important constraints

- default runtime remains local seeded mode until live backend setup is ready
- debug/demo shortcuts must not affect release or TestFlight behavior
- current bundle/application identifiers are temporary but usable for development
- real production release still requires live backend, push, calling transport, and security work

## Quick boot on the new machine

From the extracted project folder:

```bash
flutter pub get
flutter analyze
flutter test
flutter devices
flutter run -d "iPhone 17 Pro"
flutter run -d emulator-5554
```

If only one simulator/emulator is available, use any iOS simulator and any Android emulator first, then expand the device matrix later.

## Where the latest transfer package should point

If a clean archive was generated alongside this project, share that archive plus this project path reference:

- project folder: `outputs/whatswave_flutter`

If there is any confusion, the safest instruction is:

- "Open `PROJECT_BRIEF_FOR_NEW_DEVELOPER.md` first, then `TRANSFER_TO_NEW_PC.md`, then follow the handoff bundle in `docs/handoff/`."
