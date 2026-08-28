import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/models/status_story.dart';
import '../status_motion.dart';

class TextStatusFontLook {
  const TextStatusFontLook({
    required this.id,
    required this.label,
    required this.sample,
    required this.apply,
    this.uppercase = false,
  });

  final String id;
  final String label;
  final String sample;
  final TextStyle Function(TextStyle baseStyle) apply;
  final bool uppercase;
}

class TextStatusBackgroundPreset {
  const TextStatusBackgroundPreset({
    required this.id,
    required this.label,
    required this.colors,
    required this.accentColor,
    required this.suggestedTextColor,
    this.isSolid = false,
    this.begin = Alignment.topLeft,
    this.end = Alignment.bottomRight,
  });

  final String id;
  final String label;
  final List<Color> colors;
  final Color accentColor;
  final Color suggestedTextColor;
  final bool isSolid;
  final Alignment begin;
  final Alignment end;
}

class TextStatusTonePreset {
  const TextStatusTonePreset({
    required this.id,
    required this.label,
    required this.colorValue,
  });

  final String id;
  final String label;
  final int? colorValue;

  Color? get color => colorValue == null ? null : Color(colorValue!);
}

final List<TextStatusFontLook> kTextStatusFontLooks = <TextStatusFontLook>[
  TextStatusFontLook(
    id: 'clean',
    label: 'Clean',
    sample: 'Aa',
    apply: (baseStyle) => baseStyle.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -0.8,
      height: 1.02,
    ),
  ),
  TextStatusFontLook(
    id: 'poster',
    label: 'Poster',
    sample: 'UP',
    uppercase: true,
    apply: (baseStyle) => baseStyle.copyWith(
      fontWeight: FontWeight.w900,
      letterSpacing: 1.8,
      height: 0.98,
    ),
  ),
  TextStatusFontLook(
    id: 'serif',
    label: 'Serif',
    sample: 'Sr',
    apply: (baseStyle) => baseStyle.copyWith(
      fontFamily: 'serif',
      fontWeight: FontWeight.w700,
      height: 1.06,
    ),
  ),
  TextStatusFontLook(
    id: 'mono',
    label: 'Mono',
    sample: '01',
    apply: (baseStyle) => baseStyle.copyWith(
      fontFamily: 'monospace',
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      height: 1.1,
    ),
  ),
  TextStatusFontLook(
    id: 'italic',
    label: 'Italic',
    sample: 'It',
    apply: (baseStyle) => baseStyle.copyWith(
      fontFamily: 'serif',
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w600,
      height: 1.08,
    ),
  ),
  TextStatusFontLook(
    id: 'impact',
    label: 'Impact',
    sample: 'Hi',
    uppercase: true,
    apply: (baseStyle) => baseStyle.copyWith(
      fontWeight: FontWeight.w900,
      letterSpacing: 2.8,
      height: 0.94,
    ),
  ),
  TextStatusFontLook(
    id: 'soft',
    label: 'Soft',
    sample: 'So',
    apply: (baseStyle) => baseStyle.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0.15,
      height: 1.12,
    ),
  ),
  TextStatusFontLook(
    id: 'editorial',
    label: 'Editorial',
    sample: 'Ed',
    apply: (baseStyle) => baseStyle.copyWith(
      fontFamily: 'serif',
      fontWeight: FontWeight.w800,
      letterSpacing: -1.1,
      height: 1.0,
    ),
  ),
  TextStatusFontLook(
    id: 'wide',
    label: 'Wide',
    sample: 'Wd',
    uppercase: true,
    apply: (baseStyle) => baseStyle.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: 3.2,
      height: 1.0,
    ),
  ),
  TextStatusFontLook(
    id: 'note',
    label: 'Note',
    sample: 'Nt',
    apply: (baseStyle) => baseStyle.copyWith(
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w700,
      height: 1.14,
      letterSpacing: 0.35,
    ),
  ),
  TextStatusFontLook(
    id: 'banner',
    label: 'Banner',
    sample: 'Bn',
    apply: (baseStyle) => baseStyle.copyWith(
      fontWeight: FontWeight.w900,
      letterSpacing: -0.4,
      height: 1.0,
    ),
  ),
  TextStatusFontLook(
    id: 'capsule',
    label: 'Capsule',
    sample: 'Cp',
    uppercase: true,
    apply: (baseStyle) => baseStyle.copyWith(
      fontFamily: 'monospace',
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
      height: 1.04,
    ),
  ),
  TextStatusFontLook(
    id: 'cinema',
    label: 'Cinema',
    sample: 'Cm',
    uppercase: true,
    apply: (baseStyle) => baseStyle.copyWith(
      fontWeight: FontWeight.w900,
      letterSpacing: -1.2,
      height: 0.92,
    ),
  ),
  TextStatusFontLook(
    id: 'journal',
    label: 'Journal',
    sample: 'Jn',
    apply: (baseStyle) => baseStyle.copyWith(
      fontFamily: 'serif',
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w500,
      height: 1.18,
      letterSpacing: 0.2,
    ),
  ),
  TextStatusFontLook(
    id: 'signal',
    label: 'Signal',
    sample: 'SG',
    uppercase: true,
    apply: (baseStyle) => baseStyle.copyWith(
      fontFamily: 'monospace',
      fontWeight: FontWeight.w800,
      letterSpacing: 2.2,
      height: 1.0,
    ),
  ),
  TextStatusFontLook(
    id: 'luxe',
    label: 'Luxe',
    sample: 'Lx',
    apply: (baseStyle) => baseStyle.copyWith(
      fontFamily: 'serif',
      fontWeight: FontWeight.w600,
      letterSpacing: 0.9,
      height: 1.08,
    ),
  ),
];

