# Architecture

## Product goal

Build a WhatsApp-style cross-platform app in Flutter that covers:

- Auth and onboarding
- 1:1 chats and groups
- Updates/status and story-style viewing
- Audio and video calling
- Communities and channels
- Contacts and invites
- Settings, profile, privacy, and app lock
- Attachment sharing and fullscreen viewers
- Light and dark mode
- Local persistence and future Firebase/AWS integration

## Guiding principles

1. Keep the Flutter codebase independent of the existing Swift iOS app.
2. Build in small vertical slices instead of one large rewrite.
3. Keep feature boundaries clear so Firebase-first and AWS-heavy backends can both fit later.
4. Separate demo/sample implementations from production adapters.
5. Treat tests as part of each slice, not a cleanup step at the end.

## Folder strategy

```text
lib/
  app/
    theme/
    shell/
    bootstrap/
  core/
    controllers/
    models/
    sample/
    services/
    utils/
  features/
    auth/
    chats/
    chat_room/
    updates/
    communities/
    calls/
    contacts/
    settings/
```

## Layering

Each feature grows through the same layered shape:

### Presentation

- Screens
- Feature widgets
- Local screen controllers
- View-state formatting

### Application

- Use cases
- Coordinators
- Feature orchestrators
- Validation and feature-level policies

### Domain

- Entities
- Value objects
- Repository contracts
- Domain rules

### Data

- Local repositories
- Remote repositories
- DTO mappers
- Cache and sync adapters

### Platform

- Camera/gallery
- Biometrics
- Notifications
- Contacts
- Audio/video SDK bridge
- CallKit and Android telecom integrations

## Navigation model

The long-term shell follows five main tabs:

1. Chats
2. Updates
3. Communities
4. Calls
5. Settings

Additional flows sit above the shell:

- Splash/session restore
- Auth/onboarding
- Conversation thread
- Media viewer
- Story viewer
- Compose/update creation
- Incoming and active call surfaces
- Profile, privacy, and feature detail pages

## State model

The phase-1 implementation keeps things simple:

- App-wide preferences controller for theme and shell-level preferences
- Demo data for feature previews
- Local widget state where possible

As features grow, repositories and use cases should own business state and screen controllers should expose only view-state.

## Data strategy

### Phase 1

- In-memory sample data
- No backend dependency
- No plugin dependency beyond Flutter SDK

### Phase 2+

- Local-first repositories
- Firebase or AWS-backed remote adapters
- Offline cache and sync policy
- Media upload/download abstraction
- Push and call invite delivery adapters

## Backend contract plan

The app should never depend directly on Firebase widgets or AWS clients inside presentation code.

Instead:

- `AuthRepository`
- `ChatRepository`
- `MessageRepository`
- `UpdatesRepository`
- `CallRepository`
- `CommunityRepository`
- `ContactsRepository`
- `SettingsRepository`
- `MediaRepository`
- `NotificationRepository`

Demo implementations live beside the architecture while production adapters plug in later.

## Calling strategy

Calling should be designed behind adapters from the start:

- `CallSignalingService`
- `CallMediaService`
- `CallPermissionsService`
- `CallHistoryRepository`

That keeps the app free to use:

- WebRTC with self-managed infrastructure
- LiveKit
- Stream
- Twilio
- Another provider

## Security shape

Planned cross-platform security layers:

- Secure token/session storage
- App lock and biometric gate
- Attachment access policy
- Push token registration and rotation
- Abuse/rate-limit aware API boundaries
- Event logging with redaction

## Test strategy

Every feature slice should add:

- Unit tests for use cases, controllers, and validators
- Widget tests for happy and sad rendering states
- Repository tests for demo and production adapters
- Golden or screenshot tests for stable design-critical widgets when the SDK is available

## Milestone map

### Phase 1: foundation

- Repo structure
- Theme system
- App shell
- Sample data
- Roadmap and docs

### Phase 2: auth

- Session gate
- Phone/OTP screens
- Validation
- Error states

### Phase 3: chats

- Chat list
- Conversation screen
- Composer
- Attachments
- Fullscreen preview

### Phase 4: updates

- Story ring UI
- Viewer
- Composer
- Expiry rules

### Phase 5: calls

- Call list
- Simulated audio/video surfaces
- Permissions and invite flow

### Phase 6: communities and contacts

- Communities landing page
- Announcement and group previews
- Contacts discovery, permissions, and invite flows
- Search, filters, and empty states

### Phase 7: settings

- Profile page
- Preferences persistence
- App lock
- Storage and privacy settings

### Phase 8: integrations

- Firebase/AWS adapters
- Push
- Media upload
- Real call provider

### Phase 9: hardening

- Expanded tests
- Performance tuning
- Analytics and crash reporting
- Release automation
