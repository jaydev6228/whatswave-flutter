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
