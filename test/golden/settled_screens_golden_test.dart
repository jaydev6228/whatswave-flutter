import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/core/sample/demo_data.dart';
import 'package:whatswave/features/auth/application/auth_controller.dart';
import 'package:whatswave/features/auth/data/fake_auth_repository.dart';
import 'package:whatswave/features/auth/presentation/session_splash_screen.dart';
import 'package:whatswave/features/calls/application/calls_controller.dart';
import 'package:whatswave/features/calls/data/fake_calls_repository.dart';
import 'package:whatswave/features/calls/domain/call_history_entry.dart';
import 'package:whatswave/features/calls/domain/call_session.dart';
import 'package:whatswave/features/calls/presentation/call_experience_screen.dart';
import 'package:whatswave/features/chats/domain/chat_attachment.dart';
import 'package:whatswave/features/chats/presentation/attachment_viewer_screen.dart';
import 'package:whatswave/features/chats/presentation/document_send_preview_screen.dart';
import 'package:whatswave/features/settings/presentation/profile_settings_screen.dart';

import '../support/device_matrix.dart';

/// Golden images for five screens whose visual design is settled.
///
/// ## What these add over the layout sweep
///
/// `expectScreenSurvivesLayoutMatrix` proves a screen lays out without
/// throwing. It cannot see a wrong colour, a wrong gap, a misaligned overlay,
/// or content clipped inside a widget that never reports an overflow. That is
/// this file's only job, and it is why no case here re-runs the matrix:
/// duplicating the sweep would double the runtime and catch nothing new.
///
/// ## What these CANNOT see -- read before trusting an image
///
/// `flutter test` ships no real fonts. Every glyph, including every icon,
/// rasterises as an opaque box in the test font, so these images pin
/// geometry, colour and alignment and say nothing about which letters or
/// which icon a widget drew. A label changed from "Send" to "Sned", or a
/// `delete` icon swapped for `archive`, passes all five of these. Text
/// assertions belong in the behavioural tests, which already have them.
///
/// ## Why these five
///
/// Picked for visual density and design stability, not for coverage tidiness:
///
///   * **CallExperienceScreen** -- the app's densest non-list chrome: a tinted
///     full-bleed gradient, a ringed avatar, name and status lines, and the
///     floating control pill. Nothing else checks that geometry.
///   * **AttachmentViewerScreen** -- stacked overlay chrome (floating title
///     capsule, a seven-button action row) above a media canvas. Overlays are
///     exactly what misaligns without ever overflowing.
///   * **DocumentSendPreviewScreen** -- `AppPalette.emerald` on
///     `AppPalette.cloud`, in the app bar's "Send", plus the file card and the
///     outlined caption field. Commit 80006a3 darkened emerald
///     #128C7E -> #0E7268; a golden is what makes the next such change a
///     deliberate review instead of a surprise.
///   * **ProfileSettingsScreen** -- a circular avatar header over grouped
///     editable rows: the app's standard settings-detail shape, and the one
///     place where avatar, field rows and a primary-coloured app bar action
///     share a frame.
///   * **SessionSplashScreen** -- the brand surface, and the cheapest image
///     here: gradient, emerald mark, title, muted status line, spinner.
///     Almost nothing but palette and type, so a stray theme edit shows up
///     immediately, and it is the screen least likely to be redesigned.
///
/// Deliberately NOT goldened:
///
///   * **Chat list and conversation screen** (both named in
///     docs/test_strategy.md). `DemoData.buildChatThreads()` derives every
///     timestamp from `DateTime.now()`, and both screens format labels
///     relative to the current day (`_threadTimeLabel` in chats_screen.dart,
///     `_dayLabelFor` in conversation_screen.dart). A golden of either rots
///     within the hour. Pinning them needs a parallel fixed-clock fixture set
///     for the two most frequently edited screens in the app -- most churn
///     for most fixture cost. Worth its own change, not smuggled into this
///     one.
///   * **Safety number and passphrase backup** (also named in the plan).
///     Neither screen exists: `lib/core/crypto/safety_number_scope.dart` and
///     `safety_number_card.dart` are a scope and a card widget, and there is
///     no passphrase-backup screen at all. The plan predates the code.
///   * **EmojiReactionPickerSheet**, which was in this set until the
///     generated image was looked at. With no colour emoji font in the test
///     runtime the quick-reaction row and the whole grid render as blank
///     space, and an empty SharedPreferences leaves the recents tab on its
///     "No Recents" placeholder -- so the image was a picker with no emoji in
///     it. It would have passed forever while asserting almost nothing.
///   * **Anything containing a `FlutterMap`** (location send preview, the
///     location bubble). Tiles come from the network, which `flutter_test`
///     answers with a 400, so the golden would pin a tile-error placeholder.
///   * **Plain list screens** (new chat, forward message, blocked contacts,
///     help). Low visual information per pixel, and the sweep plus the
///     accessibility guidelines already cover what they have.
///
/// One image per screen: light theme, 393x852 at 3x, default text scale.
/// Every extra axis (dark theme, 2.0x text, a second viewport) multiplies the
/// images a human has to re-review on each intentional design change. Dark
/// theme is the most defensible thing to add next, and that is an addition
/// rather than an omission.
///
/// ## Platform gate -- READ BEFORE REGENERATING
///
/// These were rasterised on macOS. CI's `quality` job runs `flutter test` on
/// `ubuntu-latest` (.github/workflows/flutter_ci.yml), and rasterisation of
/// gradients, shadows and anti-aliased edges differs between hosts, so one
/// set of PNGs cannot pass on both. They are skipped off macOS rather than
/// left to fail there: a developer on macOS gets the protection, Linux CI
/// stays green and says out loud that it skipped them, and nobody learns to
/// ignore a permanently red job.
///
/// To make them run in CI the images have to be generated *by* CI, on Linux:
/// add a step that runs `flutter test --update-goldens test/golden`, commit
/// its output under `test/golden/goldens/linux/`, and replace this gate with
/// a `goldenFileComparator` that picks a directory per
/// `Platform.operatingSystem`. That needs an edit in .github/, outside this
/// change's scope.
///
/// Regenerate on macOS with:
///
///   flutter test --update-goldens test/golden
///
/// Then LOOK AT every changed PNG before committing it. A golden generated
/// from a buggy frame makes that bug the expected result.
final String? _skipOffMacOS = Platform.isMacOS
    ? null
    : 'Goldens in this file were rasterised on macOS; gradients and '
        'anti-aliasing differ on ${Platform.operatingSystem}. See this '
        "file's header for the Linux generation procedure.";

