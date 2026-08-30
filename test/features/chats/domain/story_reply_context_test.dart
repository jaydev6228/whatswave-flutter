import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/models/status_story.dart';
import 'package:whatswave/features/chats/domain/story_reply_context.dart';

void main() {
  test('the replied-to status item survives a round trip', () {
    const context = StoryReplyContext(
      storyOwnerUid: 'jay',
      storyOwnerName: 'Jay',
      segmentType: StatusStoryType.video,
      segmentId: 'segment-7',
      previewText: 'nice one',
    );

    final restored = StoryReplyContext.fromJson(context.toJson());

    expect(restored, isNotNull);
    expect(restored!.segmentId, 'segment-7');
    expect(restored.storyOwnerUid, 'jay');
    expect(restored.segmentType, StatusStoryType.video);
  });

  test('replies written before segment ids existed still decode', () {
    // The old shape: owner and a snapshot, no segment id. These keep the
    // owner-only behaviour rather than becoming dead links.
    final restored = StoryReplyContext.fromJson(<String, Object?>{
      'storyOwnerUid': 'jay',
      'storyOwnerName': 'Jay',
      'segmentType': 'photo',
      'previewText': 'old reply',
    });

    expect(restored, isNotNull);
    expect(restored!.segmentId, isNull);
    expect(restored.previewText, 'old reply');
  });

  test('an empty segment id decodes as absent, not as a segment called ""', () {
    final restored = StoryReplyContext.fromJson(<String, Object?>{
      'storyOwnerUid': 'jay',
      'storyOwnerName': 'Jay',
      'segmentType': 'text',
      'segmentId': '',
    });

    expect(restored!.segmentId, isNull);
  });
}
