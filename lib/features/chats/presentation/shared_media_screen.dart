import 'package:flutter/material.dart';

import '../../updates/presentation/widgets/status_media_source.dart';
import '../domain/chat_attachment.dart';
import 'attachment_viewer_screen.dart';

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
          padding: const EdgeInsets.all(4),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemCount: attachments.length,
          itemBuilder: (context, index) {
            final attachment = attachments[index];
            return SharedMediaThumbnail(
              attachment: attachment,
              tileKey: Key('shared_media_${attachment.id}'),
              onTap: () => showAttachmentPreview(
                context,
                attachment: attachment,
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
    final hasRealPhoto = attachment.type == ChatAttachmentType.photo &&
        localPath != null &&
        statusMediaSourceExists(localPath);

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: tileKey,
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasRealPhoto)
                Image(
                  image: imageProviderForStatusMediaPath(localPath)!,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) {
                      return child;
                    }
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
                  },
                )
              else
                ColoredBox(
                  color: attachment.tintColor.withValues(alpha: 0.18),
                  child: Icon(
                    attachment.type == ChatAttachmentType.video
                        ? Icons.videocam_outlined
                        : Icons.photo_outlined,
                    color: attachment.tintColor,
                  ),
                ),
              if (attachment.type == ChatAttachmentType.video)
                const Center(
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
