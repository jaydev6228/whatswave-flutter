import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../../../core/media/media_transfer.dart';
import '../../../updates/presentation/widgets/status_media_source.dart';
import '../../domain/chat_attachment.dart';

/// Shared by the document row's subtitle and the download affordance's
/// label, so a 416 KB photo reads the same in both places.
String formatMediaSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// The dark circular chip WhatsApp floats over a transferring thumbnail:
/// a ring around an X that cancels. Determinate once real byte counts are
/// in, indeterminate before that -- see [MediaTransfer.progress].
class MediaTransferRing extends StatelessWidget {
  const MediaTransferRing({
    super.key,
    required this.transfer,
    this.onCancel,
  });

  final MediaTransfer transfer;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: transfer,
      builder: (context, _) {
        return Center(
          child: GestureDetector(
            onTap: onCancel,
            child: SizedBox(
              width: 46,
              height: 46,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.square(
                      dimension: 40,
                      child: CircularProgressIndicator(
                        value: transfer.progress,
                        strokeWidth: 2.6,
                        color: Colors.white,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                    const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Floats a [MediaTransferRing] over media that is currently uploading.
///
/// One ring for the whole message rather than one per tile: an album is a
/// single send, and four rings counting up in step read as four separate
/// uploads that could each fail on their own.
class MediaTransferOverlay extends StatelessWidget {
  const MediaTransferOverlay({
    super.key,
    required this.transfer,
    required this.child,
    this.ringKey,
  });

  final MediaTransfer transfer;
  final Widget child;
  final Key? ringKey;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: MediaTransferRing(
            key: ringKey,
            transfer: transfer,
            onCancel: transfer.cancel,
          ),
        ),
      ],
    );
  }
}

typedef MediaGateBuilder = Widget Function(
  BuildContext context, {
  required bool suppressRemoteMedia,
  required bool transferChromeOnTop,
});

/// WhatsApp's explicit download affordance for incoming media that is only
/// a URL so far: a downward arrow plus the file size over a dimmed
/// placeholder, which turns into a cancellable progress ring on tap.
///
/// The whole thing hangs off whether the media is already in the shared
/// disk cache ([statusMediaCacheManager]) -- so media the reader has
/// already fetched, and every device-local path, renders exactly as it
/// always did with no affordance at all. Suppressing the tiles' own remote
/// load while the gate is closed is what makes the affordance mean
/// anything: the cached-network image provider would otherwise fetch the
/// bytes anyway, behind the button offering to fetch them.
class MediaDownloadGate extends StatefulWidget {
  const MediaDownloadGate({
    super.key,
    required this.messageId,
    required this.attachments,
    required this.builder,
  });

  final String messageId;
  final List<ChatAttachment> attachments;
  final MediaGateBuilder builder;

  @override
  State<MediaDownloadGate> createState() => _MediaDownloadGateState();
}

class _MediaDownloadGateState extends State<MediaDownloadGate> {
  late final List<ChatAttachment> _remote = widget.attachments
      .where(
        (attachment) =>
            attachment.localMediaPath != null &&
            isRemoteStatusMediaPath(attachment.localMediaPath!),
      )
      .toList(growable: false);

  final List<StreamSubscription<FileResponse>> _subscriptions =
      <StreamSubscription<FileResponse>>[];
  final Set<String> _completedPaths = <String>{};

  /// Starts true for media with nothing remote about it, so a bubble whose
  /// files are all device-local never waits a frame on a cache probe.
  late bool _isDownloaded = _remote.isEmpty;
  MediaTransfer? _transfer;

  @override
  void initState() {
    super.initState();
    if (_remote.isNotEmpty) {
      unawaited(_probeCache());
    }
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    super.dispose();
  }

  Future<void> _probeCache() async {
    var allCached = true;
    try {
      for (final attachment in _remote) {
        final cached =
            await statusMediaCacheManager.getFileFromCache(attachment.localMediaPath!);
        if (cached == null) {
          allCached = false;
          break;
        }
      }
    } catch (_) {
      // A device whose disk cache doesn't work (see
      // ensureStatusMediaDiskCacheReady) can neither answer this question
      // nor be filled by tapping the button, so it keeps the old
      // load-straight-from-the-network behaviour rather than showing an
      // affordance that could never resolve.
      allCached = true;
    }
    if (mounted && allCached != _isDownloaded) {
      setState(() => _isDownloaded = allCached);
    }
  }

  void _cancelSubscriptions() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }

  void _startDownload() {
    final transfer = MediaTransfer()..addListener(_onTransferChanged);
    setState(() {
      _completedPaths.clear();
      _transfer = transfer;
    });

    for (final attachment in _remote) {
      final path = attachment.localMediaPath!;
      _subscriptions.add(
        statusMediaCacheManager
            .getFileStream(path, withProgress: true)
            .listen(
          (response) {
            if (response is DownloadProgress) {
              transfer.report(
                path,
                transferred: response.downloaded,
                total: response.totalSize ?? 0,
              );
              return;
            }
            _completedPaths.add(path);
            if (_completedPaths.length == _remote.length) {
              _finishDownload(downloaded: true);
            }
          },
          // Back to the button, not stuck on a ring that will never move --
          // a failed fetch has to stay retryable.
          onError: (Object _) => _finishDownload(downloaded: false),
        ),
      );
    }
  }

  void _onTransferChanged() {
    if (_transfer?.isCancelled ?? false) {
      _finishDownload(downloaded: false);
    }
  }

  void _finishDownload({required bool downloaded}) {
    _cancelSubscriptions();
    _transfer?.removeListener(_onTransferChanged);
    if (!mounted) {
      return;
    }
    setState(() {
      _transfer = null;
      _isDownloaded = downloaded || _isDownloaded;
    });
  }

  int? get _totalSizeBytes {
    var total = 0;
    for (final attachment in _remote) {
      final size = attachment.sizeBytes;
      if (size == null) {
        return null;
      }
      total += size;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    if (_isDownloaded) {
      return widget.builder(
        context,
        suppressRemoteMedia: false,
        transferChromeOnTop: false,
      );
    }

    final transfer = _transfer;
    // Both branches below centre something over the media -- the download
    // button, or the ring that replaces it mid-fetch -- so the media must
    // drop its own centred badge either way or the two draw on top of each
    // other (a video tile's play glyph under the download arrow).
    final media = widget.builder(
      context,
      suppressRemoteMedia: true,
      transferChromeOnTop: true,
    );
    return Stack(
      fit: StackFit.passthrough,
      children: [
        media,
        Positioned.fill(
          child: transfer != null
              ? MediaTransferRing(
                  key: Key('media_download_progress_${widget.messageId}'),
                  transfer: transfer,
                  onCancel: transfer.cancel,
                )
              : _downloadButton(context),
        ),
      ],
    );
  }

  Widget _downloadButton(BuildContext context) {
    final size = _totalSizeBytes;
    return Center(
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('media_download_button_${widget.messageId}'),
          onTap: _startDownload,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.arrow_downward_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                if (size != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    formatMediaSize(size),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
