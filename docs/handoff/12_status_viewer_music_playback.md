# Status Viewer Music Playback

## What changed

- Added viewer-side playback for saved status music tracks in:
  - `lib/features/updates/presentation/status_story_viewer_screen.dart`
- Posted photo/video statuses that carry `segment.musicTrack.previewAssetPath` now try to auto-play that saved track when the viewer opens.
- Hold-to-pause now pauses the saved music too.
- Releasing hold resumes the saved music too.
- Segment changes and closing the viewer now dispose the music controller so audio does not leak across stories.
- For video segments with a selected music track, the viewer now prioritizes the saved music track by muting the local video audio path.

## Why

- Before this patch, the composer could preview music and the segment persisted `musicTrack`, but the posted-story viewer never started playback for that saved track.
- This created a visible music banner with no audible result after posting.

## Test coverage

- Added a viewer regression that opens a music-backed status and verifies the viewer path stays stable:
  - `test/features/updates/presentation/status_story_viewer_screen_test.dart`

## Verification completed

- `flutter test --no-pub test/features/updates/presentation/status_story_viewer_screen_test.dart -r expanded`
- `flutter analyze --no-pub`
- `flutter test --no-pub`
- Launched latest build on:
  - `CFB18B74-0E88-401A-B814-2857E33A51A5`
  - `12CEFA54-0950-48B4-8481-76E8ABBFA4E5`
  - `emulator-5554`
