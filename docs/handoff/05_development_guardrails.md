# Development Guardrails

## Scope rule

Work only in the Flutter project:

- active project: `outputs/whatswave_flutter`

Do not modify the separate native Swift iOS app outside this folder unless explicitly instructed.

Editing the Flutter `ios/` and `android/` runner folders is allowed when required for Flutter-native integration work.

## UX and product quality bar

The product owner strongly prefers:

- smooth UX over rough prototype behavior
- WhatsApp-like polish rather than generic demo UI
- compact-device support
- light and dark mode parity
- animation and transitions that feel stable

This means every UI change should be judged on:

- small iPhone screens
- larger iPhone screens
- small Android screens
- medium Android screens
- both themes

## Mandatory validation habit

After meaningful UI or behavior changes:

1. run `flutter analyze`
2. run `flutter test`
3. launch on at least one iOS simulator
4. launch on at least one Android emulator
5. manually spot-check the changed flow

This is not optional for feature work.

## Release and TestFlight rule

Testing shortcuts, seeded sessions, previews, and demo-only surfaces must not affect production release behavior.

Important flags:

- `WW_ENABLE_DEMO_SURFACES`
- `WW_DEMO_RESTORE_SESSION`

Release expectation:

- non-release local testing conveniences are acceptable in debug
- production and TestFlight builds must ignore those shortcuts

## Architecture guardrails

- UI code should not import Firebase or AWS SDKs directly
- repository contracts should remain the main seam
- service seams should isolate push, media, and call transport concerns
- tracked repository wrappers should remain useful even after live adapters are added
- keep local fallback implementations available until live adapters are proven

## Calling guardrails

- do not let screen code know which calling provider is used
- keep signaling, media, permissions, and device-routing concerns separate
- preserve current clean call UI direction when real calling is added
- real calling should come after backend auth and push paths are stable

## Security guardrails

- never commit server-side secrets
- do not store service account keys in the client repo
- prefer environment-separated dev and prod setup
- treat push tokens, auth tokens, and user metadata carefully
- final production release still needs abuse prevention, moderation, and stronger backend controls

## Coding style guardrails

- keep changes small and scoped when possible
- preserve the current feature folder structure
- add tests with new feature behavior
- prefer extending existing controllers and repository seams instead of bypassing them
- do not introduce backend DTO leakage into widgets or controllers

## Persistence and testing behavior

Current local behavior intentionally persists test session state so repeated OTP and profile setup are not required during local testing.

Keep that useful in debug and local development.

If changing auth or session behavior:

- do not break the local persisted testing flow without a replacement
- ensure release behavior still makes sense once live auth is added

## Documentation expectation

When major work lands, update:

- `README.md`
- relevant docs under `docs/`
- the backend or release docs if the change affects infrastructure or rollout

## Current known caution areas

- app lock and lifecycle behavior
- call UI polish across themes and sizes
- chat thread scroll and composer behavior
- story progress behavior and viewed-state logic
- backend sync screen accuracy as live adapters replace scaffolds

These areas deserve extra care during future refactors.
