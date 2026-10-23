import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdfx/pdfx.dart';
import 'package:video_player/video_player.dart';

import '../../../app/theme/app_palette.dart';
import '../../shared/widgets/liquid_glass.dart';
import '../../updates/presentation/widgets/status_media_source.dart';
import '../domain/chat_attachment.dart';
import 'widgets/location_map_preview.dart';
import '../../shared/swipe_down_to_dismiss.dart';

/// Shown as an in-place overlay over the current screen (see
/// [showAttachmentPreview]) rather than pushed as a separate route -- a
/// full-bleed canvas under a floating title bar, no AppBar/back-chevron
/// chrome pretending it's a whole new screen.
///
/// The title bar floats over the canvas (a [Stack], not a [Column] that
/// pushes the media down under a separate header bar) so it always reads
/// correctly whether the canvas underneath is the black photo/video
/// background or a themed placeholder/document card -- a frosted glass
/// circle adapts to whatever's behind it, unlike a solid app-bar-style row
/// that only matched some of those backgrounds. Ignores the bottom safe
/// area entirely (the canvas and any per-canvas bottom controls, like the
/// video control bar or the map's "Open in Maps" button, already handle
/// their own bottom inset) so there's no stray blank gap above the home
/// indicator.
class AttachmentViewerScreen extends StatefulWidget {
  const AttachmentViewerScreen({
    required this.attachments,
    required this.threadName,
    this.initialIndex = 0,
    this.senderName,
    this.sentAtLabel,
    this.isStarred = false,
    this.onShare,
    this.onSave,
    this.onForward,
    this.onStar,
    this.onReply,
    this.onEdit,
    this.onDelete,
    super.key,
  }) : assert(attachments.length > 0, 'nothing to preview');

  /// Every attachment the tapped one arrived with, in bubble order.
  ///
  /// A message that bundles sixteen photos shows four in the bubble; the
  /// other twelve are only reachable here, so the viewer pages the whole
  /// album rather than the single tile that opened it.
  final List<ChatAttachment> attachments;
  final String threadName;
  final int initialIndex;

  /// Who sent the message these attachments came with ("You" for your own).
  final String? senderName;

  /// When it was sent, already formatted by the caller.
  ///
  /// A pre-formatted string rather than a [DateTime]: the day/clock
  /// formatting the message list uses lives with the message list, and the
  /// title has to read the same as the timestamp under the bubble the viewer
  /// was opened from -- formatting it a second time here is how those two
  /// drift apart.
  final String? sentAtLabel;

  /// Whether the message is starred, which flips the star action's
  /// icon/tooltip the same way the long-press menu's star row does.
  final bool isStarred;

  /// Every action is optional, and an action with no callback simply isn't
  /// offered -- the shared-media grid opens this viewer with no message
  /// context at all, so there is nothing there to forward, star or delete.
  ///
  /// Share and save act on the attachment currently paged to, not the
  /// message, so they hand it back; resolving it to a real local file (a
  /// Storage URL for anyone but the sender, ciphertext when encrypted) is
  /// the caller's job, since it already owns that pipeline.
  final void Function(ChatAttachment attachment)? onShare;
  final void Function(ChatAttachment attachment)? onSave;
  final VoidCallback? onForward;
  final VoidCallback? onStar;
  final VoidCallback? onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  State<AttachmentViewerScreen> createState() => _AttachmentViewerScreenState();
}

/// The one fixed dark-glass tint every piece of this viewer's chrome uses --
/// see the close button for why it ignores the app theme.
final Color _chromeTint = Colors.black.withValues(alpha: 0.42);

class _AttachmentViewerScreenState extends State<AttachmentViewerScreen> {
  late final PageController _pageController;
  late int _index;

