# Test strategy

## Philosophy

Every slice should ship with happy and sad path coverage. "Sad path" means more than exceptions:

- Empty state
- Loading state
- Validation failure
- Permission denied
- Offline state
- Partial data state
- Backend failure state
- Recovery path

## Test layers

### Unit tests

Use for:

- Controllers
- Use cases
- Validators
- Mapper logic
- Repository behavior

### Widget tests

Use for:

- Primary screens
- Important reusable widgets
- Theme behavior
- Navigation shell interactions
- Error and empty states

### Security rules tests

`firestore.rules` and `storage.rules` are the app's real authorization
boundary. Every per-thread read gate, per-field admin check and per-owner
write check lives there rather than in Dart -- a modified client talks to
Firebase directly, so no Dart test can stand in for them.

```bash
npm install        # once
npm run test:rules
```

Runs `test/rules/*.test.mjs` against the Firestore and Storage emulators via
`@firebase/rules-unit-testing`, using the committed `firebase.test.json`
(rules paths and emulator ports only -- no project id or credentials, unlike
the gitignored `firebase.json`). The emulators need a JDK;
`scripts/run-rules-tests.mjs` finds one automatically, including the JDK
Android Studio bundles, so no extra install is normally required.

Cover both directions for every rule: the legitimate operation must be
allowed *and* each way of abusing it must be denied. Asserting only the
denials lets a rule that denies everything pass, and asserting only the
happy path is how the `starredBy` escalation below survived.

What this already caught, on its first run: a participant could write any
uid into a message's `starredBy`, and because the collection-group rule
grants read access to every uid listed there, that handed a **non-participant
read access to that message**. The rule checked only one direction of the set
change, and `hasOnly` on an empty set is vacuously true.

### Integration tests

Add once the Flutter SDK and platform runners are in place:

- Auth flow
- Chat send flow
- Update posting flow
- Simulated call flow
- Settings persistence

## Phase-1 test coverage

The current foundation focuses on:

- App preferences controller
- Root app shell
- Story ring widget
- Settings screen presence and interaction scaffolding

## Expected future matrix

For each feature:

1. Happy path
2. Validation failure
3. Loading state
4. Empty state
5. Backend failure
6. Retry or recovery
