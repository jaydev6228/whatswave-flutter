import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/features/chats/domain/chat_attachment.dart';
import 'package:whatswave/features/chats/presentation/attachment_viewer_screen.dart';

import '../../../support/device_matrix.dart';

/// A photo whose file isn't actually on disk: the canvas falls back to its
/// placeholder, which keeps these tests about the title bar rather than
/// about decoding an image.
const ChatAttachment _photo = ChatAttachment(
  id: 'viewer-photo',
  type: ChatAttachmentType.photo,
  title: 'Photo',
  details: 'JPG',
  tintColor: Color(0xFF128C7E),
  localMediaPath: '/viewer-test/photo.jpg',
);

const ChatAttachment _location = ChatAttachment(
  id: 'viewer-location',
  type: ChatAttachmentType.location,
  title: 'Marine Drive',
  details: 'Mumbai',
  tintColor: Color(0xFF128C7E),
);

/// Every action key the title bar can show, so a test can assert on the
/// ones it didn't wire up as well as the ones it did.
const Map<String, Key> _actionKeys = {
  'share': Key('attachment_viewer_share_button'),
  'save': Key('attachment_viewer_save_button'),
  'forward': Key('attachment_viewer_forward_button'),
  'star': Key('attachment_viewer_star_button'),
  'reply': Key('attachment_viewer_reply_button'),
  'edit': Key('attachment_viewer_edit_button'),
  'delete': Key('attachment_viewer_delete_button'),
};

