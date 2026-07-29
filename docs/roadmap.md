# Roadmap

## Phase 1: foundation and architecture

### Goal

Stand up the new Flutter repository with a strong structure, design system, and shared shell.

### Subtasks

1. Create repo structure and base Flutter files
2. Write architecture, roadmap, and testing docs
3. Build light and dark theme foundations
4. Build a sample app shell with the target tabs
5. Add representative sample UI for chats, updates, calls, communities, and settings
6. Add tests for the current foundation

### Exit criteria

- Repo is understandable without the Swift project
- The app shell communicates the intended product direction
- Theme support exists for both light and dark mode
- The next feature slice can be implemented without refactoring the whole repo

## Phase 2: auth and session

### Subtasks

1. Splash/session restore flow
2. Phone entry and OTP request screen
3. OTP verification screen
4. Profile bootstrap flow
5. Auth controller and validation tests
6. Success, loading, empty, and error UI states

## Phase 3: chats

### Subtasks

1. Chat filters, search, and archive
2. Conversation thread screen
3. Message grouping and delivery/read states
4. Message composer with emoji, media, and voice-note entry points
5. Attachment preview and fullscreen viewer
6. Happy and sad path widget/unit tests

## Phase 4: updates

### Subtasks

1. Story ring treatment
2. My status card and composer
3. Recent and viewed sections
4. Story viewer shell
5. Channels/discovery surface
6. Empty, loading, and error states

## Phase 5: calls

### Subtasks

1. Calls list and favorites
2. Simulated outgoing audio/video flows
3. Simulated incoming call surfaces
4. Active call UI states
5. Permissions UX
6. Call history and edge-state tests

## Phase 6: communities and contacts

### Subtasks

1. Communities landing page
2. Group and announcement previews
3. Contacts list and invite/share flow
4. Search/filter states
5. Empty states and permission denials

## Phase 7: settings, profile, and security

### Subtasks

1. WhatsApp-style profile page
2. Preferences persistence
3. Theme preference
4. App lock UI
5. Privacy options
6. Unit and widget tests for happy/sad scenarios

## Phase 8: backend and platform integrations

### Subtasks

1. Repository contracts and fake implementations alignment
2. Firebase-first adapters
3. AWS-compatible adapter boundaries
4. Push notifications and token sync
5. Media upload pipeline
6. Real calling provider integration

## Phase 9: hardening

### Subtasks

1. Offline resilience
2. Performance profiling
3. Analytics and crash hooks
4. Release configuration
5. Test matrix expansion
6. CI and quality gates