/// 393x852 -- the iPhone Pro class profile from the shared device matrix. A
/// realistic phone rather than an extreme, because this file is about how the
/// design looks, not about whether it survives being squeezed.
const _goldenSize = iphoneProProfile;
const _goldenPixelRatio = 3.0;

/// Sets the viewport through `tester.view`, NOT through
/// `binding.setSurfaceSize`.
///
/// That distinction is load-bearing and cost this file a round of bad images.
/// `setSurfaceSize` resizes the render surface but leaves `tester.view`
/// reporting the default 800x600, so `MediaQuery.sizeOf` inside the screen
/// still answers 600 while the Scaffold is really 852 tall. SessionSplash
/// sizes its scroll content with
/// `ConstrainedBox(minHeight: MediaQuery.sizeOf(context).height)`, so its
/// first generated golden centred everything in a 600pt box inside an 852pt
/// viewport and left a quarter of the screen blank -- a harness artefact
/// that, committed, would have become the expected result.
///
/// `expectScreenSurvivesLayoutMatrix` avoids the same trap by wrapping its
/// subject in an explicit `MediaQuery`; this does it by fixing the view the
/// `MediaQuery` is derived from, which also keeps the captured image at the
/// device's real pixel ratio.
Future<void> pumpAtGoldenSize(WidgetTester tester, Widget app) async {
  tester.view.devicePixelRatio = _goldenPixelRatio;
  tester.view.physicalSize = _goldenSize.size * _goldenPixelRatio;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(app);
  await pumpForAsyncUi(tester);
}

/// `debugShowCheckedModeBanner: false` is not cosmetic here -- the default
/// banner is painted over the top-right corner, which is where this app keeps
/// its primary app-bar action. It hid the emerald "Send" in the first
/// document-preview golden outright.
Widget _app(Widget home) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme(),
    darkTheme: AppTheme.darkTheme(),
    home: home,
  );
}

/// The same simulation the call-experience layout test uses: with no
/// `signalingService` the controller takes its local branch, and zeroing the
/// three durations lands the session on `connected` by the first pump with no
/// ticker left running -- so the rendered duration is a fixed "0:00" rather
/// than whatever the clock says.
Future<CallsController> _connectedAudioCall(WidgetTester tester) async {
  final controller = CallsController(
    repository: FakeCallsRepository(latency: Duration.zero),
    permissionService: MemoryAppPermissionService(),
    outgoingRingDuration: Duration.zero,
    outgoingConnectingDuration: Duration.zero,
    durationTickInterval: Duration.zero,
  );
  await controller.ensureLoaded();
  final started = await controller.startOutgoingCall(
    contact: controller.favorites.first,
    type: CallType.audio,
  );
  expect(started, isTrue);
  await tester.pump();
  expect(controller.currentSession?.phase, CallSessionPhase.connected);
  return controller;
}

