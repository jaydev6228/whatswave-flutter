import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../updates/presentation/widgets/status_media_source.dart';
import '../../domain/chat_attachment.dart';
import 'video_thumbnail_source.dart';

/// The image layer shared by conversation bubbles and the shared-media
/// grid -- both surfaces hit the same photo decode budget and the same
/// [videoThumbnailFor] cache (memory + disk), so a frame extracted for a
/// chat bubble is reused when that attachment appears in Shared media.
class ChatMediaThumbnailBody extends StatefulWidget {
  const ChatMediaThumbnailBody({
    required this.attachment,
    required this.maxDecodeWidth,
    this.suppressRemoteMedia = false,
    this.hidePlaceholderIcon = false,
    super.key,
  });

  final ChatAttachment attachment;
  final int maxDecodeWidth;

  /// Render the placeholder instead of fetching, while a download gate is
  /// still offering to fetch.
  final bool suppressRemoteMedia;

  /// When a download button or transfer ring is already centred over the
  /// tile, the type icon underneath must stand down.
  final bool hidePlaceholderIcon;

  @override
  State<ChatMediaThumbnailBody> createState() => _ChatMediaThumbnailBodyState();
}

class _ChatMediaThumbnailBodyState extends State<ChatMediaThumbnailBody> {
  Future<Uint8List?>? _videoThumbnailFuture;

  @override
  void initState() {
    super.initState();
    _primeVideoThumbnail();
  }

  @override
  void didUpdateWidget(covariant ChatMediaThumbnailBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.id != widget.attachment.id ||
        oldWidget.attachment.localMediaPath !=
            widget.attachment.localMediaPath) {
      _primeVideoThumbnail();
    }
  }

  void _primeVideoThumbnail() {
    final localPath = widget.attachment.localMediaPath;
    if (widget.attachment.type == ChatAttachmentType.video &&
        localPath != null &&
        statusMediaSourceExists(localPath) &&
        !_isGated(localPath)) {
      _videoThumbnailFuture = videoThumbnailFor(localPath);
      return;
    }
    _videoThumbnailFuture = null;
  }

  bool _isGated(String localPath) {
    return widget.suppressRemoteMedia && isRemoteStatusMediaPath(localPath);
  }

  @override
  Widget build(BuildContext context) {
    final attachment = widget.attachment;
    final localPath = attachment.localMediaPath;
    final isPhoto = attachment.type == ChatAttachmentType.photo ||
        attachment.isImageDocument;
    final isGated = localPath != null && _isGated(localPath);
    final hasRealPhoto = isPhoto &&
        !isGated &&
        localPath != null &&
        statusMediaSourceExists(localPath);
    final hasRealVideo = attachment.type == ChatAttachmentType.video &&
        !isGated &&
        localPath != null &&
        statusMediaSourceExists(localPath);

    if (hasRealPhoto) {
      return Image(
        image: imageProviderForStatusMediaPath(
          localPath,
          maxDecodeWidth: widget.maxDecodeWidth,
        )!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            return child;
          }
          return _loadingPlaceholder(attachment);
        },
        errorBuilder: (_, __, ___) => _typePlaceholder(attachment),
      );
    }

    if (hasRealVideo) {
      return FutureBuilder<Uint8List?>(
        future: _videoThumbnailFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _loadingPlaceholder(attachment);
          }
          final bytes = snapshot.data;
          if (bytes == null) {
            return _typePlaceholder(attachment, video: true);
          }
          return Image.memory(
            bytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) =>
                _typePlaceholder(attachment, video: true),
          );
        },
      );
    }

    return _typePlaceholder(
      attachment,
      video: attachment.type == ChatAttachmentType.video,
    );
  }

  Widget _typePlaceholder(
    ChatAttachment attachment, {
    bool video = false,
  }) {
    return ColoredBox(
      color: attachment.tintColor.withValues(alpha: 0.18),
      child: widget.hidePlaceholderIcon
          ? const SizedBox.expand()
          : Center(
              child: Icon(
                video ? Icons.videocam_outlined : Icons.photo_outlined,
                color: attachment.tintColor,
                size: 32,
              ),
            ),
    );
  }

  static Widget _loadingPlaceholder(ChatAttachment attachment) {
    return ColoredBox(
      color: attachment.tintColor.withValues(alpha: 0.18),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: attachment.tintColor,
          ),
        ),
      ),
    );
  }
}
