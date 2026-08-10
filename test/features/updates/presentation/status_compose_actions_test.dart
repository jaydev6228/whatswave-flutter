import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/models/status_story.dart';
import 'package:whatswave/core/models/story_viewer.dart';
import 'package:whatswave/features/updates/application/updates_controller.dart';
import 'package:whatswave/features/updates/data/updates_repository.dart';
import 'package:whatswave/features/updates/presentation/status_compose_actions.dart';

import '../../../support/device_matrix.dart';

/// A repository whose createStatus always fails -- used to verify that a
/// failed post now actually tells the user, instead of silently doing
/// nothing (see the doc comment on openTextStatusComposer/pickStatusMedia's
/// error-dialog calls in status_compose_actions.dart).
class _FailingCreateStatusRepository implements UpdatesRepository {
  @override
  Future<UpdatesFeed> fetchUpdates() async =>
      const UpdatesFeed(stories: [], channels: []);

  @override
  Stream<UpdatesFeed>? watchUpdates() => null;

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
  }) {
    throw const UpdatesRepositoryException(
      'Storage is unreachable right now.',
    );
  }

  @override
  Future<List<StatusStory>> markStoryViewed(
    String storyId, {
    required int seenSegments,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<StatusStory>> deleteStatusSegment({
    required String storyId,
    required String segmentId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<StatusStory>> clearStory({required String storyId}) {
    throw UnimplementedError();
  }

  @override
  Future<List<StoryViewer>> fetchStoryViewers(String storyId) {
    throw UnimplementedError();
  }

  @override
  Future<void> likeStory(String storyId) {
    throw UnimplementedError();
  }
}

void main() {
  testWidgets(
      'openTextStatusComposer shows an error dialog when the post fails, '
      'instead of silently doing nothing', (tester) async {
    await tester.binding.setSurfaceSize(iphoneSeProfile.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = UpdatesController(
      repository: _FailingCreateStatusRepository(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () => openTextStatusComposer(context, controller),
              child: const Text('Open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('updates_composer_field')),
      'Hello!',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('updates_share_status_button')));
    await tester.pumpAndSettle();

    // The composer sheet is gone (it always pops with the draft first),
    // and in its place is an explicit failure dialog -- not silence.
    expect(find.byKey(const Key('updates_composer_sheet')), findsNothing);
    expect(find.text('Storage is unreachable right now.'), findsOneWidget);
  });
}
