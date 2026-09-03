import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/models/status_story.dart';
import 'package:whatswave/features/auth/application/auth_controller.dart';
import 'package:whatswave/features/auth/data/fake_auth_repository.dart';
import 'package:whatswave/features/calls/application/calls_controller.dart';
import 'package:whatswave/features/calls/data/fake_calls_repository.dart';
import 'package:whatswave/features/chats/application/chats_controller.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/chats/presentation/chats_screen.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/updates/application/updates_controller.dart';
import 'package:whatswave/features/updates/data/fake_updates_repository.dart';
import 'package:whatswave/features/updates/data/updates_repository.dart';

/// Demo data: Ava's ring is three photo segments, each with its own text
/// overlay, and seenSegments: 1 -- so opening it lands on the *second* one.
const _firstSegmentText = 'Late-night launch coffee';
const _secondSegmentText = 'Built in one calm evening';
const _thirdSegmentText = 'Small team, big launch';

/// Serves other people's rings with `totalSegments` set but no `segments`
/// until [hydrated] is flipped -- the shape a status feed really has before
/// its segment list loads, and the one that made
/// [StatusStory.segmentAt] hand the reply bar a synthesized segment id.
class _LateHydratingUpdatesRepository extends FakeUpdatesRepository {
  _LateHydratingUpdatesRepository() : super(latency: Duration.zero);

  bool hydrated = false;

  List<StatusStory> _visible(List<StatusStory> stories) => hydrated
      ? stories
      : stories
          .map(
            (story) => story.isMine
                ? story
                : story.copyWith(segments: const <StatusStorySegment>[]),
          )
          .toList(growable: false);

  @override
  Future<UpdatesFeed> fetchUpdates() async {
    final feed = await super.fetchUpdates();
    return UpdatesFeed(
      stories: _visible(feed.stories),
      channels: feed.channels,
    );
  }

  @override
  Future<List<StatusStory>> markStoryViewed(
    String storyId, {
    required int seenSegments,
  }) async {
    return _visible(
        await super.markStoryViewed(storyId, seenSegments: seenSegments));
  }
}

void main() {
  testWidgets(
      'a reply sent before the ring hydrated still reopens that segment',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final updatesRepository = _LateHydratingUpdatesRepository();
    final updatesController = UpdatesController(repository: updatesRepository);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: ChatsScreen(
            callsController: CallsController(
              repository: FakeCallsRepository(latency: Duration.zero),
            ),
            communitiesController: CommunitiesController(
              repository: FakeCommunitiesRepository(latency: Duration.zero),
            ),
            controller: ChatsController(
              repository: FakeChatRepository(latency: Duration.zero),
            ),
            updatesController: updatesController,
            authController: AuthController(
              repository: FakeAuthRepository(latency: Duration.zero),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final avatarFinder =
        find.byKey(const ValueKey<String>('chat_story_avatar_ava-patel'));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -260));
    await tester.pumpAndSettle();
    await tester.ensureVisible(avatarFinder);
    await tester.pump();
    await tester.tap(avatarFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // One segment already seen, so this is the ring's second item -- the
    // story the user replies to below.
    expect(find.byKey(const Key('updates_story_viewer')), findsOneWidget);

    // Typing pauses playback, so the segment can't advance mid-reply.
    await tester.tap(find.byKey(const Key('updates_story_reply_field')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('updates_story_reply_field')),
      'Love this one',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('updates_story_reply_send_button')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Reply sent to Ava'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    // The ring's segments arrive after the reply was sent.
    updatesRepository.hydrated = true;
    await updatesController.loadUpdates();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('chat_tile_ava-story')));
    await tester.pumpAndSettle();

    final cardFinder = find.byKey(const Key('story_reply_card'));
    expect(cardFinder, findsOneWidget);
    // The status is live, so the card must not claim otherwise.
    expect(find.text('Original status no longer available'), findsNothing);

    // Not pumpAndSettle -- the reopened viewer's progress bar never stops.
    await tester.tap(cardFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(const Key('updates_story_viewer')), findsOneWidget);
    // The replied-to segment, not the ring's first one and not wherever
    // the unseen-resume rule would otherwise land.
    expect(find.text(_secondSegmentText), findsOneWidget);
    expect(find.text(_firstSegmentText), findsNothing);
    expect(find.text(_thirdSegmentText), findsNothing);
  });
}