/// A photo whose file is not on disk, so the canvas renders its placeholder.
/// Deliberate: a real decoded image would make the golden a test of the
/// fixture bytes instead of a test of the chrome laid over them. Every label
/// here is a literal, so nothing in this image depends on the clock.
const _photo = ChatAttachment(
  id: 'golden-photo',
  type: ChatAttachmentType.photo,
  title: 'Photo',
  details: 'JPG',
  tintColor: Color(0xFF0E7268),
  localMediaPath: '/golden/photo.jpg',
);

const _document = ChatAttachment(
  id: 'golden-document',
  type: ChatAttachmentType.file,
  title: 'Quarterly handover notes.docx',
  details: 'DOCX · 2.4 MB',
  tintColor: Color(0xFF0E7268),
  localMediaPath: '/golden/handover.docx',
);

void main() {
  // Grouped so the platform gate is declared once and CI prints its reason.
  // (Only `group` accepts a String reason; `testWidgets` takes a bare bool,
  // which would skip these silently.)
  group('settled-screen goldens', _goldens, skip: _skipOffMacOS);
}

void _goldens() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('CallExperienceScreen, connected audio call', (tester) async {
    final controller = await _connectedAudioCall(tester);
    await pumpAtGoldenSize(
      tester,
      _app(CallExperienceScreen(controller: controller)),
    );

    // Proof the image is a real in-call layout: the screen returns
    // SizedBox.shrink() with no session, and a golden of an empty frame would
    // pass forever having asserted nothing.
    expect(find.byKey(const Key('call_experience_screen')), findsOneWidget);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/call_experience_audio_connected.png'),
    );
  });

  testWidgets('AttachmentViewerScreen, photo with every action',
      (tester) async {
    await pumpAtGoldenSize(
      tester,
      _app(
        AttachmentViewerScreen(
          attachments: const [_photo],
          threadName: 'Priya Shah',
          senderName: 'Priya Shah',
          sentAtLabel: 'Today at 9:04 AM',
          isStarred: true,
          onShare: (_) {},
          onSave: (_) {},
          onForward: () {},
          onStar: () {},
          onReply: () {},
          onEdit: () {},
          onDelete: () {},
        ),
      ),
    );

    expect(find.byType(AttachmentViewerScreen), findsOneWidget);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/attachment_viewer_photo.png'),
    );
  });

  testWidgets('DocumentSendPreviewScreen, Word document', (tester) async {
    await pumpAtGoldenSize(
      tester,
      _app(const DocumentSendPreviewScreen(attachment: _document)),
    );

    expect(
      find.byKey(const Key('document_send_preview_screen')),
      findsOneWidget,
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/document_send_preview.png'),
    );
  });

  testWidgets('ProfileSettingsScreen, restored session', (tester) async {
    // runAsync, not a bare await: FakeAuthRepository._wait() arms a
    // Future.delayed even at zero latency, and a fake-async timer does not
    // fire until the first pump -- so awaiting it here would deadlock. Same
    // reasoning as the screen's layout test.
    final authController = AuthController(
      repository: FakeAuthRepository(
        restoredUser: DemoData.currentUser,
        latency: Duration.zero,
      ),
    );
    await tester.runAsync(authController.restoreSession);

    await pumpAtGoldenSize(
      tester,
      _app(
        ProfileSettingsScreen(
          authController: authController,
          currentUser: authController.currentUser ?? DemoData.currentUser,
        ),
      ),
    );

    expect(find.byType(ProfileSettingsScreen), findsOneWidget);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/profile_settings.png'),
    );
  });

  testWidgets('SessionSplashScreen, with a status message', (tester) async {
    // The message state rather than the bare one: it renders strictly more.
    // The string is the longest one AuthController.restoreSession actually
    // sets, matching the layout test's choice.
    await pumpAtGoldenSize(
      tester,
      _app(
        const SessionSplashScreen(
          message: 'No saved session on this device yet.',
        ),
      ),
    );

    expect(find.byType(SessionSplashScreen), findsOneWidget);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/session_splash_with_message.png'),
    );
  });
}
