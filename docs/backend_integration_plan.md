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

1. [x] Add FlutterFire CLI setup
2. [x] Create `firebase_options.dart`
3. [x] Wire auth and session restore -- `FirebaseAuthRepository`
4. [x] Add chat and message repositories -- `FirestoreChatRepository`
5. [x] Add status/updates and communities repositories -- `FirestoreUpdatesRepository`, `FirestoreCommunitiesRepository` (not originally itemized here, but followed the same pattern)
6. [ ] Add media upload/download -- deliberately deferred; status media stays device-local rather than Cloud Storage, to avoid requiring the Blaze billing plan (see `docs/handoff/03_firebase_dev_setup.md`)
7. [x] Add FCM token sync -- `FirebaseMessagingPushRegistrationService` (real token registration; sending pushes still needs a Cloud Function, which needs Blaze; iOS Simulators can't obtain a real APNs token at all -- see the class doc comment)
8. [x] Add Crashlytics and Analytics -- `FirebaseAppTelemetry` (crash capture/upload confirmed working; automatic dSYM symbolication disabled, see the class doc comment for why)
9. [x] Add real device contacts (not originally itemized here) -- `DeviceContactsService`/`NativeDeviceContactsService`, matched against registered accounts via a `phoneDirectory` collection

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

## Phase B progress

Auth, chats, updates, and communities are no longer scaffolds -- they run against real Firebase services when `WW_BACKEND_TARGET=firebase`:

- **Auth**: `FirebaseAuthRepository` (`lib/features/auth/data/firebase_auth_repository.dart`) -- real phone/OTP verification via `firebase_auth`, session persistence, profile fields stored via `updateDisplayName` + a local `about` field in `SharedPreferences` (no Firestore user-profile collection yet).
- **Chats**: `FirestoreChatRepository` (`lib/features/chats/data/firestore_chat_repository.dart`) -- `chatThreads/{id}` documents with a `messages` subcollection, gated by a `participantUids` array in both the query and `firestore.rules`.
- **Updates**: `FirestoreUpdatesRepository` (`lib/features/updates/data/firestore_updates_repository.dart`) -- one `statusStories/{uid}` document per user (leverages `StatusStory.toJson()`/`fromJson()`, which already serialized the entire nested segment/overlay/transform model). Media stays local (see the checklist above).
- **Communities**: `FirestoreCommunitiesRepository` (`lib/features/communities/data/firestore_communities_repository.dart`) -- communities are real Firestore documents; contacts are real device contacts via `DeviceContactsService`, fetched once per repository instance and cached to preserve session mutations.
- **Contacts**: `DeviceContactsService`/`NativeDeviceContactsService` (`lib/features/communities/data/device_contacts_service.dart`) -- wraps `flutter_contacts`. "On WhatsWave" status comes from checking each contact's `phoneMatchKey` (see `core/utils/phone_number_matching.dart`, a deliberately approximate trailing-digits comparison) against a `phoneDirectory` collection that `FirebaseAuthRepository` populates on profile save.
- **Push**: `FirebaseMessagingPushRegistrationService` (`lib/core/integrations/backend_integration_bundle.dart`) -- replaces the old scaffold behind the pre-existing `PushRegistrationService` seam. Requests notification permission, fetches a real FCM token, writes it to `pushTokens/{uid}`. Only registers the token -- sending pushes needs a Cloud Function (Blaze), and iOS Simulators can't obtain a real APNs token at all regardless of billing plan.
- **Observability**: `FirebaseAppTelemetry` (`lib/core/observability/firebase_app_telemetry.dart`) -- a decorator around the existing `LocalAppTelemetry`, additionally forwarding errors to Crashlytics and screen views/interactions to Analytics. `main.dart` picks it over `LocalAppTelemetry` based on `WW_BACKEND_TARGET`, before `bootstrap()` runs. Crash capture/upload verified manually; automatic dSYM symbolication is disabled (see the class doc comment for the Swift Package Manager path issue that caused).

Each repository/service documents its own scope decisions and known gaps in a class-level doc comment -- read those directly for the most current, precise picture rather than this summary.

- **Calls (Slice A)**: `LiveKitTestScreen` (`lib/features/calls/presentation/livekit_test_screen.dart`) -- a debug-only screen, reachable from Settings -> Backend and sync -> Debug tools, that connects to a real LiveKit Cloud room using a manually generated test token and enables local camera/mic. Verified manually: room connection and mic track publish succeed; camera track creation throws on the iOS Simulator (no real `AVCaptureDevice`, a hardware limitation, not a bug) and is now caught as a non-fatal warning rather than aborting the connection. Deliberately **not** wired into `CallsController`, which still runs its Timer-based simulation.
- **Calls (Slice B1 -- token server)**: `server/livekit-token` -- a standalone Node/Vercel serverless function that mints real per-user LiveKit access tokens. Avoids needing a Firebase Cloud Function (Blaze) by verifying the caller's Firebase ID token with `firebase-admin` and deploying to Vercel's free tier instead. Verified end-to-end against the live deployment with a real ID token -- see `server/livekit-token/README.md` for the two dependency bugs (`firebase-admin` v14's modular API, a `jose`/ESM crash inside `jwks-rsa`) hit and fixed while doing that verification.
- **Calls (Slice B2 -- Firestore signaling)**: `CallSignalingService`/`FirestoreCallSignalingService` (`lib/features/calls/data/`) -- a new `calls/{callId}` Firestore collection lets one device notify another that a call is happening (ringing/accepted/declined/ended), independent of media. A debug-only `CallSignalingTestScreen` (Settings -> Backend and sync -> Debug tools -> "Test call signaling") exercises it directly. **Verified with a real two-device test** (iOS Simulator + a physical Android phone, two separate Firebase accounts): placing a call from one device surfaced it live on the other within ~1-2 seconds, and accept/status changes synced back correctly. Needed a composite Firestore index (documented in `firestore.indexes.json`) and an Android build fix (`google-services` plugin bumped to 4.5.0 -- the version FlutterFire CLI had pinned was too old for the already-present Crashlytics Gradle plugin). Not yet wired into `CallsController` -- that's B3.

Still fully local/simulated: **Calls beyond Slice B2** (own roadmap in `docs/calling_strategy.md`), **Settings/preferences** (no reason to move these to a backend yet). **Media/Storage** and **sending pushes** (as opposed to registering for them) are both blocked on the Blaze billing upgrade.