const List<TextStatusBackgroundPreset> kTextStatusBackgroundPresets =
    <TextStatusBackgroundPreset>[
  TextStatusBackgroundPreset(
    id: 'emerald_pop',
    label: 'Emerald',
    colors: <Color>[
      Color(0xFF0F5C55),
      Color(0xFF118C7E),
      Color(0xFF24D56E),
    ],
    accentColor: Color(0xFFD8FFE7),
    suggestedTextColor: Colors.white,
  ),
  TextStatusBackgroundPreset(
    id: 'sunset_glow',
    label: 'Sunset',
    colors: <Color>[
      Color(0xFFFF7B54),
      Color(0xFFFFB26B),
      Color(0xFFFFE7C4),
    ],
    accentColor: Color(0xFF702400),
    suggestedTextColor: Color(0xFF3D1604),
  ),
  TextStatusBackgroundPreset(
    id: 'midnight_drive',
    label: 'Midnight',
    colors: <Color>[
      Color(0xFF090B22),
      Color(0xFF272B66),
      Color(0xFF784BFF),
    ],
    accentColor: Color(0xFFD9CCFF),
    suggestedTextColor: Colors.white,
  ),
  TextStatusBackgroundPreset(
    id: 'rose_gold',
    label: 'Rose',
    colors: <Color>[
      Color(0xFF6E2548),
      Color(0xFFCE5A86),
      Color(0xFFF7D0D8),
    ],
    accentColor: Color(0xFFFFF0D9),
    suggestedTextColor: Colors.white,
  ),
  TextStatusBackgroundPreset(
    id: 'ocean_splash',
    label: 'Ocean',
    colors: <Color>[
      Color(0xFF003B73),
      Color(0xFF0074B7),
      Color(0xFF60D2FF),
    ],
    accentColor: Color(0xFFE5FBFF),
    suggestedTextColor: Colors.white,
  ),
  TextStatusBackgroundPreset(
    id: 'mango_fizz',
    label: 'Mango',
    colors: <Color>[
      Color(0xFFFF8C42),
      Color(0xFFFFC75F),
      Color(0xFFFFF1B5),
    ],
    accentColor: Color(0xFF712A00),
    suggestedTextColor: Color(0xFF4F2300),
  ),
  TextStatusBackgroundPreset(
    id: 'neon_stage',
    label: 'Neon',
    colors: <Color>[
      Color(0xFF10141F),
      Color(0xFF432A94),
      Color(0xFF16D9E3),
    ],
    accentColor: Color(0xFFEEFCFF),
    suggestedTextColor: Colors.white,
  ),
  TextStatusBackgroundPreset(
    id: 'peach_cloud',
    label: 'Peach',
    colors: <Color>[
      Color(0xFFFFECE5),
      Color(0xFFFFC9B9),
      Color(0xFFFF8A80),
    ],
    accentColor: Color(0xFFA23A35),
    suggestedTextColor: Color(0xFF55211F),
  ),
  TextStatusBackgroundPreset(
    id: 'forest_night',
    label: 'Forest',
    colors: <Color>[
      Color(0xFF132A13),
      Color(0xFF31572C),
      Color(0xFF4F772D),
    ],
    accentColor: Color(0xFFEFFFD6),
    suggestedTextColor: Colors.white,
  ),
  TextStatusBackgroundPreset(
    id: 'lavender_dream',
    label: 'Lavender',
    colors: <Color>[
      Color(0xFF564592),
      Color(0xFF9A8CFF),
      Color(0xFFF0E8FF),
    ],
    accentColor: Color(0xFFFFF7C2),
    suggestedTextColor: Colors.white,
  ),
];

