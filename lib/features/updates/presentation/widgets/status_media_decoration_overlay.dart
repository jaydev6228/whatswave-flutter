import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_twemoji/flutter_twemoji.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/models/status_story.dart';
import 'status_story_media_surface.dart';
import 'text_status_canvas.dart';

const EdgeInsets kStatusMediaOverlayCanvasPadding = EdgeInsets.fromLTRB(
  20,
  20,
  20,
  24,
);

const List<String> _emojiFontFallback = <String>[
  'Apple Color Emoji',
  'Segoe UI Emoji',
  'Noto Color Emoji',
];

String? _preferredEmojiFontFamily(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.iOS || TargetPlatform.macOS => 'Apple Color Emoji',
    TargetPlatform.android || TargetPlatform.linux => 'Noto Color Emoji',
    TargetPlatform.windows => 'Segoe UI Emoji',
    TargetPlatform.fuchsia => null,
  };
}

TextStyle _statusEmojiTextStyle(
  BuildContext context, {
  required double fontSize,
}) {
  return TextStyle(
    inherit: false,
    fontSize: fontSize,
    height: 1,
    fontFamily: _preferredEmojiFontFamily(Theme.of(context).platform),
    fontFamilyFallback: _emojiFontFallback,
  );
}

bool _usesTwemoji(TargetPlatform platform) {
  return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
}

class _StatusEmojiGlyph extends StatelessWidget {
  const _StatusEmojiGlyph({
    required this.emoji,
    required this.fontSize,
  });

  final String emoji;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final glyph = _usesTwemoji(platform)
        ? SizedBox(
            width: fontSize,
            height: fontSize,
            child: Twemoji(
              emoji: emoji,
              width: fontSize,
              height: fontSize,
            ),
          )
        : Text(
            emoji,
            style: _statusEmojiTextStyle(
              context,
              fontSize: fontSize,
            ),
          );

    return Semantics(
      label: emoji,
      child: ExcludeSemantics(
        child: glyph,
      ),
    );
  }
}

String meaningfulStatusCaption(StatusStorySegment segment) {
  final caption = segment.previewText.trim();
  final normalizedCaption = caption.toLowerCase();
  if (normalizedCaption == 'shared a new photo update' ||
      normalizedCaption == 'shared a new video update') {
    return '';
  }
  return caption;
}

/// The region a placed text overlay may occupy on a story.
///
/// Deliberately smaller than the raw canvas: the story chrome (progress
/// bar and author row up top, caption and reply bar at the bottom) is
/// drawn over the media on both the composer and the viewer, so text
/// allowed to use the full height runs underneath the close/delete/volume
/// buttons and the "Just now - 0 views" line.
///
/// Both the composer preview and the posted story size text against this
/// same box, which is what keeps the two identical -- the whole point of
/// a preview is that it shows what gets posted.
/// The bands at the top and bottom of a story that its chrome occupies --
/// progress bar, avatar row and action buttons above; caption, reply bar
/// and view count below.
///
/// Shared so anything that must stay clear of the chrome measures against
/// the same numbers: placed text, and the canvas decorations, which used to
/// slide under the avatar row because they only allowed for the device's
/// own insets.
const double kStatusChromeReservedTop = 104;
const double kStatusChromeReservedBottom = 136;
const double kStatusChromeReservedSide = 16;

Size statusOverlayTextBoundsFor(Size canvasSize) {
  return Size(
    math.max(canvasSize.width - (kStatusChromeReservedSide * 2), 120),
    math.max(
      canvasSize.height -
          kStatusChromeReservedTop -
          kStatusChromeReservedBottom,
      160,
    ),
  );
}

Offset statusStoryOverlayOffsetFor(
  Size canvasSize,
  StatusMediaOverlayItem item,
) {
  return Offset(
    (item.positionDx - 0.5) * canvasSize.width,
    (item.positionDy - 0.5) * canvasSize.height,
  );
}

class StatusMediaDecorationOverlay extends StatelessWidget {
  const StatusMediaDecorationOverlay({
    required this.segment,
    required this.accentColor,
    this.padding = kStatusMediaOverlayCanvasPadding,
    this.compact = false,
    this.showBackdrop = true,
    this.showTopDecorations = true,
    this.showCaption = true,
    this.showTextOverlays = true,
    super.key,
  });

  final StatusStorySegment segment;
  final Color accentColor;
  final EdgeInsets padding;
  final bool compact;
  final bool showBackdrop;
  final bool showTopDecorations;
  final bool showCaption;

