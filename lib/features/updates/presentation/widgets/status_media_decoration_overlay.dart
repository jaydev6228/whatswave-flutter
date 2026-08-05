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
    super.key,
  });

  final StatusStorySegment segment;
  final Color accentColor;
  final EdgeInsets padding;
  final bool compact;
  final bool showBackdrop;
  final bool showTopDecorations;
  final bool showCaption;

  @override
  Widget build(BuildContext context) {
    if (segment.overlayItems.isNotEmpty) {
      return _RichStatusMediaDecorationOverlay(
        segment: segment,
        accentColor: accentColor,
        compact: compact,
        showBackdrop: showBackdrop,
        showTopDecorations: showTopDecorations,
        showCaption: showCaption,
      );
    }

    final theme = Theme.of(context);
    final caption = meaningfulStatusCaption(segment);
    final captionMaxLines = compact ? 3 : 4;
    final captionFontSize = _captionFontSizeFor(
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

  double _captionFontSizeFor(
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
}

class _RichStatusMediaDecorationOverlay extends StatelessWidget {
  const _RichStatusMediaDecorationOverlay({
    required this.segment,
    required this.accentColor,
    required this.compact,
    required this.showBackdrop,
    required this.showTopDecorations,
    required this.showCaption,
  });

  final StatusStorySegment segment;
  final Color accentColor;
  final bool compact;
  final bool showBackdrop;
  final bool showTopDecorations;
  final bool showCaption;

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
      if (showCaption) ...textItems,
    ];

    if (!showBackdrop && visibleItems.isEmpty) {
      return const SizedBox.shrink();
    }

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
        if (visibleItems.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
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
                        fit: StackFit.expand,
                        children: [
                          for (final item in visibleItems)
                            _StaticStatusOverlayPosition(
                              item: item,
                              canvasSize: frameSize,
                              compact: compact,
                              accentColor: accentColor,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
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
  });

  final StatusMediaOverlayItem item;
  final Size canvasSize;
  final bool compact;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final offset = statusStoryOverlayOffsetFor(canvasSize, item);

    return Center(
      child: Transform.translate(
        offset: offset,
        child: Transform.rotate(
          angle: item.rotation,
          child: Transform.scale(
            scale: item.scale,
            child: StatusOverlayContent(
              item: item,
              compact: compact,
              accentColor: accentColor,
            ),
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
    super.key,
  });

  final StatusMediaOverlayItem item;
  final bool compact;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return switch (item.type) {
      StatusMediaOverlayType.text => ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: compact ? 210 : 320,
          ),
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
              Icon(
                Icons.music_note_rounded,
                color: primaryColor,
                size: compact ? 15 : 17,
              ),
              SizedBox(width: compact ? 8 : 10),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: compact ? 120 : 160),
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
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
        fontSize: baseFontSize * textStyleModel.sizeScale.clamp(0.72, 1.28),
        fontWeight: FontWeight.w800,
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
        style: style,
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