const List<TextStatusTonePreset> kTextStatusTonePresets =
    <TextStatusTonePreset>[
  TextStatusTonePreset(
    id: 'auto',
    label: 'Auto',
    colorValue: null,
  ),
  TextStatusTonePreset(
    id: 'light',
    label: 'Light',
    colorValue: 0xFFFFFFFF,
  ),
  TextStatusTonePreset(
    id: 'ink',
    label: 'Ink',
    colorValue: 0xFF111B21,
  ),
  TextStatusTonePreset(
    id: 'amber',
    label: 'Amber',
    colorValue: 0xFFFFF1B5,
  ),
  TextStatusTonePreset(
    id: 'sky',
    label: 'Sky',
    colorValue: 0xFFE5FBFF,
  ),
  TextStatusTonePreset(
    id: 'blush',
    label: 'Blush',
    colorValue: 0xFFFFF2F6,
  ),
  TextStatusTonePreset(
    id: 'mint',
    label: 'Mint',
    colorValue: 0xFFDDFBE5,
  ),
  TextStatusTonePreset(
    id: 'lime',
    label: 'Lime',
    colorValue: 0xFFF4FFAE,
  ),
  TextStatusTonePreset(
    id: 'coral',
    label: 'Coral',
    colorValue: 0xFFFFD6CF,
  ),
  TextStatusTonePreset(
    id: 'lavender',
    label: 'Lavender',
    colorValue: 0xFFF2E7FF,
  ),
  TextStatusTonePreset(
    id: 'plum',
    label: 'Plum',
    colorValue: 0xFF4F235F,
  ),
  TextStatusTonePreset(
    id: 'navy',
    label: 'Navy',
    colorValue: 0xFF10233F,
  ),
];

TextStatusFontLook resolveTextStatusFontLook(String id) {
  for (final look in kTextStatusFontLooks) {
    if (look.id == id) {
      return look;
    }
  }
  return kTextStatusFontLooks.first;
}

TextStatusBackgroundPreset resolveTextStatusBackgroundPreset(
  String id,
  Color accentColor,
) {
  for (final preset in kTextStatusBackgroundPresets) {
    if (preset.id == id) {
      return preset;
    }
  }

  final hsl = HSLColor.fromColor(accentColor);
  final deepColor =
      hsl.withLightness((hsl.lightness * 0.38).clamp(0.12, 0.42)).toColor();
  final brightColor =
      hsl.withLightness((hsl.lightness * 1.22).clamp(0.54, 0.8)).toColor();
  final isDark = deepColor.computeLuminance() < 0.4;
  return TextStatusBackgroundPreset(
    id: 'generated-accent',
    label: 'Accent',
    colors: <Color>[deepColor, accentColor, brightColor],
    accentColor: isDark ? Colors.white : AppPalette.ink,
    suggestedTextColor: isDark ? Colors.white : AppPalette.ink,
  );
}

