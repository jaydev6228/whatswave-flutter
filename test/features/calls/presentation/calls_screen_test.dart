import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/features/calls/application/calls_controller.dart';
import 'package:whatswave/features/calls/data/fake_calls_repository.dart';
import 'package:whatswave/features/calls/domain/call_history_entry.dart';
import 'package:whatswave/features/calls/presentation/calls_screen.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/communities/domain/community_contact.dart';
import 'package:whatswave/features/communities/domain/contact_access_status.dart';

import '../../../support/device_matrix.dart';
import 'package:whatswave/features/shared/widgets/liquid_glass.dart';

CommunitiesController _defaultCommunitiesController({
  List<CommunityContact>? initialContacts,
}) {
  return CommunitiesController(
    repository: FakeCommunitiesRepository(
      latency: Duration.zero,
      initialContacts: initialContacts,
    ),
    permissionService: MemoryAppPermissionService(
      contactsStatus: ContactAccessStatus.granted,
    ),
  );
}

Future<void> _searchAndStartCall(
  WidgetTester tester, {
  required String query,
  required Key callButtonKey,
}) async {
  await tester.enterText(
    find.byKey(const Key('calls_search_field')),
    query,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(callButtonKey));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'starts an outgoing video call after allowing permissions and records it in history',
      (tester) async {
    final controller = CallsController(
      repository: FakeCallsRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(),
      outgoingRingDuration: Duration.zero,
      outgoingConnectingDuration: Duration.zero,
      durationTickInterval: Duration.zero,
    );

    await _pumpCallsScreen(
      tester,
      device: iphoneSeProfile,
      controller: controller,
    );

    await _searchAndStartCall(
      tester,
      query: 'Ava',
      callButtonKey: const Key('calls_search_video_ava-patel'),
    );

    expect(find.byKey(const Key('call_experience_screen')), findsOneWidget);
    expect(controller.currentSession?.phase.name, 'connected');
    expect(find.text('Remote stream'), findsNothing);

    await tester.tap(find.byKey(const Key('call_end_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('call_experience_screen')), findsNothing);
    expect(controller.history.first.contactId, 'ava-patel');
    expect(controller.history.first.status, CallHistoryStatus.completed);
  });

  testWidgets(
      'finds WhatsWave contacts via search and places a call using their uid',
      (tester) async {
    final controller = CallsController(
      repository: FakeCallsRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(),
      outgoingRingDuration: Duration.zero,
      outgoingConnectingDuration: Duration.zero,
      durationTickInterval: Duration.zero,
    );
    final communitiesController = _defaultCommunitiesController();

    await _pumpCallsScreen(
      tester,
      device: iphoneSeProfile,
      controller: controller,
      communitiesController: communitiesController,
    );

    await _searchAndStartCall(
      tester,
      query: '@priya.rai',
      callButtonKey: const Key('calls_search_audio_priya-rai'),
    );

    expect(controller.currentSession?.contact.uid, 'uid-priya-rai');
  });

  testWidgets('shows a permission error when microphone access is denied',
      (tester) async {
    final controller = CallsController(
      repository: FakeCallsRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(
        grantMicrophoneOnRequest: false,
      ),
      durationTickInterval: Duration.zero,
    );

    await _pumpCallsScreen(
      tester,
      device: androidSmallProfile,
      controller: controller,
    );

    await _searchAndStartCall(
      tester,
      query: 'Ava',
      callButtonKey: const Key('calls_search_audio_ava-patel'),
    );

    expect(find.text('Microphone access is required for audio calls.'),
        findsOneWidget);
    expect(controller.currentSession, isNull);
  });

  testWidgets('starts a recent call again when a recent list item is tapped',
      (tester) async {
    final controller = CallsController(
      repository: FakeCallsRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(),
      outgoingConnectingDuration: Duration.zero,
      outgoingRingDuration: Duration.zero,
      durationTickInterval: Duration.zero,
    );

    await _pumpCallsScreen(
      tester,
      device: iphoneProProfile,
      controller: controller,
    );

    final recentEntry = controller.history.first;
    await tester.drag(
      find.byKey(const Key('calls_screen')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('calls_recent_item_${recentEntry.id}')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('call_experience_screen')), findsOneWidget);
    expect(controller.currentSession?.phase.name, 'connected');
    expect(controller.currentSession?.type, recentEntry.type);
  });

  testWidgets('does not show raw call status labels in recent call rows',
      (tester) async {
    final controller = CallsController(
      repository: FakeCallsRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(),
      durationTickInterval: Duration.zero,
    );

    await _pumpCallsScreen(
      tester,
      device: iphoneProProfile,
      controller: controller,
    );

    expect(find.text('Completed video'), findsNothing);
    expect(find.text('Missed audio'), findsNothing);
    expect(find.text('Your contacts'), findsNothing);
    expect(find.text('Noah Kim'), findsOneWidget);
    expect(find.byIcon(Icons.group_rounded), findsOneWidget);
  });

  testWidgets('swipe-deletes a call from recent history', (tester) async {
    final controller = CallsController(
      repository: FakeCallsRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(),
      durationTickInterval: Duration.zero,
    );

    await _pumpCallsScreen(
      tester,
      device: iphoneProProfile,
      controller: controller,
    );
    final initialCount = controller.history.length;
    final entryToDelete = controller.history.first;

    await tester.drag(
      find.byKey(const Key('calls_screen')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(Key('call_swipe_${entryToDelete.id}')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('Delete this call?'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(LiquidGlassDialog),
        matching: find.text('Delete'),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.history.length, initialCount - 1);
    expect(
      controller.history.any((entry) => entry.id == entryToDelete.id),
      isFalse,
    );
  });

  testWidgets(
      'keeps the video status and local preview separated on compact phones',
      (tester) async {
    final controller = CallsController(
      repository: FakeCallsRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(),
      outgoingRingDuration: Duration.zero,
      outgoingConnectingDuration: Duration.zero,
      durationTickInterval: Duration.zero,
    );

    await _pumpCallsScreen(
      tester,
      device: iphoneSeProfile,
      controller: controller,
    );

    await _searchAndStartCall(
      tester,
      query: 'Ava',
      callButtonKey: const Key('calls_search_video_ava-patel'),
    );

    final statusRect =
        tester.getRect(find.byKey(const Key('call_video_status_text')));
    final previewRect =
        tester.getRect(find.byKey(const Key('call_video_preview_card')));
    final dockRect =
        tester.getRect(find.byKey(const Key('call_video_control_dock')));
    final screenRect =
        tester.getRect(find.byKey(const Key('call_experience_screen')));
    final switchButtonRect =
        tester.getRect(find.byKey(const Key('call_switch_camera_button')));

    expect(find.byKey(const Key('call_video_control_dock')), findsOneWidget);
    expect(previewRect.left, greaterThan(statusRect.right + 8));
    expect(
      dockRect.center.dx,
      moreOrLessEquals(screenRect.center.dx, epsilon: 8),
      reason:
          'The video control dock should stay centered along the bottom edge.',
    );
    expect(
      dockRect.contains(switchButtonRect.center),
      isTrue,
      reason:
          'The front/back camera action should live inside the bottom dock.',
    );
    expect(
      previewRect.contains(switchButtonRect.center),
      isFalse,
      reason:
          'The switch camera action should no longer consume space in the local preview card.',
    );
    expect(
      find.text('You'),
      findsNothing,
      reason:
          'The preview badge is intentionally removed for a cleaner local preview.',
    );
    expect(find.text('Camera'), findsNothing);
    expect(find.text('Speaker'), findsNothing);
    expect(find.text('Mute'), findsNothing);

    await tester.tap(find.byKey(const Key('call_switch_camera_button')));
    await tester.pumpAndSettle();

    expect(
      controller.currentSession?.isFrontCamera,
      isFalse,
      reason:
          'Tapping the dock switch action should still swap between front and back camera states.',
    );

    await tester.tap(find.byKey(const Key('call_video_toggle_button')));
    await tester.pumpAndSettle();

    final disabledPreviewRect =
        tester.getRect(find.byKey(const Key('call_video_preview_card')));
    final disabledLabelRect =
        tester.getRect(find.byKey(const Key('call_local_video_status_label')));

    expect(find.text('Cam off'), findsNothing);
    expect(
      disabledLabelRect.left,
      greaterThanOrEqualTo(disabledPreviewRect.left),
      reason: 'The camera-off label should stay inside the preview card.',
    );
    expect(
      disabledLabelRect.right,
      lessThanOrEqualTo(disabledPreviewRect.right),
      reason: 'The camera-off label should not clip at the preview edge.',
    );
    expect(
      tester.takeException(),
      isNull,
      reason: 'Compact video call layout should not overlap or overflow.',
    );
  });

  testWidgets('keeps the dock camera switch control soft in light theme',
      (tester) async {
    final controller = CallsController(
      repository: FakeCallsRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(),
      outgoingRingDuration: Duration.zero,
      outgoingConnectingDuration: Duration.zero,
      durationTickInterval: Duration.zero,
    );

    await _pumpCallsScreen(
      tester,
      device: iphoneSeProfile,
      controller: controller,
      themeMode: ThemeMode.light,
    );

    await _searchAndStartCall(
      tester,
      query: 'Ava',
      callButtonKey: const Key('calls_search_video_ava-patel'),
    );

    final switchIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('call_switch_camera_button')),
        matching: find.byIcon(Icons.flip_camera_ios_rounded),
      ),
    );
    final muteIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('call_mute_button')),
        matching: find.byIcon(Icons.mic_rounded),
      ),
    );

    expect(
      switchIcon.color,
      equals(muteIcon.color),
      reason:
          'The dock camera switch should share the same foreground treatment as the other dock controls.',
    );
    expect(
      tester.takeException(),
      isNull,
      reason:
          'The dock switch styling should still render without layout or paint issues.',
    );
  });

  testWidgets(
      'highlights the speaker control with a neutral fill while keeping a stable label',
      (tester) async {
    final controller = CallsController(
      repository: FakeCallsRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(),
      outgoingRingDuration: Duration.zero,
      outgoingConnectingDuration: Duration.zero,
      durationTickInterval: Duration.zero,
    );

    await _pumpCallsScreen(
      tester,
      device: iphoneSeProfile,
      controller: controller,
      themeMode: ThemeMode.dark,
    );

    await _searchAndStartCall(
      tester,
      query: 'Ava',
      callButtonKey: const Key('calls_search_audio_ava-patel'),
    );

    final speakerActionFinder =
        find.byKey(const Key('call_audio_route_button'));
    final speakerContainerFinder = find.ancestor(
      of: speakerActionFinder,
      matching: find.byType(AnimatedContainer),
    );

    final beforeDecoration = tester
        .widget<AnimatedContainer>(speakerContainerFinder.first)
        .decoration! as BoxDecoration;
    final beforeColor = beforeDecoration.color;

    expect(find.text('Speaker'), findsNothing);

    await tester.tap(speakerActionFinder);
    await tester.pumpAndSettle();

    final afterDecoration = tester
        .widget<AnimatedContainer>(speakerContainerFinder.first)
        .decoration! as BoxDecoration;
    final afterColor = afterDecoration.color;
    final afterHsl = HSLColor.fromColor(afterColor!.withAlpha(255));

    expect(controller.currentSession?.isSpeakerOn, isTrue);
    expect(afterColor, isNot(equals(beforeColor)));
    expect(find.text('Speaker'), findsNothing);
    expect(
      afterColor.a,
      greaterThan(beforeColor!.a + 0.15),
      reason:
          'Speaker on should read as a clearly brighter control, not a barely different translucent shade.',
    );
    expect(
      afterHsl.saturation,
      lessThan(0.12),
      reason:
          'Selected call controls should feel neutral instead of using loud accent fills.',
    );
    expect(
      tester.takeException(),
      isNull,
      reason:
          'Speaker state changes should not introduce layout or paint issues.',
    );
  });

  testWidgets(
      'keeps dark theme mute and speaker selected surfaces visually aligned',
      (tester) async {
    final controller = CallsController(
      repository: FakeCallsRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(),
      outgoingRingDuration: Duration.zero,
      outgoingConnectingDuration: Duration.zero,
      durationTickInterval: Duration.zero,
    );

    await _pumpCallsScreen(
      tester,
      device: iphoneSeProfile,
      controller: controller,
      themeMode: ThemeMode.dark,
    );

    await _searchAndStartCall(
      tester,
      query: 'Ava',
      callButtonKey: const Key('calls_search_audio_ava-patel'),
    );

    final muteActionFinder = find.byKey(const Key('call_mute_button'));
    final muteContainerFinder = find.ancestor(
      of: muteActionFinder,
      matching: find.byType(AnimatedContainer),
    );
    final speakerActionFinder =
        find.byKey(const Key('call_audio_route_button'));
    final speakerContainerFinder = find.ancestor(
      of: speakerActionFinder,
      matching: find.byType(AnimatedContainer),
    );

    await tester.tap(muteActionFinder);
    await tester.pumpAndSettle();
    await tester.tap(speakerActionFinder);
    await tester.pumpAndSettle();
    final muteDecoration = tester
        .widget<AnimatedContainer>(muteContainerFinder.first)
        .decoration! as BoxDecoration;
    final speakerDecoration = tester
        .widget<AnimatedContainer>(speakerContainerFinder.first)
        .decoration! as BoxDecoration;

    expect(controller.currentSession?.isMuted, isTrue);
    expect(controller.currentSession?.isSpeakerOn, isTrue);
    expect(find.text('Muted'), findsNothing);
    expect(find.text('Speaker'), findsNothing);
    expect(muteDecoration.color, equals(speakerDecoration.color));
    expect(
      muteDecoration.border,
      equals(speakerDecoration.border),
      reason:
          'Dark theme mute and speaker states should use the same selected surface treatment.',
    );
    expect(
      tester.takeException(),
      isNull,
      reason:
          'Matching selected call controls should still render without layout or paint issues.',
    );
  });

  testWidgets(
      'keeps dark theme mute, speaker, and camera selected surfaces visually aligned',
      (tester) async {
    final controller = CallsController(
      repository: FakeCallsRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(),
      outgoingRingDuration: Duration.zero,
      outgoingConnectingDuration: Duration.zero,
      durationTickInterval: Duration.zero,
    );

    await _pumpCallsScreen(
      tester,
      device: iphoneSeProfile,
      controller: controller,
      themeMode: ThemeMode.dark,
    );

    await _searchAndStartCall(
      tester,
      query: 'Ava',
      callButtonKey: const Key('calls_search_video_ava-patel'),
    );

    final muteActionFinder = find.byKey(const Key('call_mute_button'));
    final muteContainerFinder = find.ancestor(
      of: muteActionFinder,
      matching: find.byType(AnimatedContainer),
    );
    final speakerActionFinder =
        find.byKey(const Key('call_audio_route_button'));
    final speakerContainerFinder = find.ancestor(
      of: speakerActionFinder,
      matching: find.byType(AnimatedContainer),
    );
    final cameraActionFinder =
        find.byKey(const Key('call_video_toggle_button'));
    final cameraContainerFinder = find.ancestor(
      of: cameraActionFinder,
      matching: find.byType(AnimatedContainer),
    );

    await tester.tap(muteActionFinder);
    await tester.pumpAndSettle();

    final muteDecoration = tester
        .widget<AnimatedContainer>(muteContainerFinder.first)
        .decoration! as BoxDecoration;
    final speakerDecoration = tester
        .widget<AnimatedContainer>(speakerContainerFinder.first)
        .decoration! as BoxDecoration;
    final cameraDecoration = tester
        .widget<AnimatedContainer>(cameraContainerFinder.first)
        .decoration! as BoxDecoration;

    expect(controller.currentSession?.isMuted, isTrue);
    expect(controller.currentSession?.isSpeakerOn, isTrue);
    expect(controller.currentSession?.isLocalVideoEnabled, isTrue);
    expect(find.text('Muted'), findsNothing);
    expect(find.text('Speaker'), findsNothing);
    expect(find.text('Camera'), findsNothing);
    expect(muteDecoration.color, equals(speakerDecoration.color));
    expect(cameraDecoration.color, equals(speakerDecoration.color));
    expect(
      muteDecoration.border,
      equals(speakerDecoration.border),
      reason:
          'Dark theme mute and speaker states should use the same selected surface treatment.',
    );
    expect(
      cameraDecoration.border,
      equals(speakerDecoration.border),
      reason:
          'Dark theme camera on should match the same selected surface treatment as mute and speaker.',
    );
    expect(
      tester.takeException(),
      isNull,
      reason:
          'Matching selected video-call controls should still render without layout or paint issues.',
    );
  });

  testWidgets(
      'makes the light theme speaker control read as an obvious selected surface',
      (tester) async {
    final controller = CallsController(
      repository: FakeCallsRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(),
      outgoingRingDuration: Duration.zero,
      outgoingConnectingDuration: Duration.zero,
      durationTickInterval: Duration.zero,
    );

    await _pumpCallsScreen(
      tester,
      device: iphoneSeProfile,
      controller: controller,
      themeMode: ThemeMode.light,
    );

    await _searchAndStartCall(
      tester,
      query: 'Ava',
      callButtonKey: const Key('calls_search_audio_ava-patel'),
    );

    final speakerActionFinder =
        find.byKey(const Key('call_audio_route_button'));
    final speakerContainerFinder = find.ancestor(
      of: speakerActionFinder,
      matching: find.byType(AnimatedContainer),
    );

    final beforeDecoration = tester
        .widget<AnimatedContainer>(speakerContainerFinder.first)
        .decoration! as BoxDecoration;
    final beforeColor = beforeDecoration.color!;
    final beforeHsl = HSLColor.fromColor(beforeColor.withAlpha(255));
    final beforeLuminance = beforeColor.withAlpha(255).computeLuminance();

    await tester.tap(speakerActionFinder);
    await tester.pumpAndSettle();

    final afterDecoration = tester
        .widget<AnimatedContainer>(speakerContainerFinder.first)
        .decoration! as BoxDecoration;
    final afterColor = afterDecoration.color!;
    final afterHsl = HSLColor.fromColor(afterColor.withAlpha(255));
    final afterLuminance = afterColor.withAlpha(255).computeLuminance();

    expect(controller.currentSession?.isSpeakerOn, isTrue);
    expect(find.text('Speaker'), findsNothing);
    expect(
      afterHsl.lightness,
      greaterThan(beforeHsl.lightness + 0.05),
      reason:
          'Light theme speaker on should step up to a clearly brighter white surface.',
    );
    expect(
      afterLuminance,
      greaterThan(beforeLuminance + 0.05),
      reason:
          'Speaker on should feel obviously selected in light mode, not just barely different.',
    );
    expect(
      afterHsl.saturation,
      lessThan(0.12),
      reason:
          'Light theme selected controls should stay neutral instead of introducing a loud tint.',
    );
    expect(
      tester.takeException(),
      isNull,
      reason:
          'Light theme speaker state changes should not introduce layout or paint issues.',
    );
  });

  testWidgets('renders the audio call portrait backdrop cleanly in dark theme',
      (tester) async {
    final controller = CallsController(
      repository: FakeCallsRepository(latency: Duration.zero),
      permissionService: MemoryAppPermissionService(),
      outgoingRingDuration: Duration.zero,
      outgoingConnectingDuration: Duration.zero,
      durationTickInterval: Duration.zero,
    );

    await _pumpCallsScreen(
      tester,
      device: iphoneSeProfile,
      controller: controller,
      themeMode: ThemeMode.dark,
    );

    await _searchAndStartCall(
      tester,
      query: 'Ava',
      callButtonKey: const Key('calls_search_audio_ava-patel'),
    );

    expect(find.byKey(const Key('call_audio_backdrop')), findsOneWidget);
    expect(
        find.byKey(const Key('call_audio_backdrop_portrait')), findsOneWidget);
    expect(find.byKey(const Key('call_audio_backdrop_stage')), findsOneWidget);
    expect(find.byKey(const Key('call_audio_avatar_stage')), findsOneWidget);
    final backdropCenter =
        tester.getCenter(find.byKey(const Key('call_audio_backdrop_stage')));
    final avatarCenter =
        tester.getCenter(find.byKey(const Key('call_audio_avatar_stage')));
    expect(backdropCenter.dx, moreOrLessEquals(avatarCenter.dx, epsilon: 0.01));
    expect(backdropCenter.dy, moreOrLessEquals(avatarCenter.dy, epsilon: 0.01));
    expect(
      find.text('AP'),
      findsOneWidget,
      reason:
          'Audio call fallback should show a single centered identity avatar without a duplicated backdrop label.',
    );
    expect(
      tester.takeException(),
      isNull,
      reason: 'Dark theme audio calls should render without layout exceptions.',
    );
  });

  testWidgets('shows an error card and retries after a failed load',
      (tester) async {
    final controller = CallsController(
      repository: FakeCallsRepository(
        latency: Duration.zero,
        failFetchOnce: true,
      ),
      permissionService: MemoryAppPermissionService(),
      durationTickInterval: Duration.zero,
    );

    await _pumpCallsScreen(
      tester,
      device: androidMediumProfile,
      controller: controller,
    );

    expect(find.byKey(const Key('calls_error_card')), findsOneWidget);
    expect(find.text('Transient calls failure'), findsOneWidget);

    await tester.tap(find.byKey(const Key('calls_retry_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('calls_error_card')), findsNothing);
    expect(find.byKey(const Key('calls_search_field')), findsOneWidget);
    expect(find.text('Recent calls'), findsNothing);
    expect(controller.history, isNotEmpty);
  });
}

Future<void> _pumpCallsScreen(
  WidgetTester tester, {
  required TestDeviceProfile device,
  required CallsController controller,
  CommunitiesController? communitiesController,
  ThemeMode themeMode = ThemeMode.light,
}) async {
  await tester.binding.setSurfaceSize(device.size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final resolvedCommunitiesController =
      communitiesController ?? _defaultCommunitiesController();
  await resolvedCommunitiesController.ensureLoaded();

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      home: Scaffold(
        body: CallsScreen(
          controller: controller,
          communitiesController: resolvedCommunitiesController,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  expect(
    tester.takeException(),
    isNull,
    reason:
        '${device.name} should render the calls experience without framework exceptions.',
  );
}
