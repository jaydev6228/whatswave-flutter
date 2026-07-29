# Backend integration plan

## Objective

Keep the Flutter app ready for:

- Firebase-first delivery
- AWS-backed services when scale or custom requirements demand it
- A mixed architecture where auth, data, media, and calling do not need to come from one vendor

## Phase order

### Phase A: demo and local-first

- Demo repositories
- Local state only
- No remote dependency

### Phase B: Firebase-first MVP

- Firebase Authentication
- Cloud Firestore
- Cloud Storage
- Firebase Cloud Messaging
- Crashlytics and Analytics

### Phase C: AWS or mixed scale path

- Cognito or custom auth broker
- API Gateway / Lambda or container APIs
- DynamoDB, Aurora, or custom data stores
- S3 media strategy
- CloudFront or another CDN
- KMS and WAF policies

## Repository contracts to keep stable

- `AuthRepository`
- `UserRepository`
- `ChatRepository`
- `MessageRepository`
- `GroupRepository`
- `StatusRepository`
- `ChannelRepository`
- `CommunityRepository`
- `CallRepository`
- `MediaRepository`
- `NotificationRepository`
- `SettingsRepository`

## Rules

1. UI should not import Firebase or AWS SDKs directly.
2. Repository contracts should expose domain models, not backend DTOs.
3. Media upload and download should use a dedicated abstraction.
4. Push registration should be isolated behind a notification service.
5. Calling invite signaling should not depend on UI routes.

## Firebase-first checklist

1. Add FlutterFire CLI setup
2. Create `firebase_options.dart`
3. Wire auth and session restore
4. Add chat and message repositories
5. Add media upload/download
6. Add FCM token sync
7. Add Crashlytics and Analytics

## AWS escalation triggers

Consider AWS or mixed infra when:

- Firestore cost or indexing model becomes a problem
- You need stronger custom moderation and API layers
- You need custom message fanout or event pipelines
- You need region-specific compliance controls
- You want vendor independence for media, calling, or abuse prevention

## Recommendation

Start with Firebase for speed, but keep repository and service boundaries strict enough that high-cost or high-risk services can move later without rewriting presentation code.

## Current scaffold in code

- Runtime-selected repository bundles now choose the default auth, chat, updates, communities, and calls adapters from one Phase 8 factory instead of hard-wiring local fakes inside the app shell.
- Repository readiness is surfaced feature-by-feature in the backend sync screen, including whether the active adapter is fully local or a Firebase/AWS scaffold still using local fallback data.
- Repository actions are already tracked through non-blocking integration wrappers.
- Push token sync now sits behind an injectable service contract with a local default implementation.
- Media upload completion now sits behind an injectable service contract with a local default implementation.
- The settings backend screen exposes provider readiness, setup guidance, and active local adapters so real Firebase wiring can replace local defaults incrementally.
- Runtime backend flags now let the app switch between `local`, `firebase`, and `aws` scaffolding modes without rewriting the feature screens.
- Firebase-first scaffold services now surface missing setup directly in the backend sync screen, including `firebase_options.dart`, native config files, storage, FCM, APNs, analytics, crash reporting, and call-provider readiness.