  /// Whether placed rich text overlays (e.g. a draggable "Add text" item)
  /// render -- independent of [showCaption], which only controls the
  /// separate typed-caption card. A caller that wants the caption shown
  /// elsewhere (see the story viewer's own bottom-chrome caption text)
  /// still needs this true, or its placed text overlays would silently
  /// disappear along with the caption card.
  final bool showTextOverlays;

  @override
  Widget build(BuildContext context) {
    if (segment.overlayItems.isNotEmpty) {
      return _RichStatusMediaDecorationOverlay(
        segment: segment,
        accentColor: accentColor,
        padding: padding,
        compact: compact,
        showBackdrop: showBackdrop,
        showTopDecorations: showTopDecorations,
        showCaption: showCaption,
        showTextOverlays: showTextOverlays,
      );
    }

    final theme = Theme.of(context);
    final caption = meaningfulStatusCaption(segment);
    final captionMaxLines = compact ? 3 : 4;
    final captionFontSize = captionFontSizeFor(
      caption,
      compact: compact,
    );
    final hasTopDecorations = showTopDecorations &&
        ((segment.emoji?.trim().isNotEmpty ?? false) ||
            segment.stickers.isNotEmpty ||
            segment.musicTrack != null);
    final hasCaption = showCaption && caption.isNotEmpty;
    final hasDecorations = hasCaption || hasTopDecorations;

    if (!hasDecorations && !showBackdrop) {
      return const SizedBox.shrink();
    }

    final overlayColor = Colors.black.withValues(alpha: compact ? 0.26 : 0.34);
    final borderColor = Colors.white.withValues(alpha: compact ? 0.12 : 0.18);
    final topInset = padding.top;
    final leftInset = padding.left;
    final rightInset = padding.right;
    final bottomInset = padding.bottom;
    final musicTrack = segment.musicTrack;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (showBackdrop)
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: compact ? 0.2 : 0.28),
                    Colors.transparent,
                    Colors.black.withValues(alpha: compact ? 0.32 : 0.48),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const <double>[0, 0.46, 1],
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final frameSize = statusStoryFrameSizeFor(
                constraints.biggest,
                segment.mediaTransform.frameAspectRatio,
              );
              return Center(
                child: SizedBox(
                  width: frameSize.width,
                  height: frameSize.height,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (showTopDecorations && musicTrack != null)
                        Positioned(
                          top: topInset,
                          left: leftInset,
                          right: rightInset + (compact ? 104 : 136),
                          child: IgnorePointer(
                            child: _OverlayPill(
                              backgroundColor:
                                  (musicTrack.color ?? accentColor).withValues(
                                alpha: 0.78,
                              ),
                              borderColor: Colors.white.withValues(alpha: 0.24),
                              icon: Icons.music_note_rounded,
                              title: musicTrack.title,
                              subtitle: musicTrack.artist,
                              compact: compact,
                            ),
                          ),
                        ),
                      if (showTopDecorations && segment.stickers.isNotEmpty)
                        Positioned(
                          top: topInset +
                              (segment.musicTrack == null
                                  ? 0
                                  : (compact ? 52 : 64)),
                          left: leftInset,
                          right: rightInset + (compact ? 66 : 94),
                          child: IgnorePointer(
                            child: Wrap(
                              spacing: compact ? 8 : 10,
                              runSpacing: compact ? 8 : 10,
                              children: [
                                for (final sticker
                                    in segment.stickers.take(compact ? 2 : 4))
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: compact ? 10 : 12,
                                      vertical: compact ? 7 : 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: overlayColor,
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(color: borderColor),
                                    ),
                                    child: Text(
                                      sticker,
                                      style:
                                          theme.textTheme.labelLarge?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      if (showTopDecorations &&
                          (segment.emoji?.trim().isNotEmpty ?? false))
                        Positioned(
                          top: topInset,
                          right: rightInset,
                          child: IgnorePointer(
                            child: Container(
                              width: compact ? 56 : 74,
                              height: compact ? 56 : 74,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withValues(
                                  alpha: compact ? 0.2 : 0.26,
                                ),
                                border: Border.all(
                                  color: Colors.white.withValues(
                                    alpha: compact ? 0.12 : 0.18,
                                  ),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppPalette.deepOcean.withValues(
                                      alpha: 0.2,
                                    ),
                                    blurRadius: 18,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: _StatusEmojiGlyph(
                                  emoji: segment.emoji!,
                                  fontSize: compact ? 28 : 38,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (hasCaption)
                        Positioned(
                          left: leftInset,
                          right: rightInset,
                          bottom: bottomInset,
                          child: Align(
                            alignment: Alignment.bottomLeft,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: compact ? 236 : 420,
                              ),
                              child: _ExpandableCaptionCard(
                                key: ValueKey<String>(
                                  'status-caption-${segment.id}-${compact ? 'compact' : 'regular'}',
                                ),
                                caption: caption,
                                compact: compact,
                                overlayColor: overlayColor,
                                borderColor: borderColor,
                                accentColor: accentColor,
                                textStyleModel: segment.textStyle ??
                                    _defaultMediaCaptionStyle,
                                collapsedMaxLines: captionMaxLines,
                                collapsedFontSize: captionFontSize,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Shared by both rendering paths below -- shrinks the caption card's font
/// as the text gets longer, so a short caption still reads big and bold
/// (matching WhatsApp/Instagram) while a long one doesn't blow past the
/// card's bounds.
double captionFontSizeFor(
  String caption, {
  required bool compact,
}) {
  final normalizedCaption = caption.trim();
  if (normalizedCaption.isEmpty) {
    return compact ? 12 : 20;
  }

  final lineCount = '\n'.allMatches(normalizedCaption).length + 1;
  final textLength = normalizedCaption.length;

  if (compact) {
    if (lineCount >= 3 || textLength > 90) {
      return 11;
    }
    if (lineCount >= 2 || textLength > 48) {
      return 11.5;
    }
    return 12;
  }

  if (lineCount >= 4 || textLength > 180) {
    return 14;
  }
  if (lineCount >= 3 || textLength > 120) {
    return 15.5;
  }
  if (lineCount >= 2 || textLength > 72) {
    return 17;
  }
  return 19;
}

class _RichStatusMediaDecorationOverlay extends StatelessWidget {
  const _RichStatusMediaDecorationOverlay({
    required this.segment,
    required this.accentColor,
    required this.padding,
    required this.compact,
    required this.showBackdrop,
    required this.showTopDecorations,
    required this.showCaption,
    required this.showTextOverlays,
  });

  final StatusStorySegment segment;
  final Color accentColor;
  final EdgeInsets padding;
  final bool compact;
  final bool showBackdrop;
  final bool showTopDecorations;
  final bool showCaption;
  final bool showTextOverlays;

  @override
  Widget build(BuildContext context) {
    final textItems = segment.overlayItems
        .where((item) => item.type == StatusMediaOverlayType.text)
        .toList(growable: false);
    final decorationItems = segment.overlayItems
        .where((item) => item.type != StatusMediaOverlayType.text)
        .toList(growable: false);
    final visibleItems = <StatusMediaOverlayItem>[
      if (showTopDecorations) ...decorationItems,
      if (showTextOverlays) ...textItems,
    ];

    // WhatsApp shows the plain typed caption *and* any placed overlays
    // together -- they're independent inputs in the composer. The one
    // exception: older stored segments (and any other caller that never
    // adopted the rich overlay list) get a caption synthesized into a
    // single text overlay item instead of a real `previewText` -- in that
    // case the caption card would just be showing the same string twice.
    final caption = meaningfulStatusCaption(segment);
    final captionAlreadyRepresented = textItems.any(
      (item) => item.label.trim() == caption,
    );
    final hasCaption =
        showCaption && caption.isNotEmpty && !captionAlreadyRepresented;
    final captionMaxLines = compact ? 3 : 4;
    final captionFontSize = captionFontSizeFor(caption, compact: compact);

    if (!showBackdrop && visibleItems.isEmpty && !hasCaption) {
      return const SizedBox.shrink();
    }

    final overlayColor = Colors.black.withValues(alpha: compact ? 0.26 : 0.34);
    final borderColor = Colors.white.withValues(alpha: compact ? 0.12 : 0.18);

    return Stack(
      fit: StackFit.expand,
      children: [
        if (showBackdrop)
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: compact ? 0.2 : 0.28),
                    Colors.transparent,
                    Colors.black.withValues(alpha: compact ? 0.32 : 0.48),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const <double>[0, 0.46, 1],
                ),
              ),
            ),
          ),
        if (visibleItems.isNotEmpty || hasCaption)
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableSize = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                final frameSize = statusStoryFrameSizeFor(
                  availableSize,
                  segment.mediaTransform.frameAspectRatio,
                );
                return Center(
                  child: SizedBox(
                    width: frameSize.width,
                    height: frameSize.height,
                    child: Stack(
                      // Text overlays are allowed to run past the media
                      // frame onto the letterbox bars: shrinking a long one
                      // to fit inside the frame made it unreadable, and the
                      // bars are dead space the story can happily use.
                      clipBehavior: Clip.none,
                      fit: StackFit.expand,
                      children: [
                        if (visibleItems.isNotEmpty)
                          // Only the non-text decorations ignore pointers.
                          // A long text overlay has to stay scrollable, and
                          // an IgnorePointer around it would make that
                          // scroll silently dead (see how the same mistake
                          // clipped overlay text before).
                          Stack(
                            clipBehavior: Clip.none,
                            fit: StackFit.expand,
                            children: [
                              for (final item in visibleItems)
                                if (item.type == StatusMediaOverlayType.text &&
                                    !compact)
                                  _StaticStatusOverlayPosition(
                                    item: item,
                                    canvasSize: frameSize,
                                    // Long text sizes itself against the
                                    // whole screen, not the media frame.
                                    boundsSize: availableSize,
                                    compact: compact,
                                    accentColor: accentColor,
                                  )
                                else
                                  IgnorePointer(
                                    child: _StaticStatusOverlayPosition(
                                      item: item,
                                      canvasSize: frameSize,
                                      boundsSize: availableSize,
                                      compact: compact,
                                      accentColor: accentColor,
                                    ),
                                  ),
                            ],
                          ),
                        if (hasCaption)
                          Positioned(
                            left: padding.left,
                            right: padding.right,
                            bottom: padding.bottom,
                            child: Align(
                              alignment: Alignment.bottomLeft,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: compact ? 236 : 420,
                                ),
                                child: _ExpandableCaptionCard(
                                  key: ValueKey<String>(
                                    'status-caption-${segment.id}-${compact ? 'compact' : 'regular'}',
                                  ),
                                  caption: caption,
                                  compact: compact,
                                  overlayColor: overlayColor,
                                  borderColor: borderColor,
                                  accentColor: accentColor,
                                  // Always the plain default look here, never
                                  // segment.textStyle -- once there are rich
                                  // overlay items, that field describes the
                                  // *primary text overlay's* own font/color
                                  // (e.g. a bold custom look for a placed
                                  // "Gg" overlay), not this genuinely
                                  // separate typed caption. Applying it here
                                  // made the caption pick up the overlay's
                                  // styling instead of showing as plain text,
                                  // like WhatsApp's own caption.
                                  textStyleModel: _defaultMediaCaptionStyle,
                                  collapsedMaxLines: captionMaxLines,
                                  collapsedFontSize: captionFontSize,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _StaticStatusOverlayPosition extends StatelessWidget {
  const _StaticStatusOverlayPosition({
    required this.item,
    required this.canvasSize,
    required this.compact,
    required this.accentColor,
    this.boundsSize,
  });

  final StatusMediaOverlayItem item;

  /// The media frame the item's normalised position is anchored to.
  final Size canvasSize;

  /// How much room the item may actually occupy -- the whole screen, not
  /// just the media frame, so long text stays readable instead of being
  /// shrunk to fit between the letterbox bars. Falls back to [canvasSize].
  final Size? boundsSize;

  final bool compact;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final offset = statusStoryOverlayOffsetFor(canvasSize, item);
    final bounds = boundsSize;
    Widget content = StatusOverlayContent(
      item: item,
      compact: compact,
      accentColor: accentColor,
      canvasSize: bounds ?? canvasSize,
    );

    // The media frame's own SizedBox still *constrains* children to the
    // frame even with the Stack's clip off, so a text overlay allowed to
    // use the whole screen has to be handed looser constraints as well --
    // otherwise it silently lays out at the frame's height again.
    if (bounds != null && item.type == StatusMediaOverlayType.text) {
      content = OverflowBox(
        alignment: Alignment.center,
        maxWidth: bounds.width,
        maxHeight: bounds.height,
        child: content,
      );
    }

    return Center(
      child: Transform.translate(
        offset: offset,
        child: Transform.rotate(
          angle: item.rotation,
          child: Transform.scale(
            scale: item.scale,
            child: content,
          ),
        ),
      ),
    );
  }
}

class StatusOverlayContent extends StatelessWidget {
  const StatusOverlayContent({
    required this.item,
    required this.compact,
    required this.accentColor,
    this.canvasSize,
    super.key,
  });

  final StatusMediaOverlayItem item;
  final bool compact;
  final Color accentColor;

  /// The frame the overlay is placed on, when the caller knows it. Text
  /// overlays size themselves against this so they always fit the frame
  /// they will actually be seen in; without it they fall back to the
  /// screen, which is right for full-bleed callers and merely generous
  /// for smaller ones.
  final Size? canvasSize;

  @override
  Widget build(BuildContext context) {
    return switch (item.type) {
      StatusMediaOverlayType.text => _overlayTextConstraints(
          context,
          child: _StatusOverlayTextCard(
            item: item,
            compact: compact,
          ),
        ),
      StatusMediaOverlayType.emoji => _StatusEmojiGlyph(
          emoji: item.label,
          fontSize: compact ? 30 : 44,
        ),
      StatusMediaOverlayType.sticker => _StatusStickerDecoration(
          item: item,
          compact: compact,
        ),
      StatusMediaOverlayType.music => _StatusMusicBanner(
          item: item,
          compact: compact,
          accentColor: accentColor,
        ),
    };
  }

  /// Keeps a placed text overlay readable, however long its text is.
  ///
  /// Width is a share of the available bounds rather than a fixed pixel
  /// count, so the text wraps instead of running past the screen edge.
  /// Height is bounded by those same bounds and *scrolls* past that --
  /// deliberately not shrink-to-fit, which turned a long overlay into
  /// unreadably small type. Compact (thumbnail) renderings keep their
  /// small fixed budget and shrink instead, since nothing can scroll a
  /// list thumbnail.
  Widget _overlayTextConstraints(
    BuildContext context, {
    required Widget child,
  }) {
    final bounds = canvasSize ?? MediaQuery.sizeOf(context);
    if (compact) {
      final maxWidth = math.min(210.0, bounds.width * 0.9);
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: math.min(140.0, bounds.height * 0.9),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          ),
        ),
      );
    }

    final textBounds = statusOverlayTextBoundsFor(bounds);
    final maxWidth = textBounds.width;
    final maxHeight = textBounds.height;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
      child: _ScrollableOverlayText(maxWidth: maxWidth, child: child),
    );
  }
}

/// Reports where a text overlay's "more below" hint currently sits, in
/// global coordinates, or null when there is no hint.
///
/// The story viewer's previous/next tap zones sit above the story card and
/// are translucent, so they receive every tap the hint receives and would
/// navigate the story out from under it. The viewer listens for this and
/// leaves that patch of screen alone.
class StatusOverlayScrollHintNotification extends Notification {
  const StatusOverlayScrollHintNotification(this.rect);

  final Rect? rect;
}

/// A placed text overlay that outgrew the screen, with a hint that there
/// is more below it.
///
/// Long overlay text scrolls, but on a posted story nothing said so -- the
/// text simply ran to the bottom edge and looked finished. A chevron marks
/// the overflow the way a scrollable dialog does, and goes away for good
/// once the end has been reached, since by then the reader knows the text
/// scrolls.
///
/// Tapping it pages down. That needs the story viewer to leave this patch
/// of screen alone -- its previous/next zones sit above the card and are
/// translucent, so without that they receive the same tap and navigate the
/// story out from under the reader. The rect is published upwards as a
/// [StatusOverlayScrollHintNotification] for exactly that.
class _ScrollableOverlayText extends StatefulWidget {
  const _ScrollableOverlayText({required this.maxWidth, required this.child});

  final double maxWidth;
  final Widget child;

  @override
  State<_ScrollableOverlayText> createState() => _ScrollableOverlayTextState();
}

class _ScrollableOverlayTextState extends State<_ScrollableOverlayText> {
  final ScrollController _controller = ScrollController();

  /// Whether there is more text below the fold right now.
  bool _hasMoreBelow = false;

  /// Set once the reader reaches the end. The hint never comes back after
  /// that -- it exists to tell you the text scrolls, and you now know.
  bool _reachedEnd = false;

  final GlobalKey _hintKey = GlobalKey();
  Rect? _publishedHintRect;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncOverflow);
    // The first frame is when extents are known.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverflow());
  }

  @override
  void dispose() {
    _controller.removeListener(_syncOverflow);
    _controller.dispose();
    super.dispose();
  }

  void _syncOverflow() {
    if (!mounted || !_controller.hasClients) {
      return;
    }
    final position = _controller.position;
    // A point of slack: a scroll that stops a hair short of the end should
    // still count as the end.
    final atEnd = position.pixels >= position.maxScrollExtent - 1;
    final hasMore = position.maxScrollExtent > 1 && !atEnd && !_reachedEnd;
    if (atEnd && !_reachedEnd) {
      setState(() {
        _reachedEnd = true;
        _hasMoreBelow = false;
      });
      return;
    }
    if (hasMore != _hasMoreBelow) {
      setState(() => _hasMoreBelow = hasMore);
    }
  }

  /// Tells the viewer where the hint is, so its tap zones can skip it.
  void _publishHintRect() {
    if (!mounted) {
      return;
    }
    Rect? rect;
    if (_hasMoreBelow) {
      final box = _hintKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        rect = box.localToGlobal(Offset.zero) & box.size;
      }
    }
    if (rect == _publishedHintRect) {
      return;
    }
    _publishedHintRect = rect;
    StatusOverlayScrollHintNotification(rect).dispatch(context);
  }

  void _pageDown() {
    if (!_controller.hasClients) {
      return;
    }
    final position = _controller.position;
    _controller.animateTo(
      math.min(
        position.pixels + position.viewportDimension * 0.8,
        position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _publishHintRect());
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        SingleChildScrollView(
          controller: _controller,
          // Only scrolls once the text genuinely outgrows the screen;
          // shorter overlays still size to their own content.
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.maxWidth),
            child: widget.child,
          ),
        ),
        Positioned(
          bottom: 6,
          child: IgnorePointer(
            ignoring: !_hasMoreBelow,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              opacity: _hasMoreBelow ? 1 : 0,
              child: Semantics(
                button: true,
                label: 'Scroll down for more text',
                child: GestureDetector(
                  key: const Key('updates_overlay_text_more_below'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _pageDown,
                  child: Container(
                    key: _hintKey,
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      // Heavier than the rest of the story chrome and with
                      // a shadow of its own: this sits directly on top of
                      // large white text, which nothing else has to do.
                      color: Colors.black.withValues(alpha: 0.72),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.55),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusStickerDecoration extends StatelessWidget {
  const _StatusStickerDecoration({
    required this.item,
    required this.compact,
  });

  final StatusMediaOverlayItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = item.accentColor ?? AppPalette.emerald;
    final secondaryColor =
        item.secondaryColor ?? primaryColor.withValues(alpha: 0.2);
    final icon = _iconForVariant(item.variantId);

    return switch (item.variantId) {
      'live_badge' => Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 8 : 9,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: compact ? 0.56 : 0.64),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.62),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 8 : 10,
                height: compact ? 8 : 10,
                decoration: BoxDecoration(
                  color: primaryColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: primaryColor.withValues(alpha: 0.42),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              SizedBox(width: compact ? 8 : 10),
              Text(
                item.label.toUpperCase(),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      'map_pin' => Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 8 : 9,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(compact ? 18 : 22),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: compact ? 15 : 17, color: primaryColor),
              SizedBox(width: compact ? 8 : 10),
              Text(
                item.label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.black,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      'weekend_ticket' => Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 14,
            vertical: compact ? 9 : 10,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[primaryColor, secondaryColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(compact ? 18 : 22),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: compact ? 16 : 18,
                color: Colors.black.withValues(alpha: 0.78),
              ),
              SizedBox(width: compact ? 8 : 10),
              Text(
                item.label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.black.withValues(alpha: 0.82),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.35,
                ),
              ),
            ],
          ),
        ),
      _ => Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 8 : 9,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[
                primaryColor.withValues(alpha: 0.94),
                secondaryColor.withValues(alpha: 0.94),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(compact ? 18 : 22),
            boxShadow: [
              BoxShadow(
                color: primaryColor.withValues(alpha: 0.18),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 28 : 32,
                height: compact ? 28 : 32,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(compact ? 10 : 12),
                ),
                child: Icon(
                  icon,
                  size: compact ? 15 : 18,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: compact ? 8 : 10),
              Text(
                item.label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
    };
  }

  IconData _iconForVariant(String? variantId) {
    return switch (variantId) {
      'launch_card' => Icons.auto_awesome_rounded,
      'weekend_ticket' => Icons.celebration_outlined,
      'map_pin' => Icons.location_on_rounded,
      'night_stamp' => Icons.nights_stay_rounded,
      'coffee_note' => Icons.coffee_rounded,
      'camera_tag' => Icons.camera_alt_rounded,
      'spotlight_chip' => Icons.bolt_rounded,
      _ => Icons.graphic_eq_rounded,
    };
  }
}

class _StatusMusicBanner extends StatelessWidget {
  const _StatusMusicBanner({
    required this.item,
    required this.compact,
    required this.accentColor,
  });

  final StatusMediaOverlayItem item;
  final bool compact;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = item.accentColor ?? accentColor;
    final secondaryColor =
        item.secondaryColor ?? primaryColor.withValues(alpha: 0.24);

    return switch (item.variantId) {
      'pulse' => Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 8 : 9,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: compact ? 0.58 : 0.66),
            borderRadius: BorderRadius.circular(compact ? 18 : 22),
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.58),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 28 : 34,
                height: compact ? 28 : 34,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.graphic_eq_rounded,
                  color: Colors.white,
                  size: compact ? 16 : 19,
                ),
              ),
              SizedBox(width: compact ? 8 : 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                  if (item.subtitle?.isNotEmpty == true)
                    Text(
                      item.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: primaryColor.withValues(alpha: 0.96),
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      'mix' => Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 9 : 10,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[primaryColor, secondaryColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(compact ? 18 : 22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'NOW PLAYING',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                ),
              ),
              SizedBox(height: compact ? 4 : 6),
              Text(
                item.label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (item.subtitle?.isNotEmpty == true)
                Text(
                  item.subtitle!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.84),
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
      'minimal' => Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 7 : 8,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: compact ? 0.5 : 0.56),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.16),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 24 : 28,
                height: compact ? 24 : 28,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.music_note_rounded,
                  color: primaryColor,
                  size: compact ? 13 : 15,
                ),
              ),
              SizedBox(width: compact ? 8 : 10),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: compact ? 120 : 160),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    if (item.subtitle?.isNotEmpty == true)
                      Text(
                        item.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.64),
                          fontWeight: FontWeight.w600,
                          height: 1.1,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      _ => Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 8 : 9,
          ),
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(compact ? 18 : 22),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.24),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 30 : 36,
                height: compact ? 30 : 36,
                decoration: BoxDecoration(
                  color: secondaryColor.withValues(alpha: 0.34),
                  borderRadius: BorderRadius.circular(compact ? 10 : 12),
                ),
                child: const Icon(
                  Icons.music_note_rounded,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: compact ? 8 : 10),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: compact ? 138 : 188),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    if (item.subtitle?.isNotEmpty == true)
                      Text(
                        item.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
    };
  }
}

class _StatusOverlayTextCard extends StatelessWidget {
  const _StatusOverlayTextCard({
    required this.item,
    required this.compact,
  });

  final StatusMediaOverlayItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyleModel = item.textStyle ?? _defaultMediaCaptionStyle;
    final look = resolveTextStatusFontLook(textStyleModel.fontId);
    final baseFontSize = compact ? 18.0 : 24.0;
    final style = look.apply(
      (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
        color: textStyleModel.textColor ?? Colors.white,
        fontSize: (baseFontSize *
                textStyleModel.sizeScale
                    .clamp(kStatusTextMinSizeScale, kStatusTextMaxSizeScale))
            .clamp(kStatusTextMinFontSize, double.infinity),
        fontWeight: textStyleModel.fontWeight,
        height: compact ? 1.12 : 1.18,
        shadows: <Shadow>[
          Shadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
    final weightedStyle = style.copyWith(
      // Wins over the font look's own weight, same as the canvas.
      fontWeight: textStyleModel.fontWeight,
    );

    final hasSolidBackground = textStyleModel.useSolidBackground ||
        textStyleModel.backgroundColor != null;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 7 : 9,
      ),
      decoration: hasSolidBackground
          ? BoxDecoration(
              color: (textStyleModel.backgroundColor ?? Colors.black)
                  .withValues(alpha: 0.58),
              borderRadius: BorderRadius.circular(compact ? 14 : 16),
            )
          : null,
      child: Text(
        item.label,
        textAlign: switch (textStyleModel.alignment) {
          StatusTextAlignment.left => TextAlign.left,
          StatusTextAlignment.center => TextAlign.center,
          StatusTextAlignment.right => TextAlign.right,
        },
        style: weightedStyle,
      ),
    );
  }
}

const StatusTextStyle _defaultMediaCaptionStyle = StatusTextStyle(
  fontId: 'clean',
  backgroundId: 'midnight_drive',
  layout: StatusTextLayout.note,
  alignment: StatusTextAlignment.left,
  textColorValue: 0xFFFFFFFF,
  sizeScale: 0.92,
);

class _ExpandableCaptionCard extends StatefulWidget {
  const _ExpandableCaptionCard({
    required this.caption,
    required this.compact,
    required this.overlayColor,
    required this.borderColor,
    required this.accentColor,
    required this.textStyleModel,
    required this.collapsedMaxLines,
    required this.collapsedFontSize,
    super.key,
  });

  final String caption;
  final bool compact;
  final Color overlayColor;
  final Color borderColor;
  final Color accentColor;
  final StatusTextStyle textStyleModel;
  final int collapsedMaxLines;
  final double collapsedFontSize;

  @override
  State<_ExpandableCaptionCard> createState() => _ExpandableCaptionCardState();
}

class _ExpandableCaptionCardState extends State<_ExpandableCaptionCard>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;

  @override
  void didUpdateWidget(covariant _ExpandableCaptionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.caption != widget.caption && _isExpanded) {
      setState(() {
        _isExpanded = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final textStyle = _buildCaptionTextStyle(
          context,
          model: widget.textStyleModel,
          compact: widget.compact,
          textLength: widget.caption.length,
          collapsedFontSize: widget.collapsedFontSize,
        );
        final isOverflowing = _isTextOverflowing(
          widget.caption,
          textStyle: textStyle,
          maxWidth: constraints.maxWidth - (widget.compact ? 24 : 32),
          maxLines: widget.collapsedMaxLines,
          textDirection: Directionality.of(context),
          textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
        );

        return AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: Container(
            key: const Key('updates_media_caption_card'),
            constraints: BoxConstraints(
              maxHeight: _isExpanded
                  ? (widget.compact ? 220 : 360)
                  : (widget.compact ? 92 : 140),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 12 : 16,
              vertical: widget.compact ? 10 : 14,
            ),
            decoration: BoxDecoration(
              color: widget.overlayColor,
              borderRadius: BorderRadius.circular(widget.compact ? 18 : 24),
              border: Border.all(color: widget.borderColor),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  key: const Key('updates_media_caption_text'),
                  widget.caption,
                  maxLines: _isExpanded ? null : widget.collapsedMaxLines,
                  overflow: _isExpanded
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                  style: textStyle,
                ),
                if (isOverflowing || _isExpanded) ...[
                  SizedBox(height: widget.compact ? 8 : 10),
                  InkWell(
                    key: const Key('updates_media_caption_expand_button'),
                    onTap: () {
                      setState(() {
                        _isExpanded = !_isExpanded;
                      });
                    },
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 2,
                      ),
                      child: Text(
                        _isExpanded ? 'Show less' : 'Show more',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.15,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isTextOverflowing(
    String text, {
    required TextStyle textStyle,
    required double maxWidth,
    required int maxLines,
    required TextDirection textDirection,
    required double textScaleFactor,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: textDirection,
      textScaler: TextScaler.linear(textScaleFactor),
      maxLines: maxLines,
    )..layout(maxWidth: maxWidth);
    return painter.didExceedMaxLines;
  }

  TextStyle _buildCaptionTextStyle(
    BuildContext context, {
    required StatusTextStyle model,
    required bool compact,
    required int textLength,
    required double collapsedFontSize,
  }) {
    final theme = Theme.of(context);
    final look = resolveTextStatusFontLook(model.fontId);
    final adjustedFontSize =
        collapsedFontSize * model.sizeScale.clamp(0.72, 1.18);
    final baseStyle =
        (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
      color: model.textColor ?? Colors.white,
      fontSize: adjustedFontSize,
      fontWeight: FontWeight.w700,
      height: compact ? 1.18 : 1.24,
      shadows: <Shadow>[
        Shadow(
          color: Colors.black.withValues(alpha: 0.16),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    );

    var styled = look.apply(baseStyle);
    if (textLength > 180) {
      styled = styled.copyWith(
        fontSize: (styled.fontSize ?? adjustedFontSize) * 0.92,
      );
    }
    if (textLength > 260) {
      styled = styled.copyWith(
        fontSize: (styled.fontSize ?? adjustedFontSize) * 0.88,
      );
    }
    if (textLength > 340) {
      styled = styled.copyWith(
        fontSize: (styled.fontSize ?? adjustedFontSize) * 0.84,
        height: compact ? 1.14 : 1.18,
      );
    }
    return styled;
  }
}

class _OverlayPill extends StatelessWidget {
  const _OverlayPill({
    required this.backgroundColor,
    required this.borderColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.compact,
  });

  final Color backgroundColor;
  final Color borderColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 8 : 9,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(compact ? 18 : 22),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: Colors.white,
            size: compact ? 16 : 18,
          ),
          SizedBox(width: compact ? 8 : 10),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