  /// Mirrors [AttachmentViewerScreen.isStarred] so the star fills in the
  /// moment it's tapped. The viewer is an overlay over a message list it
  /// doesn't listen to, so without a local copy the icon would keep showing
  /// the state the message had when the viewer opened.
  late bool _isStarred;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.attachments.length - 1);
    _pageController = PageController(initialPage: _index);
    _isStarred = widget.isStarred;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// The navigation title: who sent this and when, the context the message
  /// list gives a bubble and a full-screen canvas otherwise throws away.
  /// Null when the caller supplied neither, which is what keeps the
  /// pre-existing bare-canvas presentation for callers that have no message
  /// behind the attachment.
  Widget? _buildTitle() {
    final senderName = widget.senderName?.trim() ?? '';
    final sentAtLabel = widget.sentAtLabel?.trim() ?? '';
    if (senderName.isEmpty && sentAtLabel.isEmpty) {
      return null;
    }
    return LiquidGlassSurface(
      borderRadius: BorderRadius.circular(16),
      color: _chromeTint,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (senderName.isNotEmpty)
            Text(
              senderName,
              key: const Key('attachment_viewer_sender_name'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (sentAtLabel.isNotEmpty)
            Text(
              sentAtLabel,
              key: const Key('attachment_viewer_sent_at'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  /// The actions that make sense for [current], in WhatsApp's order.
  List<Widget> _buildActions(ChatAttachment current) {
    final onShare = widget.onShare;
    final onSave = widget.onSave;
    final onStar = widget.onStar;

    // Sharing and saving both hand another app the file itself, so an
    // attachment that is only coordinates has nothing to give it.
    final hasFile = (current.localMediaPath ?? '').trim().isNotEmpty;
    // Gal only takes images and videos, so there is nothing a document or a
    // pinned location could put in the gallery.
    final isSavable = hasFile &&
        (current.type == ChatAttachmentType.photo ||
            current.type == ChatAttachmentType.video ||
            current.isImageDocument);

    return [
      if (onShare != null && hasFile)
        _ViewerActionButton(
          key: const Key('attachment_viewer_share_button'),
          icon: Icons.share_rounded,
          tooltip: 'Share',
          onTap: () => onShare(current),
        ),
      if (onSave != null && isSavable)
        _ViewerActionButton(
          key: const Key('attachment_viewer_save_button'),
          icon: Icons.download_rounded,
          tooltip: 'Save to gallery',
          onTap: () => onSave(current),
        ),
      if (widget.onForward != null)
        _ViewerActionButton(
          key: const Key('attachment_viewer_forward_button'),
          icon: Icons.forward_rounded,
          tooltip: 'Forward',
          onTap: widget.onForward!,
        ),
      if (onStar != null)
        _ViewerActionButton(
          key: const Key('attachment_viewer_star_button'),
          icon: _isStarred ? Icons.star_rounded : Icons.star_border_rounded,
          tooltip: _isStarred ? 'Unstar' : 'Star',
          onTap: () {
            setState(() => _isStarred = !_isStarred);
            onStar();
          },
        ),
      if (widget.onReply != null)
        _ViewerActionButton(
          key: const Key('attachment_viewer_reply_button'),
          icon: Icons.reply_rounded,
          tooltip: 'Reply',
          onTap: widget.onReply!,
        ),
      if (widget.onEdit != null)
        _ViewerActionButton(
          key: const Key('attachment_viewer_edit_button'),
          icon: Icons.edit_outlined,
          tooltip: 'Edit',
          onTap: widget.onEdit!,
        ),
      if (widget.onDelete != null)
        _ViewerActionButton(
          key: const Key('attachment_viewer_delete_button'),
          icon: Icons.delete_outline_rounded,
          tooltip: 'Delete',
          onTap: widget.onDelete!,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final attachments = widget.attachments;
    final hasAlbum = attachments.length > 1;
    final current = attachments[_index];
    final title = _buildTitle();
    final actions = _buildActions(current);

    return Semantics(
      // The visible title names the sender, not the thread, so this is
      // still what gives screen-reader users the context sighted users get
      // from the surrounding conversation.
      label: hasAlbum
          ? '${current.compactLabel} from ${widget.threadName}, '
              '${_index + 1} of ${attachments.length}'
          : '${current.compactLabel} from ${widget.threadName}',
      container: true,
      // Swipe down to close, the same gesture the story viewer uses -- the
      // standard way out of any full-screen media presentation.
      child: SwipeDownToDismiss(
        key: const Key('attachment_viewer_swipe_dismiss'),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!hasAlbum)
              _AttachmentCanvas(attachment: attachments.single)
            else
              PageView.builder(
                key: const Key('attachment_viewer_pager'),
                controller: _pageController,
                itemCount: attachments.length,
                onPageChanged: (index) => setState(() => _index = index),
                itemBuilder: (context, index) => _AttachmentCanvas(
                  attachment: attachments[index],
                ),
              ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          LiquidGlassIconButton(
                            key: const Key('attachment_viewer_close_button'),
                            icon: Icons.close_rounded,
                            tooltip: 'Close',
                            // visualSize, not size: the glass circle shrinks
                            // to sit level with the "6 of 11" pill opposite
                            // it, while the tap target stays at the 44pt
                            // minimum.
                            visualSize: 32,
                            iconSize: 18,
                            onTap: () => Navigator.of(context).pop(),
                            // A fixed dark-glass chrome regardless of app
                            // theme -- this floats over media/black canvases,
                            // not the app's own surface, so it must stay
                            // legible in both light and dark mode (same
                            // reasoning as the video control bar's buttons
                            // and in-call controls).
                            color: _chromeTint,
                            iconColor: Colors.white,
                          ),
                          // Expanded rather than a Spacer: the title is what
                          // absorbs the slack, so a long sender name
                          // ellipsizes instead of pushing the page pill off
                          // the right edge (docs/ui_layout_guidelines.md
                          // rule 6).
                          Expanded(
                            child: title == null
                                ? const SizedBox.shrink()
                                : Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    child: title,
                                  ),
                          ),
                          if (hasAlbum)
                            LiquidGlassSurface(
                              borderRadius: BorderRadius.circular(999),
                              color: _chromeTint,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              child: Text(
                                '${_index + 1} of ${attachments.length}',
                                key: const Key('attachment_viewer_page_label'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (actions.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          // A Wrap, not a Row: seven 48pt tap targets stop
                          // fitting one line on a compact phone at a large
                          // Android display size, and a second line is the
                          // right failure mode for a bar of actions
                          // (docs/ui_layout_guidelines.md rule 6). The bar
                          // sits up here rather than along the bottom
                          // because a video's own control bar already owns
                          // that edge.
                          child: Wrap(
                            key: const Key('attachment_viewer_actions'),
                            alignment: WrapAlignment.end,
                            children: actions,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One action in the viewer's title bar, in the same chrome as the close
/// button beside it.
class _ViewerActionButton extends StatelessWidget {
  const _ViewerActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LiquidGlassIconButton(
      icon: icon,
      tooltip: tooltip,
      visualSize: 32,
      iconSize: 18,
      onTap: onTap,
      color: _chromeTint,
      iconColor: Colors.white,
    );
  }
}

/// Presents [AttachmentViewerScreen] as a full-screen overlay (fade + scale)
/// on top of the current screen instead of navigating to a new route.
Future<void> showAttachmentPreview(
  BuildContext context, {
  required List<ChatAttachment> attachments,
  required String threadName,
  int initialIndex = 0,
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
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierLabel: attachments[initialIndex].title,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, __) {
      return Dialog.fullscreen(
        backgroundColor: Theme.of(context).colorScheme.surface,
        child: AttachmentViewerScreen(
          attachments: attachments,
          initialIndex: initialIndex,
          threadName: threadName,
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
      );
    },
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _AttachmentCanvas extends StatefulWidget {
  const _AttachmentCanvas({required this.attachment});

  final ChatAttachment attachment;

  @override
  State<_AttachmentCanvas> createState() => _AttachmentCanvasState();
}

class _AttachmentCanvasState extends State<_AttachmentCanvas> {
  /// Same contract as the thumbnail's: identical to
  /// `attachment.localMediaPath` for plaintext media, a decrypted temp
  /// file for encrypted media.
  String? _resolvedPath;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _AttachmentCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.id != widget.attachment.id ||
        oldWidget.attachment.mediaKey != widget.attachment.mediaKey) {
      _resolve();
    }
  }

  void _resolve() {
    final attachment = widget.attachment;
    if (attachment.mediaKey == null) {
      _resolvedPath = attachment.localMediaPath;
      return;
    }
    _resolvedPath = null;
    unawaited(
      resolveAttachmentMediaPath(attachment).then((path) {
        if (mounted && widget.attachment.id == attachment.id) {
          setState(() => _resolvedPath = path);
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final attachment = widget.attachment;
    final localPath = _resolvedPath;
    final isImageLike = attachment.type == ChatAttachmentType.photo ||
        attachment.isImageDocument;
    final hasRealMedia = localPath != null &&
        statusMediaSourceExists(localPath) &&
        (isImageLike || attachment.type == ChatAttachmentType.video);

    if (hasRealMedia) {
      // Full-bleed, no corner rounding, and pinch/double-tap-to-zoom via
      // InteractiveViewer -- matching a real photo viewer instead of the
      // constrained, rounded card every other (placeholder) attachment
      // type still uses below.
      return ColoredBox(
        color: Colors.black,
        child: isImageLike
            ? _ZoomableImage(
                imageProvider: imageProviderForStatusMediaPath(localPath)!,
                errorBuilder: () =>
                    _AttachmentPlaceholderCanvas(attachment: attachment),
              )
            : _AttachmentVideoCanvas(localMediaPath: localPath),
      );
    }

    final hasRealDocument = localPath != null &&
        localPath.trim().isNotEmpty &&
        attachment.type == ChatAttachmentType.file &&
        !isBundledStatusMediaPath(localPath);
    if (hasRealDocument) {
      // Real in-app rendering for formats that have a practical renderer
      // (PDF via pdfx, plain text/CSV by just reading the bytes) --
      // everything else (Word/Excel/PowerPoint, or if in-app rendering
      // itself fails) falls back to the OS's own native viewer, which is
      // still a real, full-fidelity preview, just outside this app's
      // direct control.
      final kind = attachment.documentKind;
      if (kind == ChatDocumentKind.pdf) {
        return _PdfDocumentCanvas(attachment: attachment);
      }
      if (kind == ChatDocumentKind.text || attachment.fileExtension == '.csv') {
        return _TextDocumentCanvas(attachment: attachment);
      }
      return _DocumentPreviewCanvas(attachment: attachment);
    }

    if (attachment.type == ChatAttachmentType.location &&
        attachment.hasCoordinates) {
      return LocationMapCanvas(
        latitude: attachment.latitude!,
        longitude: attachment.longitude!,
        label: attachment.title,
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: AspectRatio(
          aspectRatio: attachment.aspectRatio,
          child: _AttachmentPlaceholderCanvas(attachment: attachment),
        ),
      ),
    );
  }
}

/// Resolves an attachment's media path to a real local file path, on-device
/// -- a Storage-uploaded attachment's `localMediaPath` is a download URL by
/// the time anyone but the sender views it, but every renderer here (PDF,
/// text, or the OS's own native viewer) needs an actual local file, not a
/// URL. Downloads to a temp file the first time; harmless to call again for
/// an already-local path, which is returned unchanged.
/// A local path for an attachment the OS or an in-app renderer can open.
///
/// Delegates to [resolveAttachmentMediaPath], which decrypts an encrypted
/// attachment and verifies its MAC first. That also fixed a pre-existing
/// inefficiency here: this used to `http.get` the file directly, bypassing
/// the shared disk cache entirely, so opening the same document twice
/// downloaded it twice.
Future<String> _resolveAttachmentLocalPath(
  ChatAttachment attachment,
  String path,
) async {
  if (!isRemoteStatusMediaPath(path)) {
    return path;
  }
  final resolved = await resolveAttachmentMediaPath(attachment);
  if (resolved == null) {
    throw Exception('This attachment could not be opened.');
  }
  return resolved;
}

/// A document attachment with no practical in-app renderer here
/// (Word/Excel/PowerPoint) -- opens the file in the OS's own native viewer
/// (QuickLook on iOS, an Intent chooser on Android) instead, which is still
/// a real, full-fidelity preview of the actual document, just outside this
/// app's direct control. Also the failure fallback other document canvases
/// (PDF, text) offer when in-app rendering itself doesn't work.
class _DocumentPreviewCanvas extends StatefulWidget {
  const _DocumentPreviewCanvas({required this.attachment});

  final ChatAttachment attachment;

  @override
  State<_DocumentPreviewCanvas> createState() => _DocumentPreviewCanvasState();
}

class _DocumentPreviewCanvasState extends State<_DocumentPreviewCanvas> {
  bool _isOpening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openDocument());
  }

  Future<void> _openDocument() async {
    final rawPath = widget.attachment.localMediaPath?.trim();
    if (rawPath == null || rawPath.isEmpty || !mounted) {
      return;
    }
    setState(() {
      _isOpening = true;
      _error = null;
    });
    try {
      final localPath =
          await _resolveAttachmentLocalPath(widget.attachment, rawPath);
      final result = await OpenFilex.open(localPath);
      if (result.type != ResultType.done && mounted) {
        setState(() {
          _error = result.message.trim().isNotEmpty
              ? result.message
              : 'Could not open this document.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Could not open this document. Check your connection and try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isOpening = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = documentKindVisual(
        widget.attachment.documentKind, widget.attachment.tintColor);

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundColor: color.withValues(alpha: 0.22),
                  child: Icon(icon, size: 42, color: color),
                ),
                const SizedBox(height: 18),
                Text(
                  widget.attachment.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.attachment.details,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.68),
                  ),
                ),
                const SizedBox(height: 22),
                if (_error != null) ...[
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                FilledButton.icon(
                  key: const Key('attachment_viewer_open_document_button'),
                  onPressed: _isOpening ? null : _openDocument,
                  icon: _isOpening
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.open_in_new_rounded),
                  label: Text(_isOpening ? 'Opening…' : 'Open document'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A shared error state for the in-app document canvases ([_PdfDocumentCanvas],
/// [_TextDocumentCanvas]) -- offers a retry (transient network/read
/// failures are common for a Storage-hosted attachment) and, per the
/// "if it's hard to preview in-app, fall back to the current flow"
/// direction, a way to still open it in the OS's own native viewer.
class _DocumentErrorFallback extends StatelessWidget {
  const _DocumentErrorFallback({
    required this.attachment,
    required this.message,
    required this.onRetry,
  });

  final ChatAttachment attachment;
  final String message;
  final VoidCallback onRetry;

  Future<void> _openExternally() async {
    final rawPath = attachment.localMediaPath?.trim();
    if (rawPath == null || rawPath.isEmpty) {
      return;
    }
    try {
      final localPath = await _resolveAttachmentLocalPath(attachment, rawPath);
      await OpenFilex.open(localPath);
    } catch (_) {
      // Best-effort -- there's no further fallback beyond this one, and the
      // visible error state already told the reader something's wrong.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) =
        documentKindVisual(attachment.documentKind, attachment.tintColor);

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: color.withValues(alpha: 0.22),
                  child: Icon(icon, size: 38, color: color),
                ),
                const SizedBox(height: 16),
                Text(
                  attachment.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('attachment_viewer_document_retry_button'),
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try again'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                      ),
                    ),
                    FilledButton.icon(
                      key: const Key('attachment_viewer_open_document_button'),
                      onPressed: _openExternally,
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Open externally'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A real PDF, rendered and paginated in-app (pinch-zoom, page scroll) via
/// pdfx rather than handed off to the OS viewer -- matches the pinch/zoom
/// convention this app's photo viewer already uses.
class _PdfDocumentCanvas extends StatefulWidget {
  const _PdfDocumentCanvas({required this.attachment});

  final ChatAttachment attachment;

  @override
  State<_PdfDocumentCanvas> createState() => _PdfDocumentCanvasState();
}

class _PdfDocumentCanvasState extends State<_PdfDocumentCanvas> {
  PdfControllerPinch? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final rawPath = widget.attachment.localMediaPath?.trim();
    if (rawPath == null || rawPath.isEmpty) {
      setState(() => _error = 'This document is no longer available.');
      return;
    }
    _controller?.dispose();
    setState(() {
      _error = null;
      _controller = PdfControllerPinch(
        document: _resolveAttachmentLocalPath(widget.attachment, rawPath)
            .then(PdfDocument.openFile),
      );
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _DocumentErrorFallback(
        attachment: widget.attachment,
        message: _error!,
        onRetry: _load,
      );
    }
    final controller = _controller;
    if (controller == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    return ColoredBox(
      color: Colors.black,
      child: PdfViewPinch(
        controller: controller,
        onDocumentError: (_) {
          if (mounted) {
            setState(() {
              _error =
                  'Could not open this PDF. Check your connection and try again.';
            });
          }
        },
      ),
    );
  }
}

/// A plain-text or CSV attachment, read directly and shown as scrollable
/// text -- no renderer package needed, both are already human-readable
/// bytes.
class _TextDocumentCanvas extends StatefulWidget {
  const _TextDocumentCanvas({required this.attachment});

  final ChatAttachment attachment;

  @override
  State<_TextDocumentCanvas> createState() => _TextDocumentCanvasState();
}

class _TextDocumentCanvasState extends State<_TextDocumentCanvas> {
  String? _content;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _content = null;
    });
    final rawPath = widget.attachment.localMediaPath?.trim();
    if (rawPath == null || rawPath.isEmpty) {
      setState(() => _error = 'This document is no longer available.');
      return;
    }
    try {
      final localPath =
          await _resolveAttachmentLocalPath(widget.attachment, rawPath);
      final bytes = await File(localPath).readAsBytes();
      if (!mounted) {
        return;
      }
      setState(() => _content = utf8.decode(bytes, allowMalformed: true));
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Could not open this document. Check your connection and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _DocumentErrorFallback(
        attachment: widget.attachment,
        message: _error!,
        onRetry: _load,
      );
    }
    final content = _content;
    if (content == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 64, 20, 32),
          child: SelectableText(
            content,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// A photo that pans/zooms via pinch or double-tap, matching WhatsApp's own
/// attachment viewer -- InteractiveViewer handles both gestures natively.
class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({
    required this.imageProvider,
    required this.errorBuilder,
  });

  final ImageProvider imageProvider;
  final Widget Function() errorBuilder;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformController =
      TransformationController();
  TapDownDetails? _doubleTapDetails;
  bool _hasError = false;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    final isZoomedIn = _transformController.value != Matrix4.identity();
    if (isZoomedIn) {
      _transformController.value = Matrix4.identity();
      return;
    }
    final tapPosition = _doubleTapDetails?.localPosition ?? Offset.zero;
    _transformController.value = Matrix4.identity()
      ..translateByDouble(-tapPosition.dx * 2, -tapPosition.dy * 2, 0, 1)
      ..scaleByDouble(3.0, 3.0, 3.0, 1);
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return widget.errorBuilder();
    }

    return GestureDetector(
      onDoubleTapDown: (details) => _doubleTapDetails = details,
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        minScale: 1,
        maxScale: 5,
        transformationController: _transformController,
        child: Center(
          child: Image(
            image: widget.imageProvider,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) {
                return child;
              }
              return const CircularProgressIndicator(color: Colors.white);
            },
            errorBuilder: (_, __, ___) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _hasError = true);
              });
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }
}

class _AttachmentVideoCanvas extends StatefulWidget {
  const _AttachmentVideoCanvas({required this.localMediaPath});

  final String localMediaPath;

  @override
  State<_AttachmentVideoCanvas> createState() => _AttachmentVideoCanvasState();
}

class _AttachmentVideoCanvasState extends State<_AttachmentVideoCanvas> {
  // Nullable, unlike the eager `late final` this replaced: building the
  // controller now probes the media cache first, so it resolves a frame or
  // two later rather than synchronously in initState.
  VideoPlayerController? _controller;
  Future<void>? _initialization;
  double _volumeBeforeMute = 1;

  @override
  void initState() {
    super.initState();
    unawaited(_prepareController());
  }

  Future<void> _prepareController() async {
    final controller =
        await buildStatusMediaVideoControllerAsync(widget.localMediaPath);
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _controller = controller;
      _initialization = controller.initialize().then((_) {
        controller
          ..setLooping(true)
          ..play();
        if (mounted) setState(() {});
      });
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    controller.value.isPlaying ? controller.pause() : controller.play();
  }

  void _toggleMute() {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    if (controller.value.volume > 0) {
      _volumeBeforeMute = controller.value.volume;
      controller.setVolume(0);
    } else {
      controller.setVolume(_volumeBeforeMute > 0 ? _volumeBeforeMute : 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (controller == null ||
            snapshot.connectionState != ConnectionState.done ||
            !controller.value.isInitialized) {
          return const ColoredBox(
            color: Colors.black,
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          );
        }

        return InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: GestureDetector(
            onTap: _togglePlayback,
            child: ColoredBox(
              color: Colors.black,
              child: Stack(
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _VideoControlBar(
                      controller: controller,
                      onPlayPause: _togglePlayback,
                      onToggleMute: _toggleMute,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// WhatsApp-style controls floating over the video itself -- play/pause,
/// a seek bar with elapsed/total time, and mute/unmute. Rebuilds off
/// [controller] directly (it's a ValueListenable) so position/play-state
/// stay live without the parent needing setState on every frame.
class _VideoControlBar extends StatelessWidget {
  const _VideoControlBar({
    required this.controller,
    required this.onPlayPause,
    required this.onToggleMute,
  });

  final VideoPlayerController controller;
  final VoidCallback onPlayPause;
  final VoidCallback onToggleMute;

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final durationMs = value.duration.inMilliseconds;
        final positionMs = value.position.inMilliseconds
            .clamp(0, durationMs > 0 ? durationMs : 0)
            .toDouble();
        final isMuted = value.volume <= 0;

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0),
                Colors.black.withValues(alpha: 0.55),
              ],
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2.5,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.28),
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      key: const Key('attachment_video_seek_slider'),
                      min: 0,
                      max: durationMs > 0 ? durationMs.toDouble() : 1,
                      value: positionMs,
                      onChanged: durationMs > 0
                          ? (newValue) => controller.seekTo(
                                Duration(milliseconds: newValue.round()),
                              )
                          : null,
                    ),
                  ),
                  Row(
                    children: [
                      LiquidGlassIconButton(
                        actionKey:
                            const Key('attachment_video_play_pause_button'),
                        icon: value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        onTap: onPlayPause,
                        size: 40,
                        blurred: false,
                        color: Colors.black.withValues(alpha: 0.42),
                        iconColor: Colors.white,
                        tooltip: value.isPlaying ? 'Pause' : 'Play',
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${_formatDuration(value.position)} / '
                        '${_formatDuration(value.duration)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const Spacer(),
                      LiquidGlassIconButton(
                        actionKey: const Key('attachment_video_mute_button'),
                        icon: isMuted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        onTap: onToggleMute,
                        size: 40,
                        blurred: false,
                        color: Colors.black.withValues(alpha: 0.42),
                        iconColor: Colors.white,
                        tooltip: isMuted ? 'Unmute' : 'Mute',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AttachmentPlaceholderCanvas extends StatelessWidget {
  const _AttachmentPlaceholderCanvas({required this.attachment});

  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          colors: [
            attachment.tintColor.withValues(alpha: 0.9),
            attachment.tintColor.withValues(alpha: 0.35),
            theme.colorScheme.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -28,
            top: 24,
            child:
                _GlowOrb(color: attachment.tintColor.withValues(alpha: 0.28)),
          ),
          Positioned(
            right: -24,
            bottom: 24,
            child: _GlowOrb(
              color: AppPalette.cloud.withValues(alpha: 0.18),
              size: 118,
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 42,
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                  child: Icon(
                    _iconForType(attachment.type),
                    size: 40,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    attachment.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    attachment.details,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.88),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForType(ChatAttachmentType type) {
    if (type == ChatAttachmentType.file) {
      return documentKindVisual(attachment.documentKind, attachment.tintColor)
          .$1;
    }
    return switch (type) {
      ChatAttachmentType.photo => Icons.photo_outlined,
      ChatAttachmentType.video => Icons.videocam_outlined,
      ChatAttachmentType.location => Icons.location_on_outlined,
      ChatAttachmentType.voiceNote => Icons.graphic_eq_rounded,
      ChatAttachmentType.file => Icons.insert_drive_file_outlined,
    };
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.color,
    this.size = 88,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}