TextStatusBackgroundPreset buildCustomTextStatusBackgroundPreset(
    Color baseColor,
    {bool useSolidColor = false}) {
  final hsl = HSLColor.fromColor(baseColor);
  if (useSolidColor) {
    final accentColor = hsl
        .withSaturation((hsl.saturation * 0.56).clamp(0.12, 0.72))
        .withLightness((hsl.lightness + 0.26).clamp(0.5, 0.92))
        .toColor();
    final isDark =
        ThemeData.estimateBrightnessForColor(baseColor) == Brightness.dark;
    return TextStatusBackgroundPreset(
      id: 'custom-solid-${baseColor.toARGB32().toRadixString(16)}',
      label: 'Custom solid',
      colors: <Color>[baseColor],
      accentColor: accentColor,
      suggestedTextColor: isDark ? Colors.white : AppPalette.ink,
      isSolid: true,
    );
  }

  final saturation = (hsl.saturation + 0.12).clamp(0.18, 0.98);
  final middleColor = hsl.withSaturation(saturation).toColor();
  final deepColor = hsl
      .withSaturation((saturation + 0.04).clamp(0.22, 1.0))
      .withLightness((hsl.lightness * 0.46).clamp(0.08, 0.38))
      .toColor();
  final brightColor = hsl
      .withSaturation((saturation * 0.92).clamp(0.16, 0.88))
      .withLightness((hsl.lightness + 0.22).clamp(0.44, 0.86))
      .toColor();
  final accentColor = hsl
      .withSaturation((saturation * 0.56).clamp(0.14, 0.72))
      .withLightness((hsl.lightness + 0.3).clamp(0.52, 0.94))
      .toColor();
  final isDark =
      ThemeData.estimateBrightnessForColor(middleColor) == Brightness.dark;
  return TextStatusBackgroundPreset(
    id: 'custom-${baseColor.toARGB32().toRadixString(16)}',
    label: 'Custom',
    colors: <Color>[deepColor, middleColor, brightColor],
    accentColor: accentColor,
    suggestedTextColor: isDark ? Colors.white : AppPalette.ink,
  );
}

TextStatusBackgroundPreset resolveTextStatusBackgroundForStyle(
  StatusTextStyle style,
  Color accentColor,
) {
  final backgroundColor = style.backgroundColor;
  if (backgroundColor != null) {
    // Deliberately not passing style.useSolidBackground here. That flag is
    // the plate behind the *text* (the fill button, and the same field the
    // media composer's text overlay uses); it was also being read as
    // "make the canvas a flat colour instead of a gradient". One flag
    // doing two jobs is why cycling the background colour switched the
    // text plate off: the cycle sets the canvas back to a gradient, and
    // that turned off the user's plate with it.
    return buildCustomTextStatusBackgroundPreset(backgroundColor);
  }
  return resolveTextStatusBackgroundPreset(style.backgroundId, accentColor);
}

/// The copy shown on an empty canvas. Exposed so a composer can measure
/// the same string the canvas will lay out when sizing its own editor.
const String kTextStatusCanvasPlaceholder = 'Write something worth pausing for';

class TextStatusCanvas extends StatelessWidget {
  const TextStatusCanvas({
    required this.text,
    required this.style,
    required this.accentColor,
    this.borderRadius = const BorderRadius.all(Radius.circular(32)),
    this.placeholder = kTextStatusCanvasPlaceholder,
    this.padding,
    this.showFrame = true,
    this.showText = true,
    this.textChild,
    super.key,
  });

  final String text;
  final StatusTextStyle style;
  final Color accentColor;
  final BorderRadius borderRadius;
  final String placeholder;
  final EdgeInsets? padding;
  final bool showFrame;

  /// Whether the text block renders at all.
  ///
  /// The text status composer turns this off while the editor card is open
  /// over the canvas: passing an empty child instead still drew the
  /// panel's own capsule, leaving a stray empty pill floating in the
  /// middle of the preview.
  final bool showText;
  final Widget? textChild;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = resolveTextStatusBackgroundForStyle(style, accentColor);
    final fontLook = resolveTextStatusFontLook(style.fontId);
    final visibleText = text.trim().isEmpty ? placeholder : text.trim();
    final textColor =
        style.layout == StatusTextLayout.note && style.textColor == null
            ? AppPalette.ink
            : (style.textColor ?? background.suggestedTextColor);

