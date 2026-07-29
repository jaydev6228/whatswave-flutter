# Story Frame First Paint

## What changed

- Updated `MediaStatusComposerScreen` so it can accept an `initialSourceSizeHint`.
- The composer now seeds the media frame from that hint on the first build, which keeps a newly selected image closer to its original aspect ratio immediately instead of waiting for the image widget to resolve size later.
- `UpdatesScreen` now resolves an initial size hint for picked photos before pushing the composer.
- Frame syncing was tightened so if the first hint and the later resolved size differ slightly, the composer keeps the frame aligned with the original media ratio as long as the user has not already changed the frame manually.
- Frame editing now has an explicit cancel/back path that restores the pre-edit frame state instead of forcing the user to post or close the full composer.
- `StatusStoryMediaSurface` now keeps the frame container visible even when media is unavailable, which makes fallback behavior and tests more predictable.

## Files touched

- `lib/features/updates/presentation/media_status_composer_screen.dart`
- `lib/features/updates/presentation/updates_screen.dart`
- `lib/features/updates/presentation/widgets/status_story_media_surface.dart`
- `test/features/updates/presentation/media_status_composer_screen_test.dart`

## Verification completed

- `flutter test --no-pub test/features/updates/presentation/media_status_composer_screen_test.dart -r expanded`
- `flutter analyze --no-pub`
- `flutter test --no-pub`
- Launched current build on:
  - `CFB18B74-0E88-401A-B814-2857E33A51A5`
  - `12CEFA54-0950-48B4-8481-76E8ABBFA4E5`
  - `emulator-5554`

## Notes

- Android still prints the existing emulator / rendering noise during detach, but the app built, installed, and launched successfully.
- The new first-paint frame behavior is production-oriented and not a test-only code path.
