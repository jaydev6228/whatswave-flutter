import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/features/chats/domain/chat_attachment.dart';
import 'package:whatswave/features/chats/presentation/attachment_viewer_screen.dart';

import '../../support/device_matrix.dart';

/// A photo whose file isn't on disk, so the canvas falls back to its
/// placeholder -- this is about the floating title bar, not image decoding.
const _photo = ChatAttachment(
  id: 'viewer-photo',
  type: ChatAttachmentType.photo,
  title: 'Photo',
  details: 'JPG',
  tintColor: Color(0xFF128C7E),
  localMediaPath: '/viewer-layout-test/photo.jpg',
);

/// A Word document: the one document canvas that needs no real bytes (a
/// .pdf would hand pdfx a file that isn't there).
const _document = ChatAttachment(
  id: 'viewer-document',
  type: ChatAttachmentType.file,
  title: 'Quarterly handover notes revision three.docx',
  details: 'DOCX · 2.4 MB',
  tintColor: Color(0xFF128C7E),
  localMediaPath: '/viewer-layout-test/handover.docx',
);

void main() {
  testWidgets(
      'AttachmentViewerScreen survives the layout matrix with every action',
      (tester) async {
    await expectScreenSurvivesLayoutMatrix(
      tester,
      build: () => MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: AttachmentViewerScreen(
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
  });

  testWidgets('AttachmentViewerScreen document canvas survives the matrix',
      (tester) async {
    await expectScreenSurvivesLayoutMatrix(
      tester,
      build: () => MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: AttachmentViewerScreen(
          attachments: const [_document],
          threadName: 'Priya Shah',
          senderName: 'You',
          sentAtLabel: 'Yesterday at 11:58 PM',
          onShare: (_) {},
          onSave: (_) {},
          onForward: () {},
        ),
      ),
    );
  });
}
