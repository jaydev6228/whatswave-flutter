import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_palette.dart';
import 'package:whatswave/features/chats/domain/chat_attachment.dart';

ChatAttachment _fileAttachment({String? localMediaPath, String title = 'Doc'}) {
  return ChatAttachment(
    id: 'a1',
    type: ChatAttachmentType.file,
    title: title,
    details: '',
    tintColor: AppPalette.green,
    localMediaPath: localMediaPath,
  );
}

void main() {
  group('ChatAttachment.documentKind', () {
    test('detects pdf from a local path extension', () {
      final attachment = _fileAttachment(localMediaPath: '/tmp/report.pdf');
      expect(attachment.documentKind, ChatDocumentKind.pdf);
    });

    test('detects word/spreadsheet/presentation/text kinds', () {
      expect(
        _fileAttachment(localMediaPath: '/tmp/notes.docx').documentKind,
        ChatDocumentKind.word,
      );
      expect(
        _fileAttachment(localMediaPath: '/tmp/budget.xlsx').documentKind,
        ChatDocumentKind.spreadsheet,
      );
      expect(
        _fileAttachment(localMediaPath: '/tmp/rows.csv').documentKind,
        ChatDocumentKind.spreadsheet,
      );
      expect(
        _fileAttachment(localMediaPath: '/tmp/deck.pptx').documentKind,
        ChatDocumentKind.presentation,
      );
      expect(
        _fileAttachment(localMediaPath: '/tmp/log.txt').documentKind,
        ChatDocumentKind.text,
      );
    });

    test('falls back to title when there is no local path yet', () {
      final attachment = _fileAttachment(title: 'Invoice.pdf');
      expect(attachment.documentKind, ChatDocumentKind.pdf);
    });

    test('falls back to generic for an unrecognized or missing extension', () {
      expect(_fileAttachment(localMediaPath: '/tmp/mystery.xyz').documentKind,
          ChatDocumentKind.generic);
      expect(_fileAttachment().documentKind, ChatDocumentKind.generic);
    });

    test('resolves the extension from a remote download URL with a query string', () {
      final attachment = _fileAttachment(
        localMediaPath:
            'https://storage.example.com/chatMedia/u1/report.pdf?alt=media&token=abc',
      );
      expect(attachment.fileExtension, '.pdf');
      expect(attachment.documentKind, ChatDocumentKind.pdf);
    });
  });

  group('ChatAttachment.isImageDocument', () {
    test('is true for a .file attachment picked with an image extension', () {
      final attachment = _fileAttachment(localMediaPath: '/tmp/scan.jpg');
      expect(attachment.isImageDocument, isTrue);
      expect(attachment.documentKind, ChatDocumentKind.image);
    });

    test('is false for a real document and for non-file attachment types', () {
      expect(_fileAttachment(localMediaPath: '/tmp/report.pdf').isImageDocument,
          isFalse);

      const photo = ChatAttachment(
        id: 'p1',
        type: ChatAttachmentType.photo,
        title: 'Photo',
        details: '',
        tintColor: AppPalette.sky,
        localMediaPath: '/tmp/scan.jpg',
      );
      expect(photo.isImageDocument, isFalse);
    });
  });

  group('documentKindVisual', () {
    test('gives generic and image kinds the fallback tint, others a fixed brand color', () {
      const fallback = AppPalette.purple;
      final (genericIcon, genericColor) =
          documentKindVisual(ChatDocumentKind.generic, fallback);
      final (imageIcon, imageColor) =
          documentKindVisual(ChatDocumentKind.image, fallback);
      final (pdfIcon, pdfColor) = documentKindVisual(ChatDocumentKind.pdf, fallback);

      expect(genericColor, fallback);
      expect(imageColor, fallback);
      expect(pdfColor, isNot(fallback));
      expect(genericIcon, isNotNull);
      expect(imageIcon, isNotNull);
      expect(pdfIcon, isNotNull);
    });
  });
}
