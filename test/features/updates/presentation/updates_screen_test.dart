import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/models/status_story.dart';
import 'package:whatswave/core/models/story_viewer.dart';
import 'package:whatswave/features/updates/application/updates_controller.dart';
import 'package:whatswave/features/updates/data/fake_updates_repository.dart';
import 'package:whatswave/features/updates/data/status_media_store.dart';
import 'package:whatswave/features/updates/data/updates_repository.dart';
import 'package:whatswave/features/updates/presentation/updates_screen.dart';
import 'package:whatswave/features/updates/presentation/widgets/status_story_media_surface.dart';

import '../../../support/device_matrix.dart';

void main() {
  testWidgets(
      'shares a text status and keeps the my-status card subtitle generic',
      (tester) async {
    final controller = UpdatesController(
      repository: FakeUpdatesRepository(latency: Duration.zero),
    );

    await _pumpUpdatesScreen(
      tester,
      device: iphoneSeProfile,
      controller: controller,
    );

    await tester.tap(find.byKey(const Key('updates_my_status_text_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('updates_composer_sheet')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('updates_composer_field')),
      'Night build is ready for review.',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('updates_share_status_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('updates_composer_sheet')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('updates_my_status_card')),
        matching: find.text('Text update'),
      ),
      findsOneWidget,
    );
    expect(find.text('Night build is ready for review.'), findsNothing);
    expect(
        controller.myStatus?.previewText, 'Night build is ready for review.');
  });

  testWidgets(
      'keeps text studio overflow-free while editing on Android small phones',
      (tester) async {
    final controller = UpdatesController(
      repository: FakeUpdatesRepository(latency: Duration.zero),
    );

    await _pumpUpdatesScreen(
      tester,
      device: androidSmallProfile,
      controller: controller,
    );

    await tester.tap(find.byKey(const Key('updates_my_status_text_button')));
    await tester.pumpAndSettle();

    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const Key('updates_composer_sheet')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'story profile cards use compact summaries instead of raw status text',
      (tester) async {
    final controller = UpdatesController(
      repository: FakeUpdatesRepository(latency: Duration.zero),
    );

    await _pumpUpdatesScreen(
      tester,
      device: iphoneSeProfile,
      controller: controller,
    );

    expect(find.text('Late-night launch coffee'), findsNothing);
    expect(find.text('Tokyo sunset timelapse'), findsNothing);
    expect(find.text('Sketchbook dump'), findsNothing);

    expect(find.text('2 new of 3 updates'), findsOneWidget);
    expect(find.text('4 updates'), findsOneWidget);
    expect(find.text('2 viewed updates'), findsOneWidget);
  });

  testWidgets('keeps partially viewed multi-segment stories in recent updates',
      (tester) async {
    final controller = UpdatesController(
      repository: FakeUpdatesRepository(latency: Duration.zero),
    );

    await _pumpUpdatesScreen(
      tester,
      device: iphoneProProfile,
      controller: controller,
    );

    expect(
      controller.recentStories.any((story) => story.id == 'noah-story'),
      isTrue,
    );

    await tester.tap(find.byKey(const Key('updates_story_tile_noah-story')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(const Key('updates_story_viewer')), findsOneWidget);

    await tester.tap(find.byKey(const Key('updates_story_viewer_right_zone')));
    await tester.pump();

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(
      controller.recentStories.any((story) => story.id == 'noah-story'),
      isTrue,
    );
    expect(
      controller.viewedStories.any((story) => story.id == 'noah-story'),
      isFalse,
    );
    expect(
      controller.recentStories
          .singleWhere((story) => story.id == 'noah-story')
          .seenSegments,
      2,
    );
  });

  testWidgets('shows an error card and retries after a failed load',
      (tester) async {
    final controller = UpdatesController(
      repository: _FlakyUpdatesRepository(),
    );

    await _pumpUpdatesScreen(
      tester,
      device: androidSmallProfile,
      controller: controller,
    );

    expect(find.byKey(const Key('updates_error_card')), findsOneWidget);
    expect(find.text('Transient updates failure'), findsOneWidget);

    await tester.tap(find.byKey(const Key('updates_retry_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('updates_error_card')), findsNothing);
    expect(find.text('Recent updates'), findsOneWidget);
  });

  testWidgets('opens the manager sheet and lists existing status segments',
      (tester) async {
    final controller = UpdatesController(
      repository: FakeUpdatesRepository(latency: Duration.zero),
    );
    await controller.loadUpdates();
    await controller.createStatus(
      type: StatusStoryType.text,
      caption: 'Older status to reopen',
    );
    await controller.createStatus(
      type: StatusStoryType.text,
      caption: 'Latest status stays on top',
    );

    await _pumpUpdatesScreen(
      tester,
      device: iphoneSeProfile,
      controller: controller,
    );

    await tester.tap(find.byKey(const Key('updates_my_status_manage_button')));
    await tester.pumpAndSettle();

    expect(find.text('Manage status'), findsOneWidget);
    expect(
        find.byKey(const Key('updates_my_status_segment_1')), findsOneWidget);
    expect(
        find.byKey(const Key('updates_my_status_segment_0')), findsOneWidget);
    expect(find.text('Latest'), findsOneWidget);
    expect(find.text('Latest status stays on top'), findsWidgets);
    expect(find.text('Older status to reopen'), findsWidgets);
  });

  testWidgets(
      'renders a rotated, Firebase-backed photo segment through the shared '
      'media surface in the manage-status sheet, instead of falling back '
      'to the generic placeholder', (tester) async {
    // Mimics FirebaseStatusMediaStore: importMedia returns a remote URL,
    // not a local path -- the old thumbnail's plain File(url).existsSync()
    // check is always false for a URL, so this exact shape is what used to
    // silently fall through to the generic "PHOTO" placeholder.
    final controller = UpdatesController(
      repository: FakeUpdatesRepository(
        latency: Duration.zero,
        mediaStore: const _PassThroughStatusMediaStore(
          'https://example.com/status-photo.jpg',
        ),
      ),
    );
    await controller.loadUpdates();
    await controller.createStatus(
      type: StatusStoryType.photo,
      localMediaPath: '/picked/photo.jpg',
      mediaTransform: const StatusMediaTransform(
        rotationQuarterTurns: 1,
        frameAspectRatio: 3 / 4,
      ),
    );

    await HttpOverrides.runZoned(() async {
      await _pumpUpdatesScreen(
        tester,
        device: iphoneSeProfile,
        controller: controller,
      );

      await tester
          .tap(find.byKey(const Key('updates_my_status_manage_button')));
      await tester.pumpAndSettle();

      final surfaceFinder = find.descendant(
        of: find.byKey(const Key('updates_my_status_segment_0')),
        matching: find.byType(StatusStoryMediaSurface),
      );
      expect(surfaceFinder, findsOneWidget);
      final surface = tester.widget<StatusStoryMediaSurface>(surfaceFinder);
      expect(surface.localMediaPath, 'https://example.com/status-photo.jpg');
      expect(surface.mediaTransform.rotationQuarterTurns, 1);
      expect(surface.mediaTransform.frameAspectRatio, closeTo(3 / 4, 0.0001));
      expect(find.text('PHOTO'), findsNothing);
    }, createHttpClient: (context) => _ThrowingHttpClient());
  });

  testWidgets('deletes one status from manager and clears the rest',
      (tester) async {
    final controller = UpdatesController(
      repository: FakeUpdatesRepository(latency: Duration.zero),
    );
    await controller.loadUpdates();
    await controller.createStatus(
      type: StatusStoryType.text,
      caption: 'First status to remove',
    );
    await controller.createStatus(
      type: StatusStoryType.text,
      caption: 'Second status to keep',
    );
    final firstSegmentId = controller.myStatus!.segments.first.id;

    await _pumpUpdatesScreen(
      tester,
      device: androidSmallProfile,
      controller: controller,
    );

    await tester.tap(find.byKey(const Key('updates_my_status_manage_button')));
    await tester.pumpAndSettle();

    expect(find.text('Delete all (2)'), findsOneWidget);

    await tester.tap(find.byKey(Key('updates_delete_status_$firstSegmentId')));
    await tester.pumpAndSettle();

    expect(find.text('Delete all (1)'), findsOneWidget);
    expect(controller.myStatus?.totalSegments, 1);
    expect(
      controller.myStatus?.latestSegment?.previewText,
      'Second status to keep',
    );

    await tester.tap(
      find.byKey(const Key('updates_my_status_clear_all_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Delete all statuses?'), findsOneWidget);
    expect(
      find.text('This removes your last status update from My status.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Delete all (1)'), findsOneWidget);
    expect(controller.myStatus?.totalSegments, 1);

    await tester.tap(
      find.byKey(const Key('updates_my_status_clear_all_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Delete all statuses?'), findsOneWidget);

    await tester.tap(find.text('Delete all'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('updates_my_status_manage_button')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('updates_my_status_card')),
        matching: find.text('Share a quick update'),
      ),
      findsOneWidget,
    );
  });
}

Future<void> _pumpUpdatesScreen(
  WidgetTester tester, {
  required TestDeviceProfile device,
  required UpdatesController controller,
}) async {
  await tester.binding.setSurfaceSize(device.size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      home: Scaffold(
        body: UpdatesScreen(controller: controller),
      ),
    ),
  );
  await tester.pumpAndSettle();

  expect(
    tester.takeException(),
    isNull,
    reason:
        '${device.name} should render the updates experience without framework exceptions.',
  );
}

class _FlakyUpdatesRepository implements UpdatesRepository {
  _FlakyUpdatesRepository()
      : _delegate = FakeUpdatesRepository(latency: Duration.zero);

  final FakeUpdatesRepository _delegate;
  bool _hasFailed = false;

  @override
  Stream<UpdatesFeed>? watchUpdates() => _delegate.watchUpdates();

  @override
  Future<UpdatesFeed> fetchUpdates() {
    if (!_hasFailed) {
      _hasFailed = true;
      throw const UpdatesRepositoryException('Transient updates failure');
    }
    return _delegate.fetchUpdates();
  }

  @override
  Future<List<StatusStory>> createStatus({
    required StatusStoryType type,
    String? caption,
    String? localMediaPath,
    StatusTextStyle? textStyle,
    StatusMediaTransform? mediaTransform,
    List<StatusMediaOverlayItem>? overlayItems,
    String? emoji,
    List<String>? stickers,
    StatusMusicTrack? musicTrack,
    int? durationMillis,
    int? trimStartMillis,
    List<StatusDrawingStroke>? drawingStrokes,
  }) =>
      _delegate.createStatus(
        type: type,
        caption: caption,
        localMediaPath: localMediaPath,
        textStyle: textStyle,
        mediaTransform: mediaTransform,
        overlayItems: overlayItems,
        emoji: emoji,
        stickers: stickers,
        musicTrack: musicTrack,
        durationMillis: durationMillis,
        trimStartMillis: trimStartMillis,
        drawingStrokes: drawingStrokes,
      );

  @override
  Future<List<StatusStory>> markStoryViewed(
    String storyId, {
    required int seenSegments,
  }) =>
      _delegate.markStoryViewed(storyId, seenSegments: seenSegments);

  @override
  Future<List<StatusStory>> deleteStatusSegment({
    required String storyId,
    required String segmentId,
  }) =>
      _delegate.deleteStatusSegment(
        storyId: storyId,
        segmentId: segmentId,
      );

  @override
  Future<List<StatusStory>> clearStory({
    required String storyId,
  }) =>
      _delegate.clearStory(storyId: storyId);

  @override
  Future<List<StoryViewer>> fetchStoryViewers(String storyId) =>
      _delegate.fetchStoryViewers(storyId);

  @override
  Future<bool> isStoryLikedByMe(
    String storyId, {
    required String segmentId,
  }) =>
      _delegate.isStoryLikedByMe(storyId, segmentId: segmentId);

  @override
  Future<void> setStoryLiked(
    String storyId, {
    required String segmentId,
    required bool liked,
  }) =>
      _delegate.setStoryLiked(
        storyId,
        segmentId: segmentId,
        liked: liked,
      );

  @override
  Stream<List<StoryViewer>>? watchStoryViewers(String storyId) =>
      _delegate.watchStoryViewers(storyId);
}

class _PassThroughStatusMediaStore implements StatusMediaStore {
  const _PassThroughStatusMediaStore(this.targetPath);

  final String targetPath;

  @override
  Future<String> importMedia(
    String sourcePath, {
    required StatusStoryType type,
  }) async {
    return targetPath;
  }

  @override
  Future<void> deleteMedia(Iterable<String> mediaPaths) async {}
}

/// Fails every request immediately instead of attempting a real network
/// call -- widget tests run without network access, and a remote-media
/// StatusStoryMediaSurface otherwise hangs waiting on a response that
/// never arrives. Matches the pattern already used in avatar_badge_test.dart
/// for the same reason.
class _ThrowingHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    throw const SocketException('No network in tests.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
