import 'package:flutter/material.dart';

import '../../updates/presentation/widgets/status_media_source.dart';
import '../domain/chat_attachment.dart';
import 'attachment_viewer_screen.dart';
import 'widgets/chat_media_thumbnail.dart';

/// Widest a grid tile can get, and the basis of the thumbnail decode
/// budget -- one constant so the two cannot drift apart.
const double _maxTileExtent = 108;

/// The full "Shared media" grid for a conversation -- reached by tapping
/// the summary row in ContactInfoScreen (see the disclosure row built
/// there), which shows only a small preview thumbnail and an item count
/// so a thread with a lot of shared media doesn't push the rest of
/// contact info (common groups, destructive actions) further down the
/// scroll than it needs to.
class SharedMediaScreen extends StatelessWidget {
  const SharedMediaScreen({
    required this.attachments,
    required this.threadName,
    super.key,
  });

  final List<ChatAttachment> attachments;
  final String threadName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shared media')),
      body: SafeArea(
        top: false,
        child: GridView.builder(
          key: const Key('shared_media_screen_grid'),
          // Flush, gapless tiles like WhatsApp's own shared-media grid --
          // padding and inter-tile gaps only shrink the media itself.
          padding: EdgeInsets.zero,
          // Width-driven rather than a hardcoded count: columns work out to
          // ceil(width / 108), which is 4 across every phone width (90pt
          // tiles on a 360pt Android, 98pt on an iPhone Pro) and 7-8 on a
          // tablet. A hardcoded 4 would give a tablet four enormous tiles;
          // the old hardcoded 3 gave a phone 125pt tiles and barely 18 on
          // screen, where this fits ~32.
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: _maxTileExtent,
            crossAxisSpacing: 0,
            mainAxisSpacing: 0,
          ),
          itemCount: attachments.length,
          itemBuilder: (context, index) {
            final attachment = attachments[index];
            return SharedMediaThumbnail(
              attachment: attachment,
              tileKey: Key('shared_media_${attachment.id}'),
              onTap: () => showAttachmentPreview(
                context,
                attachments: attachments,
                initialIndex: index,
                threadName: threadName,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A single square media tile -- shared between [SharedMediaScreen]'s full
/// grid and ContactInfoScreen's disclosure-row preview (there with [onTap]
/// left null, since the row itself is what's tappable in that context, not
/// the individual thumbnail). [tileKey] is separate from the widget's own
/// [key] and only ever passed by the grid -- the disclosure row's preview
/// leaves it null so the same attachment doesn't briefly exist under the
/// same key in two mounted routes at once (contact info and the pushed
/// full-grid screen).
class SharedMediaThumbnail extends StatelessWidget {
  const SharedMediaThumbnail({
    required this.attachment,
    this.onTap,
    this.tileKey,
    super.key,
  });

  final ChatAttachment attachment;
  final VoidCallback? onTap;
  final Key? tileKey;

  @override
  Widget build(BuildContext context) {
    final localPath = attachment.localMediaPath;
    final hasResolvableVideo = attachment.type == ChatAttachmentType.video &&
        localPath != null &&
        statusMediaSourceExists(localPath);
    final decodeWidth =
        (_maxTileExtent * MediaQuery.devicePixelRatioOf(context)).round();

    // No ClipRRect/rounded corners: WhatsApp's shared-media grid is flush
    // tiles, and rounding each one both wastes grid space and costs a clip
    // layer per tile.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: tileKey,
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ChatMediaThumbnailBody(
              attachment: attachment,
              maxDecodeWidth: decodeWidth,
            ),
            if (hasResolvableVideo)
              const Positioned(
                right: 3,
                bottom: 3,
                child: _SharedMediaVideoBadge(),
              ),
          ],
        ),
      ),
    );
  }
}

/// Corner video glyph for shared-media grid tiles -- a tiny dark scrim
/// behind the white icon so it reads on both bright and dark thumbnails.
class _SharedMediaVideoBadge extends StatelessWidget {
  const _SharedMediaVideoBadge();

  static const Color _scrim = Color(0xB3000000);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _scrim,
        borderRadius: BorderRadius.circular(5),
      ),
      child: const Padding(
        padding: EdgeInsets.all(4.5),
        child: Icon(
          Icons.videocam_rounded,
          color: Colors.white,
          size: 16,
        ),
      ),
    );
  }
}