Future<void> _pumpViewer(
  WidgetTester tester, {
  ChatAttachment attachment = _photo,
  String? senderName,
  String? sentAtLabel,
  bool isStarred = false,
  void Function(ChatAttachment attachment)? onShare,
  void Function(ChatAttachment attachment)? onSave,
  VoidCallback? onForward,
  VoidCallback? onStar,
  VoidCallback? onReply,
  VoidCallback? onEdit,
  VoidCallback? onDelete,
  TestDeviceProfile device = iphoneProProfile,
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(device.size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: AttachmentViewerScreen(
        attachments: [attachment],
        threadName: 'Priya Shah',
        senderName: senderName,
        sentAtLabel: sentAtLabel,
        isStarred: isStarred,
        onShare: onShare,
        onSave: onSave,
        onForward: onForward,
        onStar: onStar,
        onReply: onReply,
        onEdit: onEdit,
        onDelete: onDelete,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The star action's tooltip, which flips with the message's starred state.
String _starTooltip(WidgetTester tester) {
  return tester
      .widget<Tooltip>(
        find.descendant(
          of: find.byKey(_actionKeys['star']!),
          matching: find.byType(Tooltip),
        ),
      )
      .message!;
}

void main() {
  testWidgets('the title names who sent it and when', (tester) async {
    await _pumpViewer(
      tester,
      senderName: 'Priya Shah',
      sentAtLabel: 'Today at 9:04 AM',
    );

    expect(
      find.byKey(const Key('attachment_viewer_sender_name')),
      findsOneWidget,
    );
    expect(find.text('Priya Shah'), findsOneWidget);
    expect(find.text('Today at 9:04 AM'), findsOneWidget);
  });

  testWidgets('no sender and no timestamp means no title at all',
      (tester) async {
    await _pumpViewer(tester);

    expect(find.byKey(const Key('attachment_viewer_sender_name')), findsNothing);
    expect(find.byKey(const Key('attachment_viewer_sent_at')), findsNothing);
  });

  testWidgets('a caller that supplies no actions gets none', (tester) async {
    await _pumpViewer(
      tester,
      senderName: 'Priya Shah',
      sentAtLabel: 'Today at 9:04 AM',
    );

    // The viewer still opens, and still closes, with every callback null --
    // the shared-media grid opens it exactly this way.
    expect(find.byKey(const Key('attachment_viewer_actions')), findsNothing);
    for (final entry in _actionKeys.entries) {
      expect(find.byKey(entry.value), findsNothing, reason: entry.key);
    }
    expect(
      find.byKey(const Key('attachment_viewer_close_button')),
      findsOneWidget,
    );
  });

  testWidgets('each action shows only when its callback is supplied',
      (tester) async {
    for (final shown in _actionKeys.keys) {
      await _pumpViewer(
        tester,
        // A caption makes the edit action apply, the same way the bubble
        // long-press menu only offers Edit on a message with text.
        onShare: shown == 'share' ? (_) {} : null,
        onSave: shown == 'save' ? (_) {} : null,
        onForward: shown == 'forward' ? () {} : null,
        onStar: shown == 'star' ? () {} : null,
        onReply: shown == 'reply' ? () {} : null,
        onEdit: shown == 'edit' ? () {} : null,
        onDelete: shown == 'delete' ? () {} : null,
      );

      for (final entry in _actionKeys.entries) {
        expect(
          find.byKey(entry.value),
          entry.key == shown ? findsOneWidget : findsNothing,
          reason: '${entry.key} while only $shown is wired up',
        );
      }
    }
  });

  testWidgets('tapping an action runs that callback once', (tester) async {
    final taps = <String>[];
    ChatAttachment? sharedAttachment;
    ChatAttachment? savedAttachment;

    await _pumpViewer(
      tester,
      onShare: (attachment) {
        taps.add('share');
        sharedAttachment = attachment;
      },
      onSave: (attachment) {
        taps.add('save');
        savedAttachment = attachment;
      },
      onForward: () => taps.add('forward'),
      onStar: () => taps.add('star'),
      onReply: () => taps.add('reply'),
      onEdit: () => taps.add('edit'),
      onDelete: () => taps.add('delete'),
    );

    for (final entry in _actionKeys.entries) {
      await tester.tap(find.byKey(entry.value));
      await tester.pumpAndSettle();
      expect(
        taps,
        [entry.key],
        reason: 'tapping ${entry.key} ran ${taps.join(', ')}',
      );
      taps.clear();
    }

    // Share and save act on the attachment on screen, not on the message,
    // so they have to hand it back -- the caller is what turns it into a
    // real local file.
    expect(sharedAttachment?.id, _photo.id);
    expect(savedAttachment?.id, _photo.id);
  });

  testWidgets('the star fills in on tap and offers to unstar', (tester) async {
    await _pumpViewer(tester, onStar: () {});

    expect(_starTooltip(tester), 'Star');

    await tester.tap(find.byKey(_actionKeys['star']!));
    await tester.pumpAndSettle();

    expect(_starTooltip(tester), 'Unstar');
  });

  testWidgets('an already-starred message opens offering to unstar',
      (tester) async {
    await _pumpViewer(tester, isStarred: true, onStar: () {});

    expect(_starTooltip(tester), 'Unstar');
  });

  testWidgets('a location has nothing to save or share', (tester) async {
    await _pumpViewer(
      tester,
      attachment: _location,
      onShare: (_) {},
      onSave: (_) {},
      onForward: () {},
    );

    // There is no file behind a pinned location, so neither the gallery nor
    // another app could be given one.
    expect(find.byKey(_actionKeys['save']!), findsNothing);
    expect(find.byKey(_actionKeys['share']!), findsNothing);
    // The actions that act on the message itself still apply.
    expect(find.byKey(_actionKeys['forward']!), findsOneWidget);
  });

  testWidgets(
      'the title bar fits the narrowest phone at the largest text scale',
      (tester) async {
    await _pumpViewer(
      tester,
      device: smallestPhoneProfile,
      textScale: 2,
      senderName: 'Priyanka Venkataraghavan',
      sentAtLabel: 'Yesterday at 11:58 PM',
      onShare: (_) {},
      onSave: (_) {},
      onForward: () {},
      onStar: () {},
      onReply: () {},
      onEdit: () {},
      onDelete: () {},
    );

    // Seven tap targets no longer fit one line this narrow, so the bar
    // wraps -- what matters is that every action is still on screen and
    // nothing overflowed (which a widget test fails on by itself).
    for (final entry in _actionKeys.entries) {
      expect(find.byKey(entry.value), findsOneWidget, reason: entry.key);
      final rect = tester.getRect(find.byKey(entry.value));
      expect(rect.right, lessThanOrEqualTo(smallestPhoneProfile.size.width),
          reason: entry.key);
      expect(rect.left, greaterThanOrEqualTo(0.0), reason: entry.key);
    }
  });

  testWidgets('a document can be shared but not saved to the gallery',
      (tester) async {
    await _pumpViewer(
      tester,
      attachment: const ChatAttachment(
        id: 'viewer-doc',
        type: ChatAttachmentType.file,
        title: 'Lease.pdf',
        details: 'PDF',
        tintColor: Color(0xFF128C7E),
        localMediaPath: '/viewer-test/lease.pdf',
      ),
      onShare: (_) {},
      onSave: (_) {},
    );

    expect(find.byKey(_actionKeys['share']!), findsOneWidget);
    expect(find.byKey(_actionKeys['save']!), findsNothing);
  });
}
