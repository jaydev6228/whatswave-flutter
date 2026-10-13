import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Screens proven to render across [layoutMatrix] x [layoutVariants].
/// Move a name here from [_pendingCoverage] once it has a layout test.
const _covered = <String>{
  'chats_screen',
  'conversation_screen',
  'updates_screen',
  'calls_screen',
  'communities_screen',
  'auth_flow_screen',
  'status_story_viewer_screen',
  'media_status_composer_screen',
  'text_status_composer_screen',
  'media_send_preview_screen',
  'layout_status_composer_screen',
  'shared_media_screen',
};

/// Debug-only surfaces behind WW_ENABLE_DEMO_SURFACES. These never ship, so
/// they are deliberately not worth a layout test -- but `release_gate_test`
/// must keep proving they stay out of release builds.
const _exemptDebugOnly = <String>{
  'call_signaling_test_screen',
  'livekit_test_screen',
  'backend_sync_screen',
};

/// The backlog. This set may only ever shrink -- see the ratchet below.
const _pendingCoverage = <String>{
  'add_group_members_screen',
  'attachment_viewer_screen',
  'avatar_crop_screen',
  'blocked_contacts_screen',
  'call_experience_screen',
  'community_detail_screen',
  'community_info_screen',
  'contact_info_screen',
  'document_send_preview_screen',
  'emoji_reaction_picker_screen',
  'forward_message_screen',
  'help_screen',
  'location_send_preview_screen',
  'new_chat_screen',
  'new_group_screen',
  'privacy_settings_screen',
  'profile_settings_screen',
  'session_splash_screen',
  'settings_screen',
  'starred_messages_screen',
  'storage_data_screen',
};

/// The ratchet. Lower this number as screens move to [_covered]; the test
/// fails if it ever grows, so coverage cannot quietly rot back.
const _maxPendingScreens = 21;

void main() {
  test('every screen in lib/ is classified for layout coverage', () {
    final screens = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('_screen.dart'))
        .map((n) => n.replaceAll('.dart', ''))
        .toSet();

    final classified = {..._covered, ..._exemptDebugOnly, ..._pendingCoverage};
    final unclassified = screens.difference(classified);

    expect(
      unclassified,
      isEmpty,
      reason: 'New screen(s) found with no layout-coverage decision: '
          '${unclassified.join(', ')}.\n'
          'Add a layout test and list it in _covered, or justify it in '
          '_exemptDebugOnly. Do not add it to _pendingCoverage -- that set '
          'is a backlog being drained, not a parking space.',
    );

    final stale = classified.difference(screens);
    expect(
      stale,
      isEmpty,
      reason: 'These names no longer exist in lib/ and should be removed '
          'from this file: ${stale.join(', ')}.',
    );
  });

  test('the layout-coverage backlog only shrinks', () {
    expect(
      _pendingCoverage.length,
      lessThanOrEqualTo(_maxPendingScreens),
      reason: 'The backlog grew. A screen was added to _pendingCoverage '
          'instead of being given a layout test.',
    );
  });
}
