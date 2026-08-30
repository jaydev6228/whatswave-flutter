import 'package:flutter/material.dart';

enum ChatAttachmentType { photo, video, file, location, voiceNote }

/// The broad shape of a [ChatAttachmentType.file] document, detected from
/// its filename extension -- drives which icon/color/preview strategy a
/// document attachment gets (see [documentKindVisual] and
/// [AttachmentViewerScreen]'s document canvas).
enum ChatDocumentKind {
  pdf,
  word,
  spreadsheet,
  presentation,
  text,
  image,
  generic
}

const Map<String, ChatDocumentKind> _documentKindByExtension = {
  '.pdf': ChatDocumentKind.pdf,
  '.doc': ChatDocumentKind.word,
  '.docx': ChatDocumentKind.word,
  '.rtf': ChatDocumentKind.word,
  '.xls': ChatDocumentKind.spreadsheet,
  '.xlsx': ChatDocumentKind.spreadsheet,
  '.csv': ChatDocumentKind.spreadsheet,
  '.ppt': ChatDocumentKind.presentation,
  '.pptx': ChatDocumentKind.presentation,
  '.txt': ChatDocumentKind.text,
  '.jpg': ChatDocumentKind.image,
  '.jpeg': ChatDocumentKind.image,
  '.png': ChatDocumentKind.image,
  '.gif': ChatDocumentKind.image,
  '.webp': ChatDocumentKind.image,
  '.heic': ChatDocumentKind.image,
  '.heif': ChatDocumentKind.image,
  '.bmp': ChatDocumentKind.image,
};

/// The icon + accent color a document attachment's kind should render with,
/// matching the familiar per-format coloring most messaging/file apps use
/// (red PDF, blue Word, green spreadsheet, etc). [fallbackTint] is used for
/// kinds with no strong brand color of their own (image/generic).
(IconData, Color) documentKindVisual(
  ChatDocumentKind kind,
  Color fallbackTint,
) {
  return switch (kind) {
    ChatDocumentKind.pdf => (
        Icons.picture_as_pdf_rounded,
        const Color(0xFFE2483D)
      ),
    ChatDocumentKind.word => (
        Icons.description_rounded,
        const Color(0xFF2B7DE9)
      ),
    ChatDocumentKind.spreadsheet => (
        Icons.table_chart_rounded,
        const Color(0xFF1F9D55)
      ),
    ChatDocumentKind.presentation => (
        Icons.slideshow_rounded,
        const Color(0xFFE8710A)
      ),
    ChatDocumentKind.text => (Icons.article_outlined, const Color(0xFF6B7280)),
    ChatDocumentKind.image => (Icons.image_outlined, fallbackTint),
    ChatDocumentKind.generic => (
        Icons.insert_drive_file_outlined,
        fallbackTint
      ),
  };
}

class ChatAttachment {
  const ChatAttachment({
    required this.id,
    required this.type,
    required this.title,
    required this.details,
    required this.tintColor,
    this.aspectRatio = 1.25,
    this.latitude,
    this.longitude,
    this.localMediaPath,
  });

  final String id;
  final ChatAttachmentType type;
  final String title;
  final String details;
  final Color tintColor;
  final double aspectRatio;

  /// Set only for [ChatAttachmentType.location] messages carrying a real
  /// device fix -- null for every other attachment type.
  final double? latitude;
  final double? longitude;

  /// A device-local media path (or a bundled `asset://` path) immediately
  /// after picking, before upload finishes. Once
  /// [FirestoreChatRepository]'s upload step completes, this holds a
  /// Firebase Storage download URL instead, which is what every reader
  /// (any device, not just the one that sent it) actually resolves. Null
  /// falls back to [tintColor] as a plain placeholder swatch.
  final String? localMediaPath;

  bool get hasCoordinates => latitude != null && longitude != null;

  String _fileNameForKindDetection() {
    final path = localMediaPath?.trim();
    if (path != null && path.isNotEmpty) {
      return path;
    }
    return title;
  }

  /// The lowercased filename extension (including the dot), or empty when
  /// none can be determined. Parses as a URI first and reads its `path` --
  /// a Firebase Storage download URL carries `?alt=media&token=...` after
  /// the real filename, which a naive `lastIndexOf('.')` on the raw string
  /// would swallow into the "extension".
  String get fileExtension {
    final name = _fileNameForKindDetection();
    final path = Uri.tryParse(name)?.path ?? name;
    final lastSlash = path.lastIndexOf('/');
    final filename = lastSlash == -1 ? path : path.substring(lastSlash + 1);
    final lastDot = filename.lastIndexOf('.');
    if (lastDot <= 0 || lastDot == filename.length - 1) {
      return '';
    }
    return filename.substring(lastDot).toLowerCase();
  }

  ChatDocumentKind get documentKind =>
      _documentKindByExtension[fileExtension] ?? ChatDocumentKind.generic;

  /// A [ChatAttachmentType.file] attachment whose extension is actually a
  /// photo format (picked via the Files app rather than the photo picker,
  /// same as WhatsApp treating any image file as a photo) -- renders as a
  /// real thumbnail/zoomable image instead of a generic document card.
  bool get isImageDocument =>
      type == ChatAttachmentType.file && documentKind == ChatDocumentKind.image;

  String get compactLabel {
    return switch (type) {
      ChatAttachmentType.photo => 'Photo',
      ChatAttachmentType.video =>
        details.trim().isEmpty ? 'Video' : 'Video · ${details.trim()}',
      ChatAttachmentType.file =>
        title.trim().isEmpty ? 'File' : 'File · ${title.trim()}',
      ChatAttachmentType.location =>
        title.trim().isEmpty ? 'Location' : 'Location · ${title.trim()}',
      ChatAttachmentType.voiceNote => details.trim().isEmpty
          ? 'Voice note'
          : 'Voice note · ${details.trim()}',
    };
  }

  ChatAttachment copyWith({
    String? id,
    ChatAttachmentType? type,
    String? title,
    String? details,
    Color? tintColor,
    double? aspectRatio,
    double? latitude,
    double? longitude,
    String? localMediaPath,
  }) {
    return ChatAttachment(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      details: details ?? this.details,
      tintColor: tintColor ?? this.tintColor,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      localMediaPath: localMediaPath ?? this.localMediaPath,
    );
  }
}