    return LayoutBuilder(
      builder: (context, constraints) {
        final textStyle = _buildTextStyle(
          theme: theme,
          style: style,
          fontLook: fontLook,
          textColor: textColor,
          shortestSide: math.min(
            constraints.maxWidth,
            constraints.maxHeight,
          ),
          textLength: visibleText.length,
        );
        final textAlignment = _textAlignFor(style.alignment);
        final contentPadding =
            padding ?? _paddingForLayout(style.layout, constraints.biggest);
        final resolvedTextChild = textChild ??
            Text(
              visibleText,
              key: const Key('updates_text_status_canvas_text'),
              textAlign: textAlignment,
              style: textStyle,
            );

        // Animated rather than a plain DecoratedBox: cycling the
        // background used to repaint the whole canvas in one frame, which
        // read as a flash. AnimatedContainer tweens the colour/gradient on
        // the feature's shared timing instead.
        return AnimatedContainer(
          duration: kStatusMotionDuration,
          curve: kStatusMotionCurve,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            color: background.isSolid ? background.colors.first : null,
            gradient: background.isSolid
                ? null
                : LinearGradient(
                    colors: background.colors,
                    begin: background.begin,
                    end: background.end,
                  ),
            border: showFrame
                ? Border.all(color: Colors.white.withValues(alpha: 0.08))
                : null,
            boxShadow: showFrame
                ? <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 26,
                      offset: const Offset(0, 14),
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: borderRadius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _DecorativeBackground(
                  layout: style.layout,
                  background: background,
                ),
                if (showText)
                  Padding(
                    padding: contentPadding,
                    child: Align(
                      alignment: _alignmentFor(style.alignment, style.layout),
                      child: FractionallySizedBox(
                        widthFactor: _textWidthFactor(style.layout),
                        alignment: _alignmentFor(style.alignment, style.layout),
                        // A short status still centers freely inside the
                        // panel exactly as before -- this cap only ever
                        // bites once typed text would otherwise need more
                        // room than the canvas actually has, which used to
                        // just paint straight past the card's edges instead
                        // of stopping anywhere. Past the cap the panel holds
                        // at its max height and the text scrolls inside it,
                        // so "how much you've typed" never depends on
                        // outgrowing a frame that can't actually grow
                        // further than the screen itself.
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: constraints.maxHeight * 0.86,
                          ),
                          child: _TextPanel(
                            layout: style.layout,
                            background: background,
                            showPanel: style.useSolidBackground,
                            child: SingleChildScrollView(
                              child: resolvedTextChild,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  static TextStyle _buildTextStyle({
    required ThemeData theme,
    required StatusTextStyle style,
    required TextStatusFontLook fontLook,
    required Color textColor,
    required double shortestSide,
    required int textLength,
  }) {
    final clampedScale =
        style.sizeScale.clamp(kStatusTextMinSizeScale, kStatusTextMaxSizeScale);
    var baseSize = shortestSide * 0.124;
    // Each length tier is its own target scale for that much text, not a
    // further cut on top of every shorter tier's cut already applied --
    // these used to be separate `if`s that all fired at once past 220
    // characters, compounding to ~27% of base size instead of the
    // intended 56% and shrinking any longer status down to a tiny pill of
    // text in an otherwise empty card.
    if (textLength > 220) {
      baseSize *= 0.56;
    } else if (textLength > 140) {
      baseSize *= 0.64;
    } else if (textLength > 88) {
      baseSize *= 0.76;
    } else if (textLength > 44) {
      baseSize *= 0.88;
    }

    final baseStyle =
        (theme.textTheme.displaySmall ?? const TextStyle()).copyWith(
      color: textColor,
      // Floored, not just scaled: the smallest slider position has to land
      // on a real, legible size rather than whatever the canvas ratio
      // happens to produce on that screen.
      fontSize: (baseSize * clampedScale)
          .clamp(kStatusTextMinFontSize, double.infinity),
      // The chosen weight, not a fixed one -- the font look may set its own
      // below, so this is applied again after look.apply to make the user's
      // choice win.
      fontWeight: style.fontWeight,
      height: 1.06,
      shadows: <Shadow>[
        Shadow(
          color: Colors.black.withValues(alpha: 0.16),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
    );
    // Re-applied after the font look, which sets a weight of its own --
    // the user's explicit choice has to win over the look's default.
    return fontLook.apply(baseStyle).copyWith(fontWeight: style.fontWeight);
  }

  static EdgeInsets _paddingForLayout(StatusTextLayout layout, Size size) {
    final horizontal = size.width * 0.1;
    return switch (layout) {
      StatusTextLayout.classic => EdgeInsets.symmetric(
          horizontal: horizontal, vertical: size.height * 0.1),
      StatusTextLayout.poster => EdgeInsets.fromLTRB(
          horizontal, size.height * 0.14, horizontal, size.height * 0.12),
      StatusTextLayout.banner => EdgeInsets.symmetric(
          horizontal: horizontal * 0.86, vertical: size.height * 0.12),
      StatusTextLayout.invitation => EdgeInsets.fromLTRB(horizontal * 0.9,
          size.height * 0.12, horizontal * 0.9, size.height * 0.12),
      StatusTextLayout.spotlight => EdgeInsets.symmetric(
          horizontal: horizontal * 0.86, vertical: size.height * 0.1),
      StatusTextLayout.note => EdgeInsets.fromLTRB(
          horizontal, size.height * 0.12, horizontal, size.height * 0.12),
    };
  }

  static Alignment _alignmentFor(
    StatusTextAlignment alignment,
    StatusTextLayout layout,
  ) {
    if (layout == StatusTextLayout.poster) {
      return Alignment.bottomLeft;
    }
    return switch (alignment) {
      StatusTextAlignment.left => Alignment.centerLeft,
      StatusTextAlignment.center => Alignment.center,
      StatusTextAlignment.right => Alignment.centerRight,
    };
  }

  static TextAlign _textAlignFor(StatusTextAlignment alignment) {
    return switch (alignment) {
      StatusTextAlignment.left => TextAlign.left,
      StatusTextAlignment.center => TextAlign.center,
      StatusTextAlignment.right => TextAlign.right,
    };
  }

  static double _textWidthFactor(StatusTextLayout layout) {
    return switch (layout) {
      StatusTextLayout.classic => 0.92,
      StatusTextLayout.poster => 0.82,
      StatusTextLayout.banner => 0.98,
      StatusTextLayout.invitation => 0.88,
      StatusTextLayout.spotlight => 0.92,
      StatusTextLayout.note => 0.88,
    };
  }
}

TextStyle buildTextStatusTextStyle({
  required ThemeData theme,
  required StatusTextStyle style,
  required Color accentColor,
  required double shortestSide,
  required int textLength,
}) {
  final background = resolveTextStatusBackgroundForStyle(style, accentColor);
  final textColor =
      style.layout == StatusTextLayout.note && style.textColor == null
          ? AppPalette.ink
          : (style.textColor ?? background.suggestedTextColor);
  return TextStatusCanvas._buildTextStyle(
    theme: theme,
    style: style,
    fontLook: resolveTextStatusFontLook(style.fontId),
    textColor: textColor,
    shortestSide: shortestSide,
    textLength: textLength,
  );
}

EdgeInsets textStatusPaddingForLayout(StatusTextLayout layout, Size size) =>
    TextStatusCanvas._paddingForLayout(layout, size);

Alignment textStatusAlignmentForLayout(
  StatusTextAlignment alignment,
  StatusTextLayout layout,
) =>
    TextStatusCanvas._alignmentFor(alignment, layout);

TextAlign textStatusTextAlign(StatusTextAlignment alignment) =>
    TextStatusCanvas._textAlignFor(alignment);

double textStatusTextWidthFactor(StatusTextLayout layout) =>
    TextStatusCanvas._textWidthFactor(layout);

class _TextPanel extends StatelessWidget {
  const _TextPanel({
    required this.layout,
    required this.background,
    required this.showPanel,
    required this.child,
  });

  final StatusTextLayout layout;
  final TextStatusBackgroundPreset background;

  /// Whether the layout's plate is painted behind the text.
  ///
  /// Off by default so a status starts as bare text on its background,
  /// matching the editor -- the plate used to appear only once the
  /// keyboard went down, so the thing being edited and the preview of it
  /// disagreed. The fill control opts into it.
  final bool showPanel;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!showPanel) {
      return child;
    }
    final panel = switch (layout) {
      StatusTextLayout.classic => child,
      StatusTextLayout.poster => DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: background.accentColor.withValues(alpha: 0.92),
                width: 6,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: 18),
            child: child,
          ),
        ),
      StatusTextLayout.banner => Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      StatusTextLayout.invitation => Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: background.accentColor.withValues(alpha: 0.6),
              width: 1.6,
            ),
          ),
          child: child,
        ),
      StatusTextLayout.spotlight => DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: background.accentColor.withValues(alpha: 0.28),
                blurRadius: 42,
                spreadRadius: 10,
              ),
            ],
          ),
          child: child,
        ),
      StatusTextLayout.note => Transform.rotate(
          angle: -0.02,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
            ),
            child: child,
          ),
        ),
    };
    return panel;
  }
}

