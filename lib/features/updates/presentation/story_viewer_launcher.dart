import 'package:flutter/material.dart';

import '../../../core/models/status_story.dart';
import '../application/updates_controller.dart';
import 'status_story_viewer_screen.dart';

Future<void> openStatusStoryViewer(
  BuildContext context, {
  required UpdatesController controller,
  required StatusStory story,
  int? initialSegmentIndex,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => StatusStoryViewerScreen(
        story: story,
        initialSegmentIndex: initialSegmentIndex,
        onStoryViewed: (viewedStory) {
          controller.markStoryViewed(
            viewedStory.id,
            seenSegments: viewedStory.seenSegments,
          );
        },
        onDeleteSegment: story.isMine
            ? (activeStory, segment) async {
                final didDelete = await controller.deleteMyStatusSegment(
                  segment.id,
                );
                if (!didDelete) {
                  return StatusStoryDeleteResult(
                    didDelete: false,
                    errorMessage: controller.errorMessage,
                  );
                }

                final refreshedStatus = controller.myStatus;
                return StatusStoryDeleteResult(
                  didDelete: true,
                  updatedStory:
                      refreshedStatus != null && refreshedStatus.hasSegments
                          ? refreshedStatus
                          : null,
                );
              }
            : null,
      ),
    ),
  );
}
