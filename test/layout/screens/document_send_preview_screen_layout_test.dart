import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/features/chats/domain/chat_attachment.dart';
import 'package:whatswave/features/chats/presentation/document_send_preview_screen.dart';

import '../../support/device_matrix.dart';

/// A long filename on purpose: the file card is a Row of icon + name +
/// size, which is where a document title with no room left overflows.
const _document = ChatAttachment(
  id: 'send-document',
  type: ChatAttachmentType.file,
  title: 'Quarterly handover notes revision three final.docx',
  details: 'DOCX · 2.4 MB',
  tintColor: Color(0xFF128C7E),
  localMediaPath: '/document-send-layout-test/handover.docx',
);

void main() {
  testWidgets('DocumentSendPreviewScreen survives the layout matrix',
      (tester) async {
    await expectScreenSurvivesLayoutMatrix(
      tester,
      build: () => MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: const DocumentSendPreviewScreen(attachment: _document),
      ),
    );
  });
}