class _DecorativeBackground extends StatelessWidget {
  const _DecorativeBackground({
    required this.layout,
    required this.background,
  });

  final StatusTextLayout layout;
  final TextStatusBackgroundPreset background;

  @override
  Widget build(BuildContext context) {
    if (background.isSolid) {
      return const SizedBox.shrink();
    }
    // Every shape below is placed with a hardcoded offset from the canvas
    // edge, and the canvas is edge-to-edge -- so `top: 26` landed a solid
    // accent bar directly behind the clock, and `top: -20` slid a glow orb
    // under the wifi and battery icons. The offsets are measured from the
    // usable area instead, so they mean the same thing on a Dynamic
    // Island, a notch, an Android punch-hole and a flat-top tablet.
    //
    // The gradient itself still runs edge-to-edge (it is painted by the
    // parent, not here) -- only the shapes move. That keeps the background
    // full-bleed, which is what the posted story shows.
    final insets = MediaQuery.viewPaddingOf(context);
    return IgnorePointer(
      child: Padding(
        padding: EdgeInsets.only(top: insets.top, bottom: insets.bottom),
        // Padding alone is not enough: several shapes use a negative
        // offset to bleed off the edge on purpose, which would still reach
        // back up into the status bar. Clipping the layer's top edge lets
        // them keep bleeding sideways and downwards while making it
        // structurally impossible to paint behind the indicators. A plain
        // rect clip rather than a fade: no saveLayer, and this canvas
        // rebuilds on every keystroke in the composer.
        child: ClipRect(
          clipper: const _TopEdgeClipper(),
          clipBehavior: Clip.hardEdge,
          child: switch (layout) {
            StatusTextLayout.classic => Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    top: -20,
                    right: -10,
                    child: _GlowOrb(
                      size: 180,
                      color: background.accentColor.withValues(alpha: 0.22),
                    ),
                  ),
                  Positioned(
                    left: -48,
                    bottom: -52,
                    child: _GlowOrb(
                      size: 220,
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                ],
              ),
            StatusTextLayout.poster => Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    top: 26,
                    left: 24,
                    child: Transform.rotate(
                      angle: -0.18,
                      child: Container(
                        width: 110,
                        height: 12,
                        decoration: BoxDecoration(
                          color: background.accentColor.withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: -34,
                    bottom: -28,
                    child: _GlowOrb(
                      size: 210,
                      color: Colors.black.withValues(alpha: 0.14),
                    ),
                  ),
                ],
              ),
            StatusTextLayout.banner => Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    top: 34,
                    left: 34,
                    child: Container(
                      width: 94,
                      height: 94,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 28,
                    bottom: 36,
                    child: Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: background.accentColor.withValues(alpha: 0.14),
                      ),
                    ),
                  ),
                ],
              ),
            StatusTextLayout.invitation => Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                            width: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 28,
                    right: 26,
                    child: _DotCluster(color: background.accentColor),
                  ),
                  Positioned(
                    left: 26,
                    bottom: 26,
                    child: _DotCluster(
                        color: Colors.white.withValues(alpha: 0.84)),
                  ),
                ],
              ),
            StatusTextLayout.spotlight => Stack(
                fit: StackFit.expand,
                children: [
                  Align(
                    child: _GlowOrb(
                      size: 260,
                      color: background.accentColor.withValues(alpha: 0.26),
                    ),
                  ),
                  Positioned(
                    top: 36,
                    right: 36,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                ],
              ),
            StatusTextLayout.note => Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    top: 28,
                    left: 28,
                    child: _TapeStrip(color: background.accentColor),
                  ),
                  Positioned(
                    top: 28,
                    right: 28,
                    child:
                        _TapeStrip(color: Colors.white.withValues(alpha: 0.82)),
                  ),
                  Positioned(
                    bottom: -48,
                    right: -28,
                    child: _GlowOrb(
                      size: 180,
                      color: background.accentColor.withValues(alpha: 0.14),
                    ),
                  ),
                ],
              ),
          },
        ),
      ),
    );
  }
}

/// Clips only the top edge of its child, leaving the other three sides
/// free so decorations can still bleed off them.
class _TopEdgeClipper extends CustomClipper<Rect> {
  const _TopEdgeClipper();

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
        -size.width,
        0,
        size.width * 2,
        size.height * 2,
      );

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: <Color>[
            color,
            color.withValues(alpha: color.a * 0.14),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

class _DotCluster extends StatelessWidget {
  const _DotCluster({
    required this.color,
  });

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: List<Widget>.generate(
        6,
        (index) => Container(
          width: index.isEven ? 8 : 6,
          height: index.isEven ? 8 : 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.66 - (index * 0.08)),
          ),
        ),
      ),
    );
  }
}

class _TapeStrip extends StatelessWidget {
  const _TapeStrip({
    required this.color,
  });

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.14,
      child: Container(
        width: 70,
        height: 16,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.34),
          borderRadius: BorderRadius.circular(5),
        ),
      ),
    );
  }
}
